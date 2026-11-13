#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stringio'
require_relative '../asc-store-listing'

def assert(value, label)
  raise "Assertion failed: #{label}" unless value
end

def expect_error(label, message)
  yield
  raise "Expected failure: #{label}"
rescue StoreListing::Error => e
  assert(e.message.include?(message), "#{label}: #{e.message}")
end

# Lengths and content rules.
listing = StoreListing.load
assert(StoreListing.problems(listing).empty?, 'committed copy passes')
assert(StoreListing.problems(listing.merge('name' => 'x' * 31)).any? { |e| e.start_with?('name is 31') }, 'name over 30')
assert(StoreListing.problems(listing.merge('keywords' => 'a' * 101)).any? { |e| e.include?('keywords is 101') }, 'keywords over 100')
assert(StoreListing.problems(listing.merge('promotionalText' => 'x' * 170)).empty?, 'exactly at the limit passes')
assert(StoreListing.problems(listing.merge('keywords' => 'split, loan')).any? { |e| e.include?('without spaces') }, 'keyword spacing')
assert(StoreListing.problems(listing.merge('keywords' => 'split,Split')).any? { |e| e.include?('repeat') }, 'keyword repeat')
assert(StoreListing.problems(listing.merge('description' => 'Pay asha@okicici now')).any? { |e| e.include?('UPI id') }, 'VPA rejected')
assert(StoreListing.problems(listing.reject { |k, _| k == 'subtitle' }).include?('subtitle is missing'), 'missing field')
assert(StoreListing.problems(listing.merge('supportUrl' => 'http://example.com/')).any? { |e| e.include?('supportUrl') }, 'URL host')

# Field-level diff.
live = listing.merge('name' => 'Settlo', 'description' => 'Old', 'secondaryCategory' => nil)
lines = StoreListing.diff(live, listing)
assert(lines.include?('name: "Settlo" -> "SabkiJeb"'), 'short field shows both values')
assert(lines.include?("description: changed (3 -> #{listing['description'].length} characters)"), 'long field summarised')
assert(lines.include?('secondaryCategory: (none) -> "LIFESTYLE"'), 'missing live value')
assert(lines.include?('subtitle: unchanged'), 'unchanged field')
assert(lines.length == StoreListing::FIELDS.length, 'one line per field')

# Uploader against an in-memory App Store Connect.
key = OpenSSL::PKey::EC.generate('prime256v1')
env = { 'ASC_KEY_P8' => key.to_pem, 'ASC_KEY_ID' => 'mock-key', 'ASC_ISSUER_ID' => 'mock-issuer' }
row = ->(type, id, attrs = {}) { { 'type' => type, 'id' => id, 'attributes' => attrs } }

def world(row)
  {
    versions: [row.call('appStoreVersions', 'v1', 'versionString' => '0.1.0', 'appStoreState' => 'PREPARE_FOR_SUBMISSION')],
    info_locs: [row.call('appInfoLocalizations', 'il', 'locale' => 'en-US', 'name' => 'Settlo')],
    version_locs: [], categories: {}, writes: [], reject_name: false
  }
end

def transport_for(state, row)
  ok = ->(data) { Struct.new(:code, :body).new('200', JSON.generate(data: data)) }
  lambda do |uri, req|
    data = req.body && JSON.parse(req.body).fetch('data')
    path = uri.path
    if req.method == 'GET'
      return ok.call(case path
                     when '/v1/apps' then [row.call('apps', 'app')]
                     when '/v1/apps/app/appInfos'
                       [row.call('appInfos', 'live', 'state' => 'READY_FOR_DISTRIBUTION'), row.call('appInfos', 'info', 'state' => 'PREPARE_FOR_SUBMISSION')]
                     when '/v1/apps/app/appStoreVersions' then state[:versions]
                     when '/v1/appInfos/info/appInfoLocalizations' then state[:info_locs]
                     when '/v1/appStoreVersions/v1/appStoreVersionLocalizations' then state[:version_locs]
                     when %r{\A/v1/appInfos/info/(primaryCategory|secondaryCategory)\z}
                       id = state[:categories][Regexp.last_match(1)]
                       id && row.call('appCategories', id)
                     else raise "Unexpected mock GET #{path}"
                     end)
    end
    state[:writes] << [req.method, path, data]
    return Struct.new(:code, :body).new('409', '{"errors":[]}') if state[:reject_name] && data.dig('attributes', 'name')

    case path
    when '/v1/appInfoLocalizations/il' then state[:info_locs][0]['attributes'].merge!(data['attributes'])
    when '/v1/appStoreVersionLocalizations'
      state[:version_locs] << row.call('appStoreVersionLocalizations', 'vl', data['attributes'])
      return ok.call(state[:version_locs].last)
    when '/v1/appStoreVersionLocalizations/vl' then state[:version_locs][0]['attributes'].merge!(data['attributes'])
    when '/v1/appStoreVersions/v1' then state[:versions][0]['attributes'].merge!(data['attributes'])
    when '/v1/appStoreVersions'
      state[:versions] << row.call('appStoreVersions', 'v1', data['attributes'].merge('appStoreState' => 'PREPARE_FOR_SUBMISSION'))
      return ok.call(state[:versions].last)
    when '/v1/appInfos/info'
      data['relationships'].each { |name, rel| state[:categories][name] = rel.dig('data', 'id') }
    else raise "Unexpected mock #{req.method} #{path}"
    end
    ok.call(data)
  end
end

run = lambda do |state, dry_run, extra = {}|
  out = StringIO.new
  client = TestFlightExternal::Client.new(env: env, transport: transport_for(state, row))
  StoreListing::Uploader.new(client, listing, env: env.merge(extra), output: out).run(dry_run: dry_run)
  out.string
end

state = world(row)
out = run.call(state, true)
assert(state[:writes].empty?, 'dry run never writes')
assert(out.include?('name: "Settlo" -> "SabkiJeb"') && out.include?('Dry run'), 'dry run prints the diff')
assert(!out.include?(listing['description']), 'dry run does not print long copy')

out = run.call(state, false)
assert(state[:writes].first[2]['attributes'] == { 'name' => 'SabkiJeb' }, 'name is written first and alone')
assert(state[:writes].any? { |w| w[0] == 'POST' && w[1] == '/v1/appStoreVersionLocalizations' && w[2]['attributes']['locale'] == 'en-US' }, 'version localization created')
assert(state[:categories] == { 'primaryCategory' => 'FINANCE', 'secondaryCategory' => 'LIFESTYLE' }, 'categories set')
assert(state[:versions][0]['attributes']['copyright'] == listing['copyright'], 'copyright set')
assert(out.include?('Updated: name, subtitle'), 'live run reports updated fields')
state[:writes].clear
assert(run.call(state, false).include?('Already up to date') && state[:writes].empty?, 'second run is a no-op')

state = world(row)
state[:reject_name] = true
expect_error('name rejection', 'Apple rejected the app name "SabkiJeb"') { run.call(state, false) }
assert(state[:writes].length == 1, 'nothing else written after a name rejection')

# A created version is reported, not hidden behind "nothing else changed".
state = world(row)
state[:versions] = [row.call('appStoreVersions', 'old', 'appStoreState' => 'READY_FOR_SALE')]
state[:reject_name] = true
expect_error('name rejection after creating a version', 'already created iOS App Store version 1.0 (v1)') do
  run.call(state, false, 'CREATE_VERSION' => '1.0')
end
assert(state[:writes].map { |w| w[0..1] } == [%w[POST /v1/appStoreVersions], %w[PATCH /v1/appInfoLocalizations/il]], 'only the version and the name were attempted')

state = world(row)
state[:versions] = [row.call('appStoreVersions', 'old', 'appStoreState' => 'READY_FOR_SALE')]
expect_error('dry run with no version', 'a dry run never creates one') { run.call(state, true, 'CREATE_VERSION' => '1.0') }
expect_error('live run without create_version', 'No editable iOS App Store version') { run.call(state, false) }
assert(state[:writes].empty?, 'no version created without an explicit live request')
out = run.call(state, false, 'CREATE_VERSION' => '1.0')
assert(state[:writes].first[0..1] == ['POST', '/v1/appStoreVersions'], 'live run creates the version first')
assert(out.include?('Created iOS App Store version 1.0'), 'version creation is logged')

puts 'asc-store-listing tests passed'

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stringio'
require_relative '../asc-expire-builds'

def assert(value, label)
  raise "Assertion failed: #{label}" unless value
end

def expect_error(label, message)
  yield
  raise "Expected failure: #{label}"
rescue ExpireBuilds::Error => e
  assert(e.message.include?(message), "#{label}: #{e.message}")
end

build = lambda do |number, state: 'VALID', expired: false|
  { 'type' => 'builds', 'id' => "b#{number}", 'attributes' => { 'version' => number.to_s, 'processingState' => state, 'expired' => expired },
    'relationships' => { 'preReleaseVersion' => { 'data' => { 'type' => 'preReleaseVersions', 'id' => 'pv' } } } }
end

# Selection logic.
assert(ExpireBuilds.keep_list(' 12, 14 ') == %w[12 14], 'keep list parsed')
expect_error('empty keep list', 'keep_versions') { ExpireBuilds.keep_list('') }
expect_error('non-numeric keep list', 'keep_versions') { ExpireBuilds.keep_list('12,rc6') }
builds = [build.call(6), build.call(11, expired: true), build.call(12), build.call(13), build.call(14, state: 'PROCESSING')]
actions = ExpireBuilds.plan(builds, %w[12]).to_h { |b, a| [b.dig('attributes', 'version'), a] }
assert(actions == { '6' => 'expire', '11' => 'already expired', '12' => 'keep', '13' => 'expire', '14' => 'skip (PROCESSING)' }, 'lower and higher builds expire')
expect_error('missing kept build', 'Kept build(s) 21 not found') { ExpireBuilds.plan(builds, %w[21]) }

# Dry and real runs against an in-memory App Store Connect.
key = OpenSSL::PKey::EC.generate('prime256v1')
env = { 'ASC_KEY_P8' => key.to_pem, 'ASC_KEY_ID' => 'mock-key', 'ASC_ISSUER_ID' => 'mock-issuer', 'KEEP_BUILDS' => '12' }
patches = []
transport = lambda do |uri, req|
  ok = ->(data) { Struct.new(:code, :body).new('200', JSON.generate(data: data)) }
  if req.method == 'PATCH'
    data = JSON.parse(req.body).fetch('data')
    patches << uri.path
    builds.find { |b| b['id'] == data['id'] }['attributes']['expired'] = true
    return ok.call(data)
  end
  ok.call(case uri.path
          when '/v1/apps' then [{ 'type' => 'apps', 'id' => 'app' }]
          when '/v1/preReleaseVersions' then [{ 'type' => 'preReleaseVersions', 'id' => 'pv', 'attributes' => { 'version' => '0.1.0' } }]
          when '/v1/builds' then builds
          else raise "Unexpected mock GET #{uri.path}"
          end)
end
client = TestFlightExternal::Client.new(env: env, transport: transport)

out = StringIO.new
ExpireBuilds.run(client, env: env, output: out)
assert(patches.empty?, 'dry run never writes')
assert(out.string.include?('Build 12 (0.1.0, VALID, expired=false): keep') && out.string.include?('would expire 2'), 'dry run prints the plan')

out = StringIO.new
ExpireBuilds.run(client, env: env.merge('EXPIRE_DRY_RUN' => 'false'), output: out)
assert(patches == %w[/v1/builds/b6 /v1/builds/b13], 'only unkept processed builds expire')
patches.clear
ExpireBuilds.run(client, env: env.merge('EXPIRE_DRY_RUN' => 'false'), output: StringIO.new)
assert(patches.empty?, 'second run is a no-op')

puts 'asc-expire-builds tests passed'

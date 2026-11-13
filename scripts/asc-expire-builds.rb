#!/usr/bin/env ruby
# frozen_string_literal: true

# Expires every unexpired, processed iOS TestFlight build except KEEP_BUILDS.
#   KEEP_BUILDS=12 EXPIRE_DRY_RUN=false ruby scripts/asc-expire-builds.rb
# The $PROGRAM_NAME guard in that script makes this a plain library load.
require_relative 'asc-testflight-external'

module ExpireBuilds
  Error = TestFlightExternal::Error

  def self.keep_list(raw)
    numbers = raw.to_s.split(',').map(&:strip)
    raise Error, 'keep_versions must be comma-separated build numbers, e.g. 12' if numbers.empty? || numbers.any? { |n| !n.match?(/\A[0-9]+\z/) }
    numbers
  end

  # Returns [build, action] for every build; only 'expire' rows are changed.
  def self.plan(builds, keep)
    present = builds.map { |b| b.dig('attributes', 'version') }
    missing = keep - present
    # A typo in keep_versions must not expire the build the owner meant to keep.
    raise Error, "Kept build(s) #{missing.join(', ')} not found; nothing changed" unless missing.empty?
    builds.map do |build|
      attrs = build.fetch('attributes')
      action = if keep.include?(attrs['version']) then 'keep'
               elsif attrs['expired'] then 'already expired'
               elsif attrs['processingState'] != 'VALID' then "skip (#{attrs['processingState']})"
               else 'expire'
               end
      [build, action]
    end
  end

  def self.run(client, env: ENV, output: $stdout)
    keep = keep_list(env.fetch('KEEP_BUILDS', ''))
    dry_run = env.fetch('EXPIRE_DRY_RUN', 'true') != 'false'
    apps = client.list('/v1/apps', 'filter[bundleId]' => 'app.settlo')
    raise Error, 'Expected exactly one app.settlo app' unless apps.length == 1
    app_id = apps.first.fetch('id')
    versions = client.list('/v1/preReleaseVersions', 'filter[app]' => app_id, 'filter[platform]' => 'IOS')
                     .to_h { |v| [v.fetch('id'), v.dig('attributes', 'version')] }
    builds = client.list('/v1/builds', 'filter[app]' => app_id, 'filter[preReleaseVersion.platform]' => 'IOS',
                                       'include' => 'preReleaseVersion', 'limit' => '200')
    rows = plan(builds, keep).sort_by { |build, _| build.dig('attributes', 'version').to_i }
    rows.each do |build, action|
      attrs = build['attributes']
      version = versions[build.dig('relationships', 'preReleaseVersion', 'data', 'id')] || '?'
      output.puts "Build #{attrs['version']} (#{version}, #{attrs['processingState']}, expired=#{attrs['expired']}): #{action}"
    end
    targets = rows.select { |_, action| action == 'expire' }.map(&:first)
    return output.puts("Dry run: would expire #{targets.length} build(s); nothing changed") if dry_run

    targets.each do |build|
      id = build.fetch('id')
      updated = client.request(:patch, "/v1/builds/#{id}", data: { type: 'builds', id: id, attributes: { expired: true } }).fetch('data')
      raise Error, "Build #{build.dig('attributes', 'version')} expiration was not confirmed" unless updated.dig('attributes', 'expired') == true
      output.puts "Expired build #{build.dig('attributes', 'version')}"
    end
    output.puts "Expired #{targets.length} build(s)"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ExpireBuilds.run(TestFlightExternal::Client.new)
  rescue ExpireBuilds::Error => e
    warn e.message
    exit 1
  rescue StandardError
    # Exception messages and backtraces can contain credentials or server response data.
    warn 'Build expiry failed; check configuration and App Store Connect privately'
    exit 1
  end
end

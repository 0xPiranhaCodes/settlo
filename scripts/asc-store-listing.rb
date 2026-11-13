#!/usr/bin/env ruby
# frozen_string_literal: true

# Upserts the App Store listing in docs/store/ios-en-US.json (#266).
#   ruby scripts/asc-store-listing.rb --check   # lengths only, no network
#   STORE_LISTING_DRY_RUN=false ruby scripts/asc-store-listing.rb
require 'json'
# The $PROGRAM_NAME guard in that script makes this a plain library load.
require_relative 'asc-testflight-external'

module StoreListing
  Error = TestFlightExternal::Error
  ROOT = File.expand_path('..', __dir__)
  DEFAULT_PATH = File.join(ROOT, 'docs/store/ios-en-US.json')

  # Apple's App Store Connect limits, in characters.
  LIMITS = { 'name' => 30, 'subtitle' => 30, 'promotionalText' => 170, 'description' => 4000, 'keywords' => 100 }.freeze
  APP_INFO_FIELDS = %w[name subtitle privacyPolicyUrl].freeze
  VERSION_LOC_FIELDS = %w[description keywords promotionalText supportUrl marketingUrl].freeze
  VERSION_FIELDS = %w[copyright].freeze
  CATEGORY_FIELDS = %w[primaryCategory secondaryCategory].freeze
  FIELDS = APP_INFO_FIELDS + VERSION_LOC_FIELDS + VERSION_FIELDS + CATEGORY_FIELDS
  EDITABLE = %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED INVALID_BINARY].freeze
  SHORT = 170

  def self.problems(listing)
    errors = FIELDS.reject { |f| listing[f].is_a?(String) && !listing[f].strip.empty? }.map { |f| "#{f} is missing" }
    LIMITS.each do |field, max|
      length = listing[field].to_s.length
      errors << "#{field} is #{length} characters; Apple allows #{max}" if length > max
    end
    keywords = listing['keywords'].to_s.split(',')
    errors << 'keywords must be comma-separated without spaces or empty entries' if keywords.any? { |k| k.empty? || k != k.strip }
    errors << 'keywords repeat an entry' if keywords.map(&:downcase).uniq.length != keywords.length
    %w[supportUrl marketingUrl privacyPolicyUrl].each do |field|
      errors << "#{field} must be an https://sabkijeb.app/ URL" unless listing[field].to_s.start_with?('https://sabkijeb.app/')
    end
    # A VPA is handle@psp with no dot after it; support@sabkijeb.app is an email.
    errors << 'copy must not contain a UPI id' if FIELDS.any? { |f| listing[f].to_s.match?(/[A-Za-z0-9._-]+@[A-Za-z]{2,64}(?![A-Za-z.])/) }
    errors
  end

  def self.show(value)
    value.nil? ? '(none)' : value.inspect
  end

  # One line per field; long copy is summarised by length, never printed twice.
  def self.diff(live, proposed)
    FIELDS.map do |field|
      before, after = live[field], proposed[field]
      if before == after
        "#{field}: unchanged"
      elsif [before, after].any? { |v| v.to_s.length > SHORT }
        "#{field}: changed (#{before.to_s.length} -> #{after.to_s.length} characters)"
      else
        "#{field}: #{show(before)} -> #{show(after)}"
      end
    end
  end

  def self.load(path = DEFAULT_PATH)
    listing = JSON.parse(File.read(path))
    errors = problems(listing)
    raise Error, "#{File.basename(path)}: #{errors.join('; ')}" unless errors.empty?
    listing
  end

  class Uploader
    def initialize(client, listing, env: ENV, output: $stdout)
      @client, @listing, @env, @output = client, listing, env, output
    end

    def one(rows, message)
      raise Error, message unless rows.length == 1
      rows.first
    end

    def state(row)
      attrs = row.fetch('attributes', {})
      attrs['state'] || attrs['appVersionState'] || attrs['appStoreState']
    end

    def en_us(rows)
      found = rows.select { |row| row.dig('attributes', 'locale') == 'en-US' }
      raise Error, 'Multiple en-US localizations found' if found.length > 1
      found.first
    end

    def editable_version(app_id, dry_run)
      versions = @client.list("/v1/apps/#{app_id}/appStoreVersions", 'filter[platform]' => 'IOS')
      editable = versions.select { |row| EDITABLE.include?(state(row)) }
      raise Error, 'More than one editable iOS App Store version; resolve in App Store Connect first' if editable.length > 1
      return editable.first if editable.first

      wanted = @env.fetch('CREATE_VERSION', '')
      if dry_run || wanted.empty?
        raise Error, 'No editable iOS App Store version (Prepare for Submission). Create one in App Store Connect, ' \
                     'or rerun with dry_run=false and create_version set; a dry run never creates one'
      end
      raise Error, 'create_version must look like 1.0 or 1.0.0' unless wanted.match?(/\A\d+\.\d+(\.\d+)?\z/)
      created = @client.request(:post, '/v1/appStoreVersions', data: {
        type: 'appStoreVersions', attributes: { platform: 'IOS', versionString: wanted },
        relationships: { app: { data: { type: 'apps', id: app_id } } }
      }).fetch('data')
      @output.puts "Created iOS App Store version #{wanted} (#{created.fetch('id')}) because none was editable"
      created
    end

    def category(info_id, which)
      @client.request(:get, "/v1/appInfos/#{info_id}/#{which}").fetch('data')&.fetch('id')
    end

    def run(dry_run:)
      app = one(@client.list('/v1/apps', 'filter[bundleId]' => 'app.settlo'), 'Expected exactly one app.settlo app')
      app_id = app.fetch('id')
      info = one(@client.list("/v1/apps/#{app_id}/appInfos").select { |row| EDITABLE.include?(state(row)) },
                 'Expected exactly one editable app info; inspect App Store Connect')
      info_id = info.fetch('id')
      version = editable_version(app_id, dry_run)
      version_id = version.fetch('id')
      info_loc = en_us(@client.list("/v1/appInfos/#{info_id}/appInfoLocalizations"))
      version_loc = en_us(@client.list("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations"))

      live = {}
      APP_INFO_FIELDS.each { |f| live[f] = info_loc&.dig('attributes', f) }
      VERSION_LOC_FIELDS.each { |f| live[f] = version_loc&.dig('attributes', f) }
      VERSION_FIELDS.each { |f| live[f] = version.dig('attributes', f) }
      CATEGORY_FIELDS.each { |f| live[f] = category(info_id, f) }
      proposed = @listing.slice(*FIELDS)

      @output.puts "Version #{version.dig('attributes', 'versionString')} (#{state(version)}), live -> proposed:"
      StoreListing.diff(live, proposed).each { |line| @output.puts "  #{line}" }
      changed = FIELDS.reject { |f| live[f] == proposed[f] }
      return @output.puts('Dry run: nothing changed in App Store Connect') if dry_run
      return @output.puts('Already up to date') if changed.empty?

      # The name goes first and alone, so a rejection can only mean the name.
      if changed.include?('name')
        begin
          info_loc = write('appInfoLocalizations', info_loc, { name: proposed['name'] }, 'appInfo', 'appInfos', info_id)
        rescue Error
          raise Error, "Apple rejected the app name #{proposed['name'].inspect} (it may be taken). " \
                       'Nothing else was changed; report to the owner and do not pick a fallback name'
        end
      end
      info_changes = (APP_INFO_FIELDS - ['name']).select { |f| changed.include?(f) }
      write('appInfoLocalizations', info_loc, proposed.slice(*info_changes), 'appInfo', 'appInfos', info_id) unless info_changes.empty?
      loc_changes = VERSION_LOC_FIELDS.select { |f| changed.include?(f) }
      unless loc_changes.empty?
        write('appStoreVersionLocalizations', version_loc, proposed.slice(*loc_changes), 'appStoreVersion', 'appStoreVersions', version_id)
      end
      if changed.include?('copyright')
        @client.request(:patch, "/v1/appStoreVersions/#{version_id}", data: {
          type: 'appStoreVersions', id: version_id, attributes: { copyright: proposed['copyright'] }
        })
      end
      if CATEGORY_FIELDS.any? { |f| changed.include?(f) }
        @client.request(:patch, "/v1/appInfos/#{info_id}", data: {
          type: 'appInfos', id: info_id,
          relationships: CATEGORY_FIELDS.to_h { |f| [f, { data: { type: 'appCategories', id: proposed[f] } }] }
        })
      end
      @output.puts "Updated: #{changed.join(', ')}"
    end

    # PATCH the en-US row, or POST it with the locale; returns the row.
    def write(type, row, attributes, relationship, parent_type, parent_id)
      if row
        @client.request(:patch, "/v1/#{type}/#{row.fetch('id')}", data: { type: type, id: row.fetch('id'), attributes: attributes })
        row
      else
        @client.request(:post, "/v1/#{type}", data: {
          type: type, attributes: attributes.merge(locale: 'en-US'),
          relationships: { relationship => { data: { type: parent_type, id: parent_id } } }
        }).fetch('data')
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    listing = StoreListing.load
    if ARGV.include?('--check')
      StoreListing::LIMITS.each { |field, max| puts "#{field}: #{listing[field].length}/#{max}" }
      exit 0
    end
    dry_run = ENV.fetch('STORE_LISTING_DRY_RUN', 'true') != 'false'
    StoreListing::Uploader.new(TestFlightExternal::Client.new, listing).run(dry_run: dry_run)
  rescue StoreListing::Error => e
    warn e.message
    exit 1
  rescue StandardError
    # Exception messages and backtraces can contain credentials or server response data.
    warn 'Store listing update failed; check configuration and App Store Connect privately'
    exit 1
  end
end

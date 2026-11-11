#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'json'
require 'net/http'
require 'openssl'

# Intentionally separate from the release polling script: existing release jobs stay unchanged.
module TestFlightExternal
  class Error < StandardError; end

  class Client
    ORIGIN = 'https://api.appstoreconnect.apple.com'

    def initialize(env: ENV, transport: nil)
      @env = env
      @transport = transport || lambda do |uri, request|
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 30, read_timeout: 60) do |http|
          http.request(request)
        end
      end
    end

    def token
      segment = ->(value) { Base64.urlsafe_encode64(value, padding: false) }
      now = Time.now.to_i
      input = [
        { alg: 'ES256', kid: @env.fetch('ASC_KEY_ID'), typ: 'JWT' },
        { iss: @env.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }
      ].map { |part| segment.call(part.to_json) }.join('.')
      der = OpenSSL::PKey.read(@env.fetch('ASC_KEY_P8')).sign(OpenSSL::Digest.new('SHA256'), input)
      raw = OpenSSL::ASN1.decode(der).value.map { |int| int.value.to_s(2).rjust(32, "\0") }.join
      "#{input}.#{segment.call(raw)}"
    end

    def request(method, path, query: {}, data: nil)
      uri = URI.join(ORIGIN, path)
      raise Error, 'Refusing an unexpected API URL' unless uri.scheme == 'https' && uri.host == URI(ORIGIN).host && uri.port == 443 && !uri.userinfo
      uri.query = URI.encode_www_form(query) unless query.empty?
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
      req = klass.new(uri, 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json')
      req.body = JSON.generate(data: data) if data
      response = @transport.call(uri, req)
      # Never print bodies: Apple may echo demo credentials or review notes in errors.
      raise Error, 'App Store Connect HTTP 409 conflict; state changed or a submission already exists; inspect App Store Connect privately before rerunning' if response.code.to_i == 409
      raise Error, "App Store Connect HTTP #{response.code.to_i}; inspect App Store Connect privately" unless response.code.to_i.between?(200, 299)
      response.code.to_i == 204 ? {} : JSON.parse(response.body)
    end

    def list(path, query = {})
      rows = []
      loop do
        page = request(:get, path, query: query)
        rows.concat(page.fetch('data'))
        path = page.dig('links', 'next')
        break unless path
        query = {}
      end
      rows
    end
  end

  class Distributor
    CONTACTS = {
      'contactFirstName' => 'ASC_REVIEW_CONTACT_FIRST_NAME',
      'contactLastName' => 'ASC_REVIEW_CONTACT_LAST_NAME',
      'contactPhone' => 'ASC_REVIEW_CONTACT_PHONE',
      'contactEmail' => 'ASC_REVIEW_CONTACT_EMAIL'
    }.freeze
    SUBMITTED = %w[WAITING_FOR_REVIEW IN_REVIEW APPROVED].freeze
    EXTERNAL_READY = %w[WAITING_FOR_BETA_REVIEW IN_BETA_REVIEW BETA_APPROVED READY_FOR_BETA_TESTING IN_BETA_TESTING].freeze

    def initialize(client, env: ENV, output: $stdout)
      @client, @env, @output = client, env, output
    end

    def mask(value)
      return unless @env['GITHUB_ACTIONS'] == 'true'
      escaped = value.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')
      @output.puts "::add-mask::#{escaped}"
    end

    def demo_account
      raw = @env.fetch('HOSTED_TEST_OTP', '')
      mask(raw) unless raw.empty?
      pairs = raw.split(',', -1).map { |entry| entry.strip.split('=', -1) }
      raise Error, 'HOSTED_TEST_OTP must contain number=code pairs' if pairs.empty? || pairs.any? { |p| p.length != 2 || !p[0].match?(/\A[1-9][0-9]{7,14}\z/) || !p[1].match?(/\A[0-9]{6}\z/) }
      pairs.each do |phone, code|
        [phone, "+#{phone}", phone[-10, 10], code].compact.each { |value| mask(value) }
      end
      pairs.first
    end

    def one(rows, message)
      raise Error, message unless rows.length == 1
      rows.first
    end

    def upsert(type, rows, attributes, relationship, parent_type, parent_id)
      existing = rows.select { |row| row.dig('attributes', 'locale') == 'en-US' }
      raise Error, 'Multiple en-US localizations found' if existing.length > 1
      if existing.first
        id = existing.first.fetch('id')
        @client.request(:patch, "/v1/#{type}/#{id}", data: { type: type, id: id, attributes: attributes })
      else
        @client.request(:post, "/v1/#{type}", data: {
          type: type, attributes: attributes.merge(locale: 'en-US'),
          relationships: { relationship => { data: { type: parent_type, id: parent_id } } }
        })
      end
    end

    def withdraw
      number = @env.fetch('BUILD_NUMBER', '')
      raise Error, 'BUILD_NUMBER must be numeric' unless number.match?(/\A[0-9]+\z/)
      app = one(@client.list('/v1/apps', 'filter[bundleId]' => 'app.settlo'), 'Expected exactly one app.settlo app')
      build = one(@client.list('/v1/builds', 'filter[app]' => app.fetch('id'), 'filter[version]' => number,
                              'filter[preReleaseVersion.platform]' => 'IOS'), 'Build missing or ambiguous; select a unique iOS build number')
      prior = build.dig('attributes', 'expired')
      raise Error, 'Unexpected build expiration state' unless [true, false].include?(prior)
      id = build.fetch('id')
      updated = @client.request(:patch, "/v1/builds/#{id}", data: {
        type: 'builds', id: id, attributes: { expired: true }
      }).fetch('data')
      raise Error, 'Build expiration was not confirmed' unless updated['id'] == id && updated.dig('attributes', 'expired') == true
      @output.puts "Build #{number}: expired=#{prior} -> expired=true"
    end

    def run
      action = @env.fetch('TESTFLIGHT_ACTION', 'submit')
      return withdraw if action == 'withdraw'
      raise Error, 'TESTFLIGHT_ACTION must be submit or withdraw' unless action == 'submit'
      number = @env.fetch('BUILD_NUMBER', '')
      group_name = @env.fetch('BETA_GROUP', 'Family Testers')
      what = @env.fetch('WHAT_TO_TEST', '')
      raise Error, 'BUILD_NUMBER must be numeric' unless number.match?(/\A[0-9]+\z/)
      raise Error, 'BETA_GROUP is required' if group_name.strip.empty?
      raise Error, 'WHAT_TO_TEST must contain 1 to 4000 characters' if what.strip.empty? || what.length > 4000
      phone, code = demo_account
      app = one(@client.list('/v1/apps', 'filter[bundleId]' => 'app.settlo'), 'Expected exactly one app.settlo app')
      app_id = app.fetch('id')
      build = one(@client.list('/v1/builds', 'filter[app]' => app_id, 'filter[version]' => number,
                              'filter[preReleaseVersion.platform]' => 'IOS'), 'Build missing or ambiguous; select a unique iOS build number')
      raise Error, 'Build must be VALID and not expired' unless build.dig('attributes', 'processingState') == 'VALID' && build.dig('attributes', 'expired') == false
      build_id = build.fetch('id')
      group = one(@client.list("/v1/apps/#{app_id}/betaGroups").select { |row| row.dig('attributes', 'name') == group_name },
                  'Named beta group is missing or ambiguous; create it in App Store Connect first')
      raise Error, 'Named beta group must be external' unless group.dig('attributes', 'isInternalGroup') == false
      detail = @client.request(:get, "/v1/apps/#{app_id}/betaAppReviewDetail").fetch('data')
      raise Error, 'Set up Beta App Review Information in App Store Connect first' unless detail
      contacts = CONTACTS.each_with_object({}) do |(field, secret), result|
        value = @env.fetch(secret, '')
        result[field] = value unless value.strip.empty?
      end
      effective = detail.fetch('attributes', {}).merge(contacts)
      raise Error, 'Set all four review contact fields in App Store Connect or production ASC_REVIEW_CONTACT_* secrets' unless CONTACTS.keys.all? { |field| !effective[field].to_s.strip.empty? }

      # Complete all remote preflight reads before changing shared app metadata.
      submissions = @client.list('/v1/betaAppReviewSubmissions', 'filter[build]' => build_id)
      beta = @client.request(:get, "/v1/builds/#{build_id}/buildBetaDetail").fetch('data')
      external_state = beta.dig('attributes', 'externalBuildState')
      if external_state == 'BETA_REJECTED' || submissions.any? { |row| row.dig('attributes', 'betaReviewState') == 'REJECTED' }
        raise Error, 'Beta review rejected; resolve the rejection in App Store Connect and upload a new build; this workflow will not resubmit a rejected build'
      end
      unless (EXTERNAL_READY + ['READY_FOR_BETA_SUBMISSION']).include?(external_state)
        raise Error, 'Build cannot be submitted or distributed in its current external state; resolve processing/export compliance or upload a new build if expired or terminal'
      end
      unless submissions.all? { |row| SUBMITTED.include?(row.dig('attributes', 'betaReviewState')) }
        raise Error, 'Unexpected beta review state; inspect App Store Connect before rerunning'
      end
      submitted = submissions.find { |row| SUBMITTED.include?(row.dig('attributes', 'betaReviewState')) }
      state = submitted ? submitted.dig('attributes', 'betaReviewState') : external_state
      group_builds = @client.list("/v1/betaGroups/#{group.fetch('id')}/relationships/builds")

      upsert('betaAppLocalizations', @client.list("/v1/apps/#{app_id}/betaAppLocalizations"), {
        description: 'Split expenses with flatmates, track personal loans, and record repayments with Settlo.',
        feedbackEmail: 'settlo@hellojosh.studio', marketingUrl: 'https://settlo.hellojosh.studio/',
        privacyPolicyUrl: 'https://settlo.hellojosh.studio/privacy/'
      }, 'app', 'apps', app_id)
      @client.request(:patch, "/v1/betaAppReviewDetails/#{detail.fetch('id')}", data: {
        type: 'betaAppReviewDetails', id: detail.fetch('id'), attributes: contacts.merge(
          demoAccountRequired: true, demoAccountName: "+#{phone}", demoAccountPassword: code,
          notes: "Sign in with phone +#{phone} and the fixed test OTP #{code}. No SMS is needed. Use this account to test shared expenses, loans and repayment confirmation. Settlo records payments; UPI payments happen in the user's UPI app."
        )
      })
      upsert('betaBuildLocalizations', @client.list("/v1/builds/#{build_id}/betaBuildLocalizations"),
             { whatsNew: what }, 'build', 'builds', build_id)
      unless group_builds.any? { |row| row['id'] == build_id }
        @client.request(:post, "/v1/betaGroups/#{group.fetch('id')}/relationships/builds", data: [{ type: 'builds', id: build_id }])
      end
      if state == 'READY_FOR_BETA_SUBMISSION'
        submission = @client.request(:post, '/v1/betaAppReviewSubmissions', data: {
          type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: build_id } } }
        }).fetch('data')
        state = submission.dig('attributes', 'betaReviewState')
      end
      allowed = SUBMITTED + EXTERNAL_READY + ['REJECTED']
      raise Error, 'Unexpected beta review state; inspect App Store Connect' unless allowed.include?(state)
      @output.puts "Beta review state: #{state}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    TestFlightExternal::Distributor.new(TestFlightExternal::Client.new).run
  rescue TestFlightExternal::Error => e
    warn e.message
    exit 1
  rescue StandardError
    # Exception messages and backtraces can contain credentials or server response data.
    warn 'TestFlight distribution failed; check configuration and App Store Connect privately'
    exit 1
  end
end

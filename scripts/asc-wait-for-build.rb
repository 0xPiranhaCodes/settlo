#!/usr/bin/env ruby
# frozen_string_literal: true

# Waits until App Store Connect lists build <build-number> of <bundle-id> as VALID, which is
# when TestFlight can offer it. Usage: asc-wait-for-build.rb <bundle-id> <build-number>
# Reads ASC_KEY_P8, ASC_KEY_ID and ASC_ISSUER_ID. Standard library only.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'

bundle_id, build_number = ARGV
abort 'usage: asc-wait-for-build.rb <bundle-id> <build-number>' unless bundle_id && build_number

def token
  segment = ->(value) { Base64.urlsafe_encode64(value, padding: false) }
  now = Time.now.to_i
  input = [
    { alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' },
    { iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 600, aud: 'appstoreconnect-v1' }
  ].map { |part| segment.call(part.to_json) }.join('.')
  der = OpenSSL::PKey.read(ENV.fetch('ASC_KEY_P8')).sign(OpenSSL::Digest.new('SHA256'), input)
  # JWT wants the raw 32-byte r and s, not OpenSSL's DER sequence.
  raw = OpenSSL::ASN1.decode(der).value.map { |int| int.value.to_s(2).rjust(32, "\0") }.join
  "#{input}.#{segment.call(raw)}"
end

def get(path, query)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  uri.query = URI.encode_www_form(query)
  response = Net::HTTP.get_response(uri, 'Authorization' => "Bearer #{token}")
  abort "App Store Connect answered #{response.code} for #{path}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body).fetch('data')
end

app = get('/v1/apps', 'filter[bundleId]' => bundle_id).first
abort "No App Store Connect app for #{bundle_id}" unless app

deadline = Time.now + 30 * 60
loop do
  build = get('/v1/builds', 'filter[app]' => app['id'], 'filter[version]' => build_number).first
  state = build ? build.dig('attributes', 'processingState') : 'not listed yet'
  puts "Build #{build_number}: #{state}"
  exit 0 if state == 'VALID'
  abort "Build #{build_number} was rejected by processing (#{state})" if %w[FAILED INVALID].include?(state)
  abort "Build #{build_number} was not VALID after 30 minutes (#{state})" if Time.now > deadline
  sleep 30
end

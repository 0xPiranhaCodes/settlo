#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stringio'
require 'securerandom'
require_relative '../asc-testflight-external'

def assert(value, label)
  raise "Assertion failed: #{label}" unless value
end

def expect_error(label)
  yield
  raise "Expected failure: #{label}"
rescue TestFlightExternal::Error
  # Expected; never print exception data or fixture credentials.
end

# Entirely synthetic credentials generated in memory; no production secrets are read.
key = OpenSSL::PKey::EC.generate('prime256v1')
phone = '1' + Array.new(10) { SecureRandom.random_number(10).to_s }.join
otp = Array.new(6) { SecureRandom.random_number(10).to_s }.join
settings = {
  'ASC_KEY_P8' => key.to_pem, 'ASC_KEY_ID' => 'mock-key', 'ASC_ISSUER_ID' => 'mock-issuer',
  'HOSTED_TEST_OTP' => "#{phone}=#{otp}", 'BUILD_NUMBER' => '6',
  'BETA_GROUP' => 'Family Testers', 'WHAT_TO_TEST' => 'Exercise shared expenses.', 'GITHUB_ACTIONS' => 'true'
}
resource = ->(type, id, attrs = {}) { { 'type' => type, 'id' => id, 'attributes' => attrs } }
app = resource.call('apps', 'app')
build = resource.call('builds', 'build', 'processingState' => 'VALID', 'expired' => false)
group = resource.call('betaGroups', 'group', 'name' => 'Family Testers', 'isInternalGroup' => false)
review = resource.call('betaAppReviewDetails', 'review', TestFlightExternal::Distributor::CONTACTS.keys.to_h { |k| [k, 'existing-contact'] })
app_locales, build_locales, groups, submissions, writes = [], [], [], [], []
external_state = 'READY_FOR_BETA_SUBMISSION'
group_present = true
transport = lambda do |uri, req|
  assert(req['Authorization'].start_with?('Bearer '), 'authenticated HTTP')
  data = req.body && JSON.parse(req.body).fetch('data')
  path = uri.path
  if req.method == 'GET'
    result = case path
             when '/v1/apps' then [app]
             when '/v1/builds'
               assert(URI.decode_www_form(uri.query).to_h['filter[preReleaseVersion.platform]'] == 'IOS', 'iOS filter')
               [build]
             when '/v1/apps/app/betaGroups'
               if uri.query
                 group_present ? [group] : []
               else
                 return Struct.new(:code, :body).new('200', JSON.generate(data: [], links: { next: TestFlightExternal::Client::ORIGIN + path + '?page=2' }))
               end
             when '/v1/apps/app/betaAppReviewDetail' then review
             when '/v1/apps/app/betaAppLocalizations' then app_locales
             when '/v1/builds/build/betaBuildLocalizations' then build_locales
             when '/v1/builds/build/betaGroups' then groups
             when '/v1/betaAppReviewSubmissions' then submissions
             when '/v1/builds/build/buildBetaDetail' then resource.call('buildBetaDetails', 'beta', 'externalBuildState' => external_state)
             else raise 'Unexpected mock GET'
             end
  else
    writes << [req.method, path, data]
    result = case path
             when '/v1/betaAppLocalizations'
               row = resource.call('betaAppLocalizations', 'locale', data['attributes'])
               app_locales << row
               row
             when '/v1/betaBuildLocalizations'
               row = resource.call('betaBuildLocalizations', 'build-locale', data['attributes'])
               build_locales << row
               row
             when '/v1/betaAppLocalizations/locale', '/v1/betaBuildLocalizations/build-locale', '/v1/betaAppReviewDetails/review' then data
             when '/v1/betaGroups/group/relationships/builds'
               groups << group
               return Struct.new(:code, :body).new('204', '')
             when '/v1/betaAppReviewSubmissions'
               row = resource.call('betaAppReviewSubmissions', 'submission', 'betaReviewState' => 'WAITING_FOR_REVIEW')
               submissions << row
               row
             else raise 'Unexpected mock mutation'
             end
  end
  Struct.new(:code, :body).new('200', JSON.generate(data: result))
end
client = TestFlightExternal::Client.new(env: settings, transport: transport)
output = StringIO.new
run = ->(env = settings) { TestFlightExternal::Distributor.new(client, env: env, output: output).run }
run.call
assert(writes.count { |m, _, _| m == 'POST' } == 4, 'first run creates metadata, membership and submission')
attrs = writes.find { |_, path, _| path == '/v1/betaAppReviewDetails/review' }.last.fetch('attributes')
assert(attrs['demoAccountRequired'] && attrs['demoAccountName'] == "+#{phone}" && attrs['demoAccountPassword'] == otp, 'runtime demo account')
assert(attrs['notes'].include?(otp) && attrs['notes'].include?(phone), 'runtime review notes')
assert(!attrs.key?('contactEmail'), 'existing contacts preserved')
assert(output.string.include?("::add-mask::#{phone}\n") && output.string.include?("::add-mask::#{otp}\n"), 'derived credentials masked')
visible = output.string.lines.reject { |line| line.start_with?('::add-mask::') }.join
assert(!visible.include?(phone) && !visible.include?(otp), 'no credentials in status output')
run.call
assert(writes.count { |m, _, _| m == 'POST' } == 4, 'rerun does not duplicate any resources')
%w[IN_REVIEW APPROVED].each do |state|
  submissions.first['attributes']['betaReviewState'] = state
  run.call
end
assert(writes.count { |m, _, _| m == 'POST' } == 4, 'submitted/approved build not resubmitted')
submissions.clear
external_state = 'READY_FOR_BETA_TESTING'
run.call
assert(writes.count { |m, _, _| m == 'POST' } == 4, 'approved external state without submission not resubmitted')
external_state = 'BETA_REJECTED'
run.call
assert(writes.count { |m, _, _| m == 'POST' } == 5, 'rejected build can be resubmitted')
before = writes.length
group_present = false
expect_error('missing group') { run.call }
group_present = true
group['attributes']['isInternalGroup'] = true
expect_error('internal group') { run.call }
group['attributes']['isInternalGroup'] = false
expect_error('malformed OTP') { run.call(settings.merge('HOSTED_TEST_OTP' => 'invalid')) }
review['attributes'].clear
expect_error('missing contacts') { run.call }
assert(writes.length == before, 'preflight failures do not mutate ASC')
run.call(settings.merge(TestFlightExternal::Distributor::CONTACTS.values.to_h { |k| [k, 'secret-contact'] }))
assert(writes.find_all { |_, path, _| path == '/v1/betaAppReviewDetails/review' }.last.last['attributes']['contactEmail'] == 'secret-contact', 'optional contact overrides')

bad = TestFlightExternal::Client.new(env: settings, transport: ->(*) { Struct.new(:code, :body).new('422', "echo #{phone} #{otp}") })
begin
  bad.request(:patch, '/v1/betaAppReviewDetails/review', data: {})
  raise 'Expected HTTP failure'
rescue TestFlightExternal::Error => e
  assert(e.message.include?('422') && !e.message.include?(phone) && !e.message.include?(otp), 'HTTP failure redacted')
end
expect_error('pagination origin guard') { client.list('https://example.com/v1/apps') }
# Check that the actual JWT is ES256 with a raw 64-byte signature and short lifetime.
header, claims, signature = client.token.split('.')
assert(JSON.parse(Base64.urlsafe_decode64(header))['alg'] == 'ES256', 'JWT algorithm')
payload = JSON.parse(Base64.urlsafe_decode64(claims))
assert(payload['exp'] - payload['iat'] == 600, 'JWT lifetime')
raw = Base64.urlsafe_decode64(signature)
assert(raw.bytesize == 64, 'JWT raw signature')
der = OpenSSL::ASN1::Sequence.new(raw.bytes.each_slice(32).map { |bytes| OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(bytes.pack('C*'), 2)) }).to_der
assert(key.verify(OpenSSL::Digest.new('SHA256'), der, "#{header}.#{claims}"), 'JWT signature verifies')
puts 'PASS: mocked HTTP create/rerun/review states, pagination, preflight failures, contact overrides, secret redaction and JWT verification'

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stringio'
require 'securerandom'
require_relative '../asc-testflight-external'

def assert(value, label)
  raise "Assertion failed: #{label}" unless value
end

def expect_error(label, message: nil)
  yield
  raise "Expected failure: #{label}"
rescue TestFlightExternal::Error => e
  assert(e.message.include?(message), label) if message
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
app_locales, build_locales, group_builds, submissions, writes = [], [], [], [], []
app_present = true
submission_conflict = false
external_state = 'READY_FOR_BETA_SUBMISSION'
group_present = true
transport = lambda do |uri, req|
  assert(req['Authorization'].start_with?('Bearer '), 'authenticated HTTP')
  data = req.body && JSON.parse(req.body).fetch('data')
  path = uri.path
  if req.method == 'GET'
    result = case path
             when '/v1/apps' then app_present ? [app] : []
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
             when '/v1/betaGroups/group/relationships/builds'
               if uri.query
                 group_builds
               else
                 return Struct.new(:code, :body).new('200', JSON.generate(data: [], links: { next: TestFlightExternal::Client::ORIGIN + path + '?page=2' }))
               end
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
               assert(data == [{ 'type' => 'builds', 'id' => 'build' }], 'documented membership linkage')
               group_builds << { 'type' => 'builds', 'id' => 'build' }
               return Struct.new(:code, :body).new('204', '')
             when '/v1/betaAppReviewSubmissions'
               return Struct.new(:code, :body).new('409', "echo #{phone} #{otp}") if submission_conflict
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
before = writes.length
%w[BETA_REJECTED EXPIRED PROCESSING_EXCEPTION NOT_APPLICABLE MISSING_EXPORT_COMPLIANCE IN_EXPORT_COMPLIANCE_REVIEW PROCESSING UNKNOWN].each do |state|
  external_state = state
  expect_error('blocked external state', message: state == 'BETA_REJECTED' ? 'will not resubmit' : 'current external state') { run.call }
  assert(writes.length == before, 'blocked external state cannot mutate metadata or submit')
end
external_state = 'READY_FOR_BETA_SUBMISSION'
submissions << resource.call('betaAppReviewSubmissions', 'rejected', 'betaReviewState' => 'REJECTED')
expect_error('rejected submission', message: 'will not resubmit') { run.call }
submissions.clear
assert(writes.length == before, 'rejected submission cannot mutate metadata')
app_present = false
expect_error('missing app') { run.call }
app_present = true
build['attributes']['processingState'] = 'PROCESSING'
expect_error('build not VALID') { run.call }
build['attributes']['processingState'] = 'VALID'
build['attributes']['expired'] = true
expect_error('expired build') { run.call }
build['attributes']['expired'] = false
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

# Simulate a race after successful preflight: the submission POST conflicts.
submissions.clear
submission_conflict = true
before = writes.length
expect_error('submission conflict', message: 'HTTP 409 conflict') do
  run.call(settings.merge(TestFlightExternal::Distributor::CONTACTS.values.to_h { |k| [k, 'secret-contact'] }))
end
assert(writes.drop(before).count { |_, path, _| path == '/v1/betaAppReviewSubmissions' } == 1, '409 is not blindly retried')
assert(submissions.empty?, '409 cannot report a successful submission')

bad = TestFlightExternal::Client.new(env: settings, transport: ->(*) { Struct.new(:code, :body).new('422', "echo #{phone} #{otp}") })
begin
  bad.request(:patch, '/v1/betaAppReviewDetails/review', data: {})
  raise 'Expected HTTP failure'
rescue TestFlightExternal::Error => e
  assert(e.message.include?('422') && !e.message.include?(phone) && !e.message.include?(otp), 'HTTP failure redacted')
end
conflict = TestFlightExternal::Client.new(env: settings, transport: ->(*) { Struct.new(:code, :body).new('409', "echo #{phone} #{otp}") })
begin
  conflict.request(:post, '/v1/betaAppReviewSubmissions', data: {})
  raise 'Expected conflict'
rescue TestFlightExternal::Error => e
  assert(e.message.include?('409 conflict') && !e.message.include?(phone) && !e.message.include?(otp), '409 detail is actionable and redacted')
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

# Withdrawal needs no demo account, contacts, group, or public review text.
withdraw_settings = settings.select { |k, _| k.start_with?('ASC_KEY', 'ASC_ISSUER') }.merge(
  'BUILD_NUMBER' => '7', 'TESTFLIGHT_ACTION' => 'withdraw'
)
withdraw_builds = [resource.call('builds', 'withdraw-build', 'expired' => false)]
withdraw_apps = [app]
withdraw_writes = []
withdraw_code = '200'
confirmed = true
withdraw_transport = lambda do |uri, req|
  assert(req['Authorization'].start_with?('Bearer '), 'withdrawal authenticates through Client')
  result = case [req.method, uri.path]
           when ['GET', '/v1/apps']
             assert(URI.decode_www_form(uri.query).to_h == { 'filter[bundleId]' => 'app.settlo' }, 'withdrawal app filter')
             withdraw_apps
           when ['GET', '/v1/builds']
             assert(URI.decode_www_form(uri.query).to_h == {
               'filter[app]' => 'app', 'filter[version]' => '7', 'filter[preReleaseVersion.platform]' => 'IOS'
             }, 'withdrawal app, build number and platform filters')
             withdraw_builds
           when ['PATCH', '/v1/builds/withdraw-build']
             data = JSON.parse(req.body).fetch('data')
             assert(data == { 'type' => 'builds', 'id' => 'withdraw-build', 'attributes' => { 'expired' => true } }, 'exact expiration payload')
             withdraw_writes << data
             return Struct.new(:code, :body).new(withdraw_code, "echo #{phone} #{otp}") unless withdraw_code == '200'
             resource.call('builds', 'withdraw-build', 'expired' => confirmed)
           else raise 'Unexpected withdrawal request'
           end
  Struct.new(:code, :body).new('200', JSON.generate(data: result))
end
withdraw_client = TestFlightExternal::Client.new(env: withdraw_settings, transport: withdraw_transport)
withdraw_output = StringIO.new
withdraw = lambda do |env = withdraw_settings|
  withdraw_output.truncate(0)
  withdraw_output.rewind
  TestFlightExternal::Distributor.new(withdraw_client, env: env, output: withdraw_output).run
end
withdraw.call
assert(withdraw_output.string == "Build 7: expired=false -> expired=true\n", 'only build number and prior/new expiration states logged')
assert(withdraw_writes.length == 1, 'one expiration mutation')
withdraw_builds.first['attributes']['expired'] = true
withdraw.call
assert(withdraw_output.string == "Build 7: expired=true -> expired=true\n", 'already expired build is safe to withdraw again')
before = withdraw_writes.length
saved_build = withdraw_builds.first
withdraw_builds.clear
expect_error('unknown withdrawal build', message: 'missing or ambiguous') { withdraw.call }
withdraw_builds.concat([saved_build, saved_build])
expect_error('ambiguous withdrawal build', message: 'missing or ambiguous') { withdraw.call }
withdraw_builds.replace([saved_build])
withdraw_apps.clear
expect_error('unknown withdrawal app', message: 'exactly one') { withdraw.call }
withdraw_apps.concat([app, app])
expect_error('ambiguous withdrawal app', message: 'exactly one') { withdraw.call }
withdraw_apps.replace([app])
expect_error('invalid withdrawal number', message: 'numeric') { withdraw.call(withdraw_settings.merge('BUILD_NUMBER' => '7\n')) }
expect_error('invalid action', message: 'submit or withdraw') { withdraw.call(withdraw_settings.merge('TESTFLIGHT_ACTION' => 'other')) }
saved_build['attributes']['expired'] = "echo #{phone} #{otp}"
expect_error('invalid prior expiration state', message: 'Unexpected') { withdraw.call }
assert(withdraw_writes.length == before, 'invalid withdrawal input and lookup cannot mutate ASC')
saved_build['attributes']['expired'] = false
confirmed = false
expect_error('unconfirmed expiration', message: 'not confirmed') { withdraw.call }
assert(withdraw_output.string.empty?, 'no success output for unconfirmed expiration')
%w[409 422].each do |status|
  withdraw_code = status
  expect_error('withdrawal HTTP failure redacted', message: "HTTP #{status}") { withdraw.call }
  assert(withdraw_output.string.empty?, 'no response body or false success logged')
end
puts 'PASS: mocked withdrawal filtering, exact PATCH, repeated expiry, safe preflight failures, confirmation and HTTP failures'

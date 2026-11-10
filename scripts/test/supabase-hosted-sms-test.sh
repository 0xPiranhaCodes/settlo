#!/usr/bin/env bash
# Offline checks for scripts/supabase-hosted-sms.sh: a fake curl on PATH answers the Management
# API from fixtures, so no request leaves the machine. Run: scripts/test/supabase-hosted-sms-test.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/api"

# Fixtures: $tmp/api/<METHOD>_<path with / as _>.json (body) and .status (default 200).
# Each request body is appended to $tmp/requests, one compact JSON per line; each argv to
# $tmp/argv, each --config file to $tmp/configs, and each "METHOD path" (or "deploy" from the fake
# supabase) to $tmp/calls. A successful POST /secrets or PATCH /config/auth updates the matching GET
# fixture, so a cutover reads back what it wrote.
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
out='' method=GET url='' data=false
printf '%s\n' "$*" >> "$FAKE_API/../argv"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -X) method="$2"; shift ;;
    --config) cat "$2" >> "$FAKE_API/../configs"; shift ;;
    -H|-w) shift ;;
    --data-binary) data=true; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
path="${url#https://api.supabase.com/v1/projects/ref}"
key="$method$(printf '%s' "$path" | tr / _)"
echo "$method $path" >> "$FAKE_API/../calls"
body=null
if $data; then body="$(jq -c .)"; echo "$body" >> "$FAKE_API/../requests"; fi
cp "$FAKE_API/$key.json" "$out" 2>/dev/null || echo '{}' > "$out"
status="$(cat "$FAKE_API/$key.status" 2>/dev/null || printf 200)"
if [[ "$status" == 2* && "$key" == POST_secrets ]]; then
  jq -r '.[] | [.name, .value] | @tsv' <<<"$body" | while IFS=$'\t' read -r name value; do
    jq -nc --arg n "$name" --arg d "$(printf '%s' "$value" | openssl dgst -sha256 | awk '{print $NF}')" '{name: $n, value: $d}'
  done | jq -s . > "$FAKE_API/GET_secrets.json"
elif [[ "$status" == 2* && "$key" == PATCH_config_auth ]]; then
  jq -c --argjson b "$body" '. + $b' "$FAKE_API/GET_config_auth.json" > "$FAKE_API/merged" 2>/dev/null ||
    echo "$body" > "$FAKE_API/merged"
  mv "$FAKE_API/merged" "$FAKE_API/GET_config_auth.json"
fi
printf '%s' "$status"
EOF
cat > "$tmp/bin/supabase" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "functions deploy send-sms --project-ref ref" ]] || exit 2
echo deploy >> "$FAKE_API/../calls"
exit "${FAKE_DEPLOY_STATUS:-0}"
EOF
chmod +x "$tmp/bin/curl" "$tmp/bin/supabase"

export PATH="$tmp/bin:$PATH" FAKE_API="$tmp/api" SUPABASE_ACCESS_TOKEN=token-sentinel SUPABASE_PROJECT_REF=ref
unset GITHUB_ACTIONS
fails=0

expect() { # expect pass|fail <name> <args...>
  local want="$1" name="$2" got=pass
  shift 2
  "$root/scripts/supabase-hosted-sms.sh" "$@" > "$tmp/out" 2>&1 || got=fail
  if [[ "$got" == "$want" ]]; then echo "ok   $name"; else
    echo "FAIL $name (wanted $want)"; sed 's/^/     /' "$tmp/out"; fails=$((fails + 1)); fi
}
fixture() { printf '%s' "$2" > "$tmp/api/$1.json"; printf '%s' "${3:-200}" > "$tmp/api/$1.status"; }
reset() { rm -f "$tmp/api/"* "$tmp/requests" "$tmp/argv" "$tmp/configs" "$tmp/calls"; }
sha256() { printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'; }
fn_secrets() { # fn_secrets <SEND_SMS_HOOK_SECRET digest>: all four names, as GET /secrets lists them
  fixture GET_secrets "$(jq -nc --arg d "$1" '[{name: "SEND_SMS_HOOK_SECRET", value: $d},
    {name: "MSG91_AUTH_KEY", value: "x"}, {name: "MSG91_TEMPLATE_ID", value: "x"}, {name: "MSG91_SENDER_ID", value: "x"}]')"
}

# check-test-otp
fixture GET_config_auth '{"sms_test_otp": "919000000001=123456"}'
expect fail "check-test-otp fails while a test number is set" check-test-otp
grep -q 'clear-test-otp' "$tmp/out" || { echo "FAIL check-test-otp message"; fails=$((fails + 1)); }
grep -q '919000000001' "$tmp/out" && { echo "FAIL check-test-otp printed the number"; fails=$((fails + 1)); }
fixture GET_config_auth '{"sms_test_otp": ""}'
expect pass "check-test-otp passes with an empty list" check-test-otp
fixture GET_config_auth '{"sms_test_otp": null}'
expect pass "check-test-otp passes with no list" check-test-otp
if grep -q token-sentinel "$tmp/argv"; then echo "FAIL the access token reached curl's argv"; fails=$((fails + 1)); fi
grep -qx 'header = "Authorization: Bearer token-sentinel"' "$tmp/configs" ||
  { echo "FAIL the access token did not reach curl's config"; fails=$((fails + 1)); }
if grep -v -e '--connect-timeout 10 .*--max-time 60 ' "$tmp/argv" | grep -q .; then
  echo "FAIL a curl call has no connect or overall timeout"; fails=$((fails + 1)); fi
fixture GET_config_auth '{}' 500
expect fail "check-test-otp fails when the API errors" check-test-otp

# set-secrets
reset
export MSG91_AUTH_KEY=authkey-value MSG91_TEMPLATE_ID=template-value MSG91_SENDER_ID=SENDER
fixture GET_config_auth '{"hook_send_sms_enabled": true}'
expect fail "set-secrets refuses while the hook is enabled" set-secrets
[[ ! -e "$tmp/requests" ]] || { echo "FAIL set-secrets wrote while enabled"; fails=$((fails + 1)); }
fixture GET_config_auth '{"hook_send_sms_enabled": false}'
expect pass "set-secrets sets both sides" set-secrets
if grep -qE 'authkey-value|whsec_' "$tmp/out"; then echo "FAIL set-secrets printed a secret"; fails=$((fails + 1)); fi
fn_hook="$(head -1 "$tmp/requests" | jq -r '.[] | select(.name == "SEND_SMS_HOOK_SECRET").value')"
auth="$(sed -n 2p "$tmp/requests")"
if [[ "$fn_hook" =~ ^v1,whsec_[A-Za-z0-9+/]{43}=$ ]] &&
  [[ "$(jq -r .hook_send_sms_secrets <<<"$auth")" == "$fn_hook" ]] &&
  jq -e '.hook_send_sms_enabled == false and .hook_send_sms_uri == "https://ref.supabase.co/functions/v1/send-sms"' <<<"$auth" >/dev/null &&
  [[ "$(head -1 "$tmp/requests" | jq -r '[.[].name] | sort | join(",")')" == MSG91_AUTH_KEY,MSG91_SENDER_ID,MSG91_TEMPLATE_ID,SEND_SMS_HOOK_SECRET ]]; then
  echo "ok   set-secrets sends one generated secret to the function and the hook, hook disabled"
else echo "FAIL set-secrets request bodies"; fails=$((fails + 1)); fi
# Under an inherited `bash -x` on Actions, no secret may appear outside its ::add-mask:: line.
reset
fixture GET_config_auth '{"hook_send_sms_enabled": false}'
if GITHUB_ACTIONS=true bash -x "$root/scripts/supabase-hosted-sms.sh" set-secrets > "$tmp/out" 2>&1; then
  raw="$(head -1 "$tmp/requests" | jq -r '.[] | select(.name == "SEND_SMS_HOOK_SECRET").value | ltrimstr("v1,whsec_")')"
  grep -qx "::add-mask::$raw" "$tmp/out" || { echo "FAIL xtrace: the hook secret was not masked"; fails=$((fails + 1)); }
  if grep -v '^::add-mask::' "$tmp/out" | grep -qF -e "$raw" -e token-sentinel -e authkey-value; then
    echo "FAIL xtrace: a secret was traced"; fails=$((fails + 1))
  else echo "ok   set-secrets under bash -x traces no secret"; fi
else echo "FAIL set-secrets under bash -x"; sed 's/^/     /' "$tmp/out"; fails=$((fails + 1)); fi
reset
fixture GET_config_auth '{"hook_send_sms_enabled": false}'
fixture PATCH_config_auth '{}' 500
expect fail "set-secrets fails when the hook config is not written" set-secrets
grep -q 'enable-sms-hook will refuse' "$tmp/out" || { echo "FAIL set-secrets partial-rotation message"; fails=$((fails + 1)); }
reset
unset MSG91_SENDER_ID
fixture GET_config_auth '{"hook_send_sms_enabled": false}'
expect fail "set-secrets needs every MSG91 secret" set-secrets
export MSG91_SENDER_ID=SENDER

# enable
reset
fixture GET_functions_send-sms '{}' 404
expect fail "enable refuses when send-sms is not deployed" enable
fixture GET_functions_send-sms '{"status": "ACTIVE"}'
fixture GET_secrets '[{"name": "SEND_SMS_HOOK_SECRET"}, {"name": "MSG91_AUTH_KEY"}, {"name": "MSG91_TEMPLATE_ID"}]'
expect fail "enable refuses when a function secret is missing" enable
grep -q 'MSG91_SENDER_ID' "$tmp/out" || { echo "FAIL enable names the missing secret"; fails=$((fails + 1)); }
fn_secrets "$(sha256 v1,whsec_A)"
fixture GET_config_auth '{"hook_send_sms_uri": null, "hook_send_sms_secrets": null}'
expect fail "enable refuses when the hook config is not set" enable
# A partial rotation: the function got secret B, the Auth hook kept secret A.
fixture GET_config_auth '{"hook_send_sms_uri": "https://ref.supabase.co/functions/v1/send-sms", "hook_send_sms_secrets": "v1,whsec_A"}'
fn_secrets "$(sha256 v1,whsec_B)"
expect fail "enable refuses when the function and hook secrets differ" enable
if grep -q 'whsec_' "$tmp/out"; then echo "FAIL enable printed a secret"; fails=$((fails + 1)); fi
[[ ! -e "$tmp/requests" ]] || { echo "FAIL enable wrote before its checks passed"; fails=$((fails + 1)); }
fn_secrets "$(sha256 v1,whsec_A | tr a-f A-F)"
expect pass "enable turns the hook on once everything is in place" enable
jq -e '.hook_send_sms_enabled == true' "$tmp/requests" >/dev/null || { echo "FAIL enable request body"; fails=$((fails + 1)); }

# disable
reset
expect pass "disable turns the hook off" disable
jq -e '.hook_send_sms_enabled == false' "$tmp/requests" >/dev/null || { echo "FAIL disable request body"; fails=$((fails + 1)); }

# cutover: deploy, set-secrets, enable, each only after the one before succeeded
cutover_fixtures() {
  reset
  fixture GET_functions_send-sms '{"status": "ACTIVE"}'
  fixture GET_config_auth '{"hook_send_sms_enabled": false}'
}
calls() { tr '\n' ' ' < "$tmp/calls"; }
cutover_fixtures
FAKE_DEPLOY_STATUS=1 expect fail "cutover stops when the deploy fails" cutover
[[ "$(calls)" == "deploy " ]] || { echo "FAIL cutover called the API after a failed deploy"; fails=$((fails + 1)); }
cutover_fixtures
fixture PATCH_config_auth '{}' 500
expect fail "cutover stops when set-secrets fails" cutover
if [[ "$(calls)" != "deploy GET /config/auth POST /secrets PATCH /config/auth " ]] ||
  jq -e 'select(.hook_send_sms_enabled? == true)' "$tmp/requests" >/dev/null; then
  echo "FAIL cutover went on to enable after set-secrets failed"; fails=$((fails + 1)); fi
cutover_fixtures
expect pass "cutover deploys, sets secrets, then enables" cutover
[[ "$(calls)" == "deploy GET /config/auth POST /secrets PATCH /config/auth GET /functions/send-sms GET /secrets GET /config/auth PATCH /config/auth " ]] ||
  { echo "FAIL cutover call order: $(calls)"; fails=$((fails + 1)); }
jq -e '.hook_send_sms_enabled == true' "$tmp/api/GET_config_auth.json" >/dev/null ||
  { echo "FAIL cutover left the hook disabled"; fails=$((fails + 1)); }

[[ $fails -eq 0 ]] || { echo "$fails check(s) failed"; exit 1; }
echo "All checks passed."

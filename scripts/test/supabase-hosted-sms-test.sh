#!/usr/bin/env bash
# Offline checks for scripts/supabase-hosted-sms.sh: a fake curl on PATH answers the Management
# API from fixtures, so no request leaves the machine. Run: scripts/test/supabase-hosted-sms-test.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/api"

# Fixtures: $tmp/api/<METHOD>_<path with / as _>.json (body) and .status (default 200).
# Each request body is appended to $tmp/requests, one compact JSON per line.
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
out='' method=GET url='' data=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -X) method="$2"; shift ;;
    -H|-w) shift ;;
    --data-binary) data=true; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
key="$method$(printf '%s' "${url#https://api.supabase.com/v1/projects/ref}" | tr / _)"
if $data; then jq -c . >> "$FAKE_API/../requests"; fi
cp "$FAKE_API/$key.json" "$out" 2>/dev/null || echo '{}' > "$out"
cat "$FAKE_API/$key.status" 2>/dev/null || printf 200
EOF
chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH" FAKE_API="$tmp/api" SUPABASE_ACCESS_TOKEN=token SUPABASE_PROJECT_REF=ref
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
reset() { rm -f "$tmp/api/"* "$tmp/requests"; }

# check-test-otp
fixture GET_config_auth '{"sms_test_otp": "919000000001=123456"}'
expect fail "check-test-otp fails while a test number is set" check-test-otp
grep -q 'clear-test-otp' "$tmp/out" || { echo "FAIL check-test-otp message"; fails=$((fails + 1)); }
grep -q '919000000001' "$tmp/out" && { echo "FAIL check-test-otp printed the number"; fails=$((fails + 1)); }
fixture GET_config_auth '{"sms_test_otp": ""}'
expect pass "check-test-otp passes with an empty list" check-test-otp
fixture GET_config_auth '{"sms_test_otp": null}'
expect pass "check-test-otp passes with no list" check-test-otp
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
fixture GET_secrets '[{"name": "SEND_SMS_HOOK_SECRET"}, {"name": "MSG91_AUTH_KEY"}, {"name": "MSG91_TEMPLATE_ID"}, {"name": "MSG91_SENDER_ID"}]'
fixture GET_config_auth '{"hook_send_sms_uri": null, "hook_send_sms_secrets": null}'
expect fail "enable refuses when the hook config is not set" enable
[[ ! -e "$tmp/requests" ]] || { echo "FAIL enable wrote before its checks passed"; fails=$((fails + 1)); }
fixture GET_config_auth '{"hook_send_sms_uri": "https://ref.supabase.co/functions/v1/send-sms", "hook_send_sms_secrets": "set"}'
expect pass "enable turns the hook on once everything is in place" enable
jq -e '.hook_send_sms_enabled == true' "$tmp/requests" >/dev/null || { echo "FAIL enable request body"; fails=$((fails + 1)); }

# disable
reset
expect pass "disable turns the hook off" disable
jq -e '.hook_send_sms_enabled == false' "$tmp/requests" >/dev/null || { echo "FAIL disable request body"; fails=$((fails + 1)); }

[[ $fails -eq 0 ]] || { echo "$fails check(s) failed"; exit 1; }
echo "All checks passed."

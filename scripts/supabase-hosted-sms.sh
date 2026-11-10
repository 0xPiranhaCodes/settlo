#!/usr/bin/env bash
# Hosted Send-SMS hook cutover (#119), run by the Supabase hosted and Release workflows:
#   scripts/supabase-hosted-sms.sh deploy | set-secrets | enable | cutover | disable | check-test-otp
# cutover runs deploy, set-secrets and enable in order and stops at the first failure.
# Needs SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF (set-secrets and cutover also MSG91_AUTH_KEY,
# MSG91_TEMPLATE_ID, MSG91_SENDER_ID; deploy and cutover the Supabase CLI). Management API bodies can hold the Auth config and secrets,
# so they go to a temp file that is parsed with jq and never printed.
# Off before anything expands a secret: an inherited `bash -x` would trace it ahead of ::add-mask::.
{ set +x; } 2>/dev/null
set -euo pipefail

: "${SUPABASE_ACCESS_TOKEN:?}" "${SUPABASE_PROJECT_REF:?}"
api_base="https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF"
fn_uri="https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/send-sms"
fn_secrets='["SEND_SMS_HOOK_SECRET","MSG91_AUTH_KEY","MSG91_TEMPLATE_ID","MSG91_SENDER_ID"]'
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

die() { echo "::error::$1"; exit 1; }

mask() {
  if [[ "${GITHUB_ACTIONS:-}" == true ]]; then echo "::add-mask::$1"; fi
}

token_header() { printf 'header = "Authorization: Bearer %s"\n' "$SUPABASE_ACCESS_TOKEN"; }

# Lowercase hex SHA-256 of $1, the digest GET /secrets reports instead of a secret's value.
sha256() { printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'; }

# api METHOD PATH [JSON]: prints only the status; returns 1 on a non-2xx answer.
api() {
  local status
  local args=(-sS --connect-timeout 10 --max-time 60 -o "$body_file" -w '%{http_code}' -X "$1" "$api_base$2")
  [[ $# -lt 3 ]] || args+=(-H 'Content-Type: application/json' --data-binary @-)
  # The token (as a curl config on a pipe) and the JSON (on stdin) never reach curl's argv.
  status="$(printf '%s' "${3:-}" | curl --config <(token_header) "${args[@]}")" || status=000
  echo "Management API $1 $2 answered $status"
  [[ "$status" == 2* ]]
}

# Reads verify_jwt = false from config.toml: GoTrue signs the hook call, it sends no user JWT.
deploy() {
  supabase functions deploy send-sms --project-ref "$SUPABASE_PROJECT_REF" ||
    die "send-sms was not deployed; the hook was not changed."
}

set_secrets() {
  local name
  for name in MSG91_AUTH_KEY MSG91_TEMPLATE_ID MSG91_SENDER_ID; do
    [[ -n "${!name:-}" ]] || die "Production environment secret $name is not set."
    mask "${!name}"
  done

  api GET /config/auth || die "Could not read the hosted Auth config."
  # A new secret on a live hook fails every OTP until both sides match.
  jq -e '.hook_send_sms_enabled != true' "$body_file" >/dev/null ||
    die "The Send-SMS hook is enabled. Run disable-sms-hook first, then set-sms-secrets, then enable-sms-hook."

  local raw
  raw="$(openssl rand -base64 32)"
  mask "$raw"
  export HOOK_SECRET="v1,whsec_$raw"
  mask "$HOOK_SECRET"

  api POST /secrets "$(jq -n '[
    {name: "SEND_SMS_HOOK_SECRET", value: env.HOOK_SECRET},
    {name: "MSG91_AUTH_KEY", value: env.MSG91_AUTH_KEY},
    {name: "MSG91_TEMPLATE_ID", value: env.MSG91_TEMPLATE_ID},
    {name: "MSG91_SENDER_ID", value: env.MSG91_SENDER_ID}
  ]')" || die "The function secrets were not set."

  api PATCH /config/auth "$(jq -n --arg uri "$fn_uri" '{
    hook_send_sms_enabled: false,
    hook_send_sms_uri: $uri,
    hook_send_sms_secrets: env.HOOK_SECRET
  }')" || die "The function secrets were rotated but the hook secret was not, so they differ and enable-sms-hook will refuse. The hook stays disabled; re-run set-sms-secrets."
  echo "Function secrets and the hook URI and secret are set; the hook stays disabled."
}

enable() {
  api GET /functions/send-sms || die "send-sms is not deployed. Run deploy-send-sms."
  jq -e '.status == "ACTIVE"' "$body_file" >/dev/null || die "send-sms is deployed but not ACTIVE."

  api GET /secrets || die "Could not list the function secrets."
  local missing fn_digest
  missing="$(jq -r --argjson want "$fn_secrets" '$want - [.[].name] | join(" ")' "$body_file")"
  [[ -z "$missing" ]] || die "Function secrets missing: $missing. Run set-sms-secrets."
  fn_digest="$(jq -r '.[] | select(.name == "SEND_SMS_HOOK_SECRET").value // "" | ascii_downcase' "$body_file")"

  api GET /config/auth || die "Could not read the hosted Auth config."
  jq -e --arg uri "$fn_uri" '.hook_send_sms_uri == $uri and (.hook_send_sms_secrets // "") != ""' \
    "$body_file" >/dev/null || die "The hook URI or secret is not set. Run set-sms-secrets."
  # A partial set-secrets leaves the two sides different, and every signed SMS request then fails.
  [[ "$(sha256 "$(jq -r .hook_send_sms_secrets "$body_file")")" == "$fn_digest" ]] ||
    die "The function's SEND_SMS_HOOK_SECRET differs from the Auth hook secret. Run set-sms-secrets."

  api PATCH /config/auth '{"external_phone_enabled": true, "hook_send_sms_enabled": true}' ||
    die "The hook was not enabled."
  echo "Send-SMS hook enabled: OTPs now go through MSG91."
}

disable() {
  api PATCH /config/auth '{"hook_send_sms_enabled": false}' || die "The hook was not disabled."
  echo "Send-SMS hook disabled: phone sign-in has no SMS provider until it is re-enabled."
}

check_test_otp() {
  api GET /config/auth || die "Could not read the hosted Auth config."
  jq -e '(.sms_test_otp // "") == ""' "$body_file" >/dev/null ||
    die "Test OTP numbers are still set on the hosted project while SMS_LIVE is true. Run Supabase hosted with clear-test-otp."
  echo "No test OTP numbers on the hosted project."
}

case "${1:-}" in
  deploy) deploy ;;
  set-secrets) set_secrets ;;
  enable) enable ;;
  # Each step dies on failure, so enable runs only after a successful deploy and set-secrets.
  cutover) deploy; set_secrets; enable ;;
  disable) disable ;;
  check-test-otp) check_test_otp ;;
  *) die "usage: $0 deploy|set-secrets|enable|cutover|disable|check-test-otp" ;;
esac

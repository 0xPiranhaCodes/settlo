#!/usr/bin/env bash
# Hosted Send-SMS hook cutover (#119), run by the Supabase hosted and Release workflows:
#   scripts/supabase-hosted-sms.sh set-secrets | enable | disable | check-test-otp
# Needs SUPABASE_ACCESS_TOKEN and SUPABASE_PROJECT_REF (set-secrets also MSG91_AUTH_KEY,
# MSG91_TEMPLATE_ID, MSG91_SENDER_ID). Management API bodies can hold the Auth config and secrets,
# so they go to a temp file that is parsed with jq and never printed.
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

# api METHOD PATH [JSON]: prints only the status; returns 1 on a non-2xx answer.
api() {
  local status
  local args=(-sS -o "$body_file" -w '%{http_code}' -X "$1" "$api_base$2"
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN")
  [[ $# -lt 3 ]] || args+=(-H 'Content-Type: application/json' --data-binary @-)
  # The JSON goes through stdin so secrets never reach curl's argv.
  status="$(printf '%s' "${3:-}" | curl "${args[@]}")" || status=000
  echo "Management API $1 $2 answered $status"
  [[ "$status" == 2* ]]
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
  }')" || die "The function secrets are set but the hook config is not; re-run set-sms-secrets."
  echo "Function secrets and the hook URI and secret are set; the hook stays disabled."
}

enable() {
  api GET /functions/send-sms || die "send-sms is not deployed. Run deploy-send-sms."
  jq -e '.status == "ACTIVE"' "$body_file" >/dev/null || die "send-sms is deployed but not ACTIVE."

  api GET /secrets || die "Could not list the function secrets."
  local missing
  missing="$(jq -r --argjson want "$fn_secrets" '$want - [.[].name] | join(" ")' "$body_file")"
  [[ -z "$missing" ]] || die "Function secrets missing: $missing. Run set-sms-secrets."

  api GET /config/auth || die "Could not read the hosted Auth config."
  jq -e --arg uri "$fn_uri" '.hook_send_sms_uri == $uri and (.hook_send_sms_secrets // "") != ""' \
    "$body_file" >/dev/null || die "The hook URI or secret is not set. Run set-sms-secrets."

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
  set-secrets) set_secrets ;;
  enable) enable ;;
  disable) disable ;;
  check-test-otp) check_test_otp ;;
  *) die "usage: $0 set-secrets|enable|disable|check-test-otp" ;;
esac

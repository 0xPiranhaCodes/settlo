# Supabase

## Local development

Always go through the wrapper, never the raw `supabase` CLI, for local work (agents and CI #3 included):

```sh
scripts/supabase-local.sh start
scripts/supabase-local.sh db reset
scripts/supabase-local.sh test db
scripts/supabase-local.sh stop
```

The wrapper builds `.supabase-local/` (gitignored): its `config.toml` is `config.toml` followed by
`config.local-dev.toml`, and every other entry in `supabase/` is symlinked in. It accepts local
commands only (`start`, `stop`, `status`, `test`, `db` except `push`/`pull`, `migration`, `gen`,
`seed`, `services`) and rejects anything else. Set `SUPABASE_BIN` to use a CLI that is not on `PATH`.

### One stack per worktree

Each checkout (every Orca worktree, CI included) gets its own stack, so parallel worktrees can run
`start` → `db reset` → `test db` at the same time. The wrapper hashes the repo root path (`cksum`)
and, in the generated config only, sets:

- `project_id = "settlo-<hash>"`, which names the Docker containers and volumes;
- a 10-port block at `54400 + slot*10` (`slot = hash % 500`): shadow DB `+0`, API `+1`, DB `+2`,
  Studio `+3`, Inbucket `+4`, analytics `+7`, edge inspector `+8`, pooler `+9`.

`start` prints the chosen ports, e.g.
`supabase-local: project_id settlo-d31d6c06, API port 57141, DB port 57142 (slot 274)`; `status`
shows them again. The base `config.toml` keeps `settlo` and `54321`–`54329`, which the wrapper never
uses. If two worktrees land on the same slot, set `SUPABASE_LOCAL_SLOT=<0-499>` in one of them.
`stop` stops only this worktree's stack; it keeps that stack's volumes (`stop --no-backup` drops them).

The interim `/tmp/settlo-supabase.lock` mutex is no longer needed. A stack started before this
change still runs as `settlo` on the default ports; once nobody is using it, stop it with
`scripts/supabase-local.sh stop --project-id settlo`.

`config.local-dev.toml` holds the dev-only auth values: test OTP numbers
(`+919000000001`–`3`, code `123456`) and a placeholder Twilio provider that GoTrue needs before
it enables phone login. Run the raw CLI on `config.toml` alone and phone login is off locally.

## Production config

- `config.toml` is the file `supabase config push` sends to a linked project, so it must stay
  safe to push as-is: no `[auth.sms.test_otp]`, no SMS provider block. Keep dev-only values in
  `config.local-dev.toml`.
- Production OTPs go out through the MSG91 Send-SMS auth hook (#13), not a built-in provider:
  `[auth.hook.send_sms]` in `config.toml`, disabled by default, with `env(...)` references for the
  URI and secret. See [Send-SMS hook](#send-sms-hook-msg91) below to enable it.
- To push config safely, run the **raw** CLI from the repo root (never the wrapper, which refuses):
  `supabase link --project-ref <ref>`, then `supabase config diff`, check that the diff has no
  `test_otp` or `twilio`, then `supabase config push`.

## Send-SMS hook (MSG91)

`functions/send-sms` is the Send-SMS auth hook. It verifies GoTrue's Standard Webhooks signature
(401 on mismatch or a timestamp older than 5 minutes), then sends the OTP through MSG91's flow API
(`POST https://control.msg91.com/api/v5/flow`). It makes one MSG91 call per OTP with a 4 s timeout
and no retries, and answers failures with the hook error shape
`{"error": {"http_code": 500, "message": "Failed to send SMS"}}`, which GoTrue does not retry.
Logs show only the last four digits of the phone and never the OTP.

Function secrets (Edge Function env):

| Name | Value |
| --- | --- |
| `SEND_SMS_HOOK_SECRET` | The hook secret, `v1,whsec_...`; the same value as the hook's `secrets` |
| `MSG91_AUTH_KEY` | MSG91 auth key |
| `MSG91_TEMPLATE_ID` | MSG91 flow template id, mapped to the DLT-approved template; its variable must be `##otp##` |
| `MSG91_SENDER_ID` | DLT-registered sender id (6-character header) |

Tests mock `fetch`, so they need no MSG91 account: `cd supabase/functions && deno test` (CI runs it in
the Supabase job).

Local dev never uses the hook: it stays disabled, and `config.local-dev.toml` keeps the test OTP
numbers. To try the function locally, `scripts/supabase-local.sh start` serves it at
`/functions/v1/send-sms`, but no request reaches MSG91 without the env above.

### Enabling on the hosted project

Needs the owner's MSG91 account, an approved DLT template and sender id, and the template created in
MSG91 against that DLT template id.

1. Deploy the function from the repo root with the raw CLI: `supabase link --project-ref <ref>`, then
   `supabase functions deploy send-sms` (`config.toml` already sets `verify_jwt = false` for it).
2. Dashboard → Authentication → Hooks → Send SMS → HTTPS, URI
   `https://<ref>.supabase.co/functions/v1/send-sms`; generate a secret and copy it.
3. `supabase secrets set SEND_SMS_HOOK_SECRET='v1,whsec_...' MSG91_AUTH_KEY=... MSG91_TEMPLATE_ID=... MSG91_SENDER_ID=...`
4. Send an OTP to a real number and check the function logs for `sent OTP to ********NNNN`.
5. To manage it from `config.toml` instead, set `enabled = true` under `[auth.hook.send_sms]` and
   export `SUPABASE_AUTH_HOOK_SEND_SMS_URI` and `SUPABASE_AUTH_HOOK_SEND_SMS_SECRETS` before
   `supabase config diff` / `config push` (same checks as above).

To rotate the secret, regenerate it in the dashboard and update `SEND_SMS_HOOK_SECRET` right away;
OTPs fail with 401 in between.

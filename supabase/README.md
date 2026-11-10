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
CI also sets `SUPABASE_LOCAL_PORT_BASE=30000` with slot 0 so its fixed block stays below Linux's
ephemeral port range. The default base remains 54400, so local per-worktree behaviour is unchanged.
`stop` stops only this worktree's stack; it keeps that stack's volumes (`stop --no-backup` drops them).

The interim `/tmp/settlo-supabase.lock` mutex is no longer needed. A stack started before this
change still runs as `settlo` on the default ports; once nobody is using it, stop it with
`scripts/supabase-local.sh stop --project-id settlo`.

`config.local-dev.toml` holds the dev-only auth values: test OTP numbers
(`+919000000001`–`3`, code `123456`) and a placeholder Twilio provider that GoTrue needs before
it enables phone login. It does not override the base SMS OTP expiry: `config.toml` sets the hosted
Auth expiry to 10 minutes (`600` seconds) when pushed. Run the raw CLI on `config.toml` alone and
phone login is off locally.

## Production config

- `config.toml` is the file `supabase config push` sends to a linked project, so it must stay
  safe to push as-is: no `[auth.sms.test_otp]`, no SMS provider block. Keep dev-only values in
  `config.local-dev.toml`.
- Production OTPs go out through the MSG91 Send-SMS auth hook (#13), not a built-in provider.
  The hook is configured through the **Supabase hosted** workflow only; `config.toml` must never declare
  `[auth.hook.send_sms]`. `config push` sends unresolved `env(...)` values as literals, and a
  declared `enabled = false` would turn off the hosted hook. See
  [Send-SMS hook](#send-sms-hook-msg91) below.
- Migrations reach the hosted project through the manual **Supabase hosted** workflow
  (`.github/workflows/supabase-hosted.yml`): a dry run first, then `apply`. The same workflow sets
  and clears the hosted test OTP numbers and runs the Send-SMS hook cutover; see [docs/release.md](../docs/release.md#internal-builds-testflight).
- To push config safely, run the **raw** CLI from the repo root (never the wrapper, which refuses):
  `supabase link --project-ref <ref>`, then `supabase config diff`, check that the diff has no
  `test_otp`, `twilio` or `hook`, then `supabase config push`.
- `[functions.send-sms] verify_jwt = false` is safe in `config.toml`: `config push` only updates
  api, db, auth and storage, and `functions deploy` is what reads `[functions.*]`.

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

Local dev never uses the hook: no config declares it, and `config.local-dev.toml` keeps the test
OTP numbers. To try the function locally, `scripts/supabase-local.sh start` serves it at
`/functions/v1/send-sms`, but no request reaches MSG91 without the env above.

### Enabling on the hosted project

Needs the owner's MSG91 account, an approved DLT template and sender id, and the template created in
MSG91 against that DLT template id. Everything else is the **Supabase hosted** workflow
(`.github/workflows/supabase-hosted.yml`), run from `main`; it prints no secret or API response body.
Also listed in `docs/release.md`.

1. Store the owner's values as **production** environment secrets (prompted, never on the command line):

   ```sh
   gh secret set MSG91_AUTH_KEY --env production
   gh secret set MSG91_TEMPLATE_ID --env production
   gh secret set MSG91_SENDER_ID --env production
   ```

2. `gh workflow run "Supabase hosted" -f action=deploy-send-sms` deploys the function
   (`config.toml` sets `verify_jwt = false` for it).
3. `gh workflow run "Supabase hosted" -f action=set-sms-secrets` sets the three MSG91 function
   secrets, generates a new `SEND_SMS_HOOK_SECRET` (`v1,whsec_` + 32 random bytes in base64), and
   sets it on both the function and the Auth hook along with the hook URI
   `https://<ref>.supabase.co/functions/v1/send-sms`. It refuses while the hook is enabled, and leaves
   it disabled.
4. `gh workflow run "Supabase hosted" -f action=enable-sms-hook` checks that `send-sms` is deployed
   and active, that all four function secrets exist, and that the hook URI and secret are set, then
   turns on phone sign-in and the hook.
5. Send an OTP to a real number and check the function logs for `sent OTP to ********NNNN`.
6. Clear the test numbers (`-f action=clear-test-otp`), then set the repository variable
   `gh variable set SMS_LIVE --body true`. From then on `clear-test-otp` and every **Release** run
   fail if the hosted project still has a test number.

To rotate the secret or change an MSG91 value, run `disable-sms-hook`, `set-sms-secrets`, then
`enable-sms-hook`; phone sign-in fails while the hook is off. `disable-sms-hook` alone turns the
hook off: Auth then has no SMS provider and phone sign-in fails until it is re-enabled.
`scripts/test/supabase-hosted-sms-test.sh` checks the script behind these actions offline (CI runs
it in the Supabase job).

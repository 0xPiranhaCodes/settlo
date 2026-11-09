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

`config.local-dev.toml` holds the dev-only auth values: test OTP numbers
(`+919000000001`–`3`, code `123456`) and a placeholder Twilio provider that GoTrue needs before
it enables phone login. Run the raw CLI on `config.toml` alone and phone login is off locally.

## Production config

- `config.toml` is the file `supabase config push` sends to a linked project, so it must stay
  safe to push as-is: no `[auth.sms.test_otp]`, no SMS provider block. Keep dev-only values in
  `config.local-dev.toml`.
- Production OTPs go out through the MSG91 Send-SMS auth hook (#13), not a built-in provider.
  #13 adds that hook to `config.toml`, with secrets as `env(...)` references.
- To push config safely, run the **raw** CLI from the repo root (never the wrapper, which refuses):
  `supabase link --project-ref <ref>`, then `supabase config diff`, check that the diff has no
  `test_otp` or `twilio`, then `supabase config push`.

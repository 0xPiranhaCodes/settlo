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
- Production OTPs go out through the MSG91 Send-SMS auth hook (#13), not a built-in provider.
  #13 adds that hook to `config.toml`, with secrets as `env(...)` references.
- To push config safely, run the **raw** CLI from the repo root (never the wrapper, which refuses):
  `supabase link --project-ref <ref>`, then `supabase config diff`, check that the diff has no
  `test_otp` or `twilio`, then `supabase config push`.

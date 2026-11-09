Supabase scaffold: local project, phone auth with test numbers, pgTAP harness
area:backend,type:chore,agent:claude
M0 Foundations
**Owner:** Principal Backend

## Acceptance criteria
- [ ] `supabase/` initialised; `config.toml` enables phone auth with test numbers + fixed OTP for dev
- [ ] `supabase/tests/` pgTAP harness with one smoke test
- [ ] `.env.example` lists the client keys; no secrets committed

## Test plan
`supabase db reset && supabase test db` green locally.

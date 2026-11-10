Signing, TestFlight and Play internal builds
area:infra,type:feature,agent:codex
M5 Platform surfaces and offline
**Owner:** Principal Platform · **Depends on:** Apple Developer and Play Console access, hosted Supabase, MSG91 (owner) · **Gate:** M5 → M6

## Acceptance criteria
- [ ] iOS: bundle id, signing via App Store Connect API key in CI secrets, TestFlight upload from a tagged workflow
- [ ] Android: upload keystore in CI secrets, Play internal track upload
- [ ] Release flavour points at the hosted Supabase project; migrations applied by a manual workflow; pg_cron enabled
- [ ] Phone OTP works end to end on a real device through MSG91

## Test plan
A tagged build lands in TestFlight and Play internal; a fresh install signs in with a real number; docs/release.md updated.

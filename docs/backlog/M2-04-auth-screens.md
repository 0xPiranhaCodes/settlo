Welcome, Phone and OTP screens wired to Supabase phone OTP
area:flutter,type:feature,agent:claude
M2 Design system and app shell
**Owner:** Principal Flutter · **Depends on:** M2-03 · **Canvas:** Welcome, Phone, Onboarding (notes n00–n02)

## Acceptance criteria
- [ ] Welcome with 'example' rows and one action; Phone with +91 preselected, picker reachable, 26px input, E.164 validation; OTP with six boxes, gold focus, SMS autofill (iOS one-time-code, Android SMS retriever/user consent)
- [ ] OTP screen reveals nothing about records attached to the number
- [ ] Country chip uses text "IN +91" instead of the flag emoji (decision pending owner; see docs/decisions)
- [ ] Works against local Supabase test numbers (+919000000001 → 123456)

## Test plan
Goldens at 390/360 vs artboards; integration test signs in with a test number against the local stack.

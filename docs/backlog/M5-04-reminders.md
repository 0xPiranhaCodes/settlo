Reminders and loan Remind
area:backend,type:feature,agent:claude
M5 Platform surfaces and offline
**Owner:** Principal Backend + Flutter · **Depends on:** push credentials (owner) for remote delivery

## Acceptance criteria
- [ ] Loan detail 'Remind' sends a polite nudge to the counterparty (rate-limited: one per loan per 24h), shown in their Activity
- [ ] Profile › Reminders toggle respected; due-date nudges the day after an instalment is missed
- [ ] Local notifications now; remote push wired behind a flag once APNs/FCM keys exist

## Test plan
pgTAP for rate limit and authorization; widget tests; notification scheduling tests.

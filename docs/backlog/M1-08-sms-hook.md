Send-SMS auth hook to MSG91 (production OTP)
area:backend,type:feature,agent:claude,needs-owner-decision
M1 Auth and backend core
**Owner:** Principal Backend · **Blocked on owner:** MSG91 account + DLT template

## Acceptance criteria
- [ ] Edge Function implementing Supabase Send-SMS hook, verifying the hook signature
- [ ] DLT template id and sender id from env; dev keeps test numbers

## Test plan
Function unit test with a mocked MSG91 endpoint; signature mismatch rejected.

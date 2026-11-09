Phone-to-profile linking on sign-up and pending claims
area:backend,type:feature,agent:claude
M1 Auth and backend core
**Owner:** Principal Backend · **Canvas:** HomeFound, Join · **Depends on:** M1-01, M1-02

## Acceptance criteria
- [ ] On `auth.users` insert with verified phone: create profile; backfill `user_id` on `space_members` and `loans` matching the E.164 phone
- [ ] Records created against the number surface as claims to review (HomeFound), balances blank until accepted
- [ ] "This isn't me" path removes the link and notifies the creator via activity

## Test plan
pgTAP: create space against +91…, sign up that number, member row linked; before sign-up the number's owner can read nothing.

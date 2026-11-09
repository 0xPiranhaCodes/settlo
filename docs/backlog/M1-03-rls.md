RLS for every table, keyed by phone or user id, with negative tests
area:backend,type:feature,agent:claude,gate
M1 Auth and backend core
**Owner:** Principal Backend · **Tests:** Principal QA · **Depends on:** M1-01, M1-02

## Acceptance criteria
- [ ] `is_space_member(space_id)` and `is_loan_party(loan_id)` security-definer helpers matching phone or user id
- [ ] Policies on every table; `activity` read-only to clients
- [ ] Unverified numbers see nothing; a verified number sees rows recorded against it only after verification

## Test plan (gate M1→M2)
pgTAP per policy with at least one negative case per table; `scripts/supabase-local.sh db reset && scripts/supabase-local.sh test db` green in CI.

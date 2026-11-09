Schema: profiles, spaces, members, expenses, payers, splits, recurring, activity
area:backend,type:feature,agent:claude
M1 Auth and backend core
**Owner:** Principal Backend · **Depends on:** M0-04

## Acceptance criteria
- [ ] Versioned migrations for the tables in Context pack › Backend; money columns `bigint` paise
- [ ] Deferred constraint trigger: sum(payers) = sum(splits) = amount_minor, checked at commit
- [ ] `split_type` enum equal|exact|percent|shares; soft delete via `deleted_at`
- [ ] Activity rows written only by triggers (insert/update/delete on expenses, with before/after for edits)

## Test plan
pgTAP: balanced insert commits; unbalanced insert fails at commit; edit writes before/after activity row.

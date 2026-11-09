Views: member balances, monthly fairness, monthly categories, loan summaries
area:backend,type:feature,agent:claude
M1 Auth and backend core
**Owner:** Principal Backend · **Canvas:** Space, SpacesList, Loan · **Depends on:** M1-01, M1-02

## Acceptance criteria
- [ ] `space_member_balances`, `space_monthly_fairness` (paid vs fair share), `space_monthly_categories`, `loan_summaries`
- [ ] Views run with invoker security so RLS applies

## Test plan
pgTAP fixtures with hand-computed expected values (shared with QA's money fixtures).

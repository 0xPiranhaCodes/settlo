Space: expenses and balances with fairness
area:flutter,type:feature,agent:claude
M3 Spaces end to end
**Owner:** Principal Flutter · **Depends on:** M3-02 · **Canvas:** SpaceExpenses, Space (notes n11, n12)

## Acceptance criteria
- [ ] Expenses tab: month sparkline of daily spend, grouped list, soft-deleted hidden
- [ ] Balances tab: per-member paid bar against a white fair-share tick (`space_monthly_fairness`), net balances (`space_member_balances`), category breakdown
- [ ] Edit/delete expense actions via M3-01 RPCs

## Test plan
Goldens 390/360 for both tabs; fairness widget test with fixture data; accessibility labels read paid vs fair share in rupees.

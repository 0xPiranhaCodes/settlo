Activity feed with Needs you
area:flutter,type:feature,agent:claude
M4 Loans
**Owner:** Principal Flutter · **Depends on:** M4-01, #78 · **Canvas:** Activity (note n30)

## Acceptance criteria
- [ ] Feed of activity rows across spaces and loans; edits shown with before/after values
- [ ] 'Needs you' filter and top card: pending repayment and settle-up confirmations for the current user
- [ ] Amounts in the user's favour in mint, against in coral; nothing else coloured

## Test plan
Goldens 390/360; widget tests for filter and confirm from the feed; repository tests with fixtures.

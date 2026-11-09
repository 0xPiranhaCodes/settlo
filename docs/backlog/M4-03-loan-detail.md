Loans list and loan detail with repayments
area:flutter,type:feature,agent:claude
M4 Loans
**Owner:** Principal Flutter · **Depends on:** M4-01 · **Canvas:** Loan (note n20)

## Acceptance criteria
- [ ] Loans tab list; loan detail with progress ring, three stat tiles (each instalment, next due, on track), repayment history
- [ ] Record repayment sheet (amount first); pending repayments show confirm/dispute inline for the other party only
- [ ] Ring/progress from confirmed repayments only

## Test plan
Goldens 390/360 dark and light; ring geometry tests; widget tests for record → pending → confirm.

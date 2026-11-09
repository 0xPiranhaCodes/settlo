New loan sheet
area:flutter,type:feature,agent:claude
M4 Loans
**Owner:** Principal Flutter · **Depends on:** M4-01 · **Canvas:** NewLoan (note n21)

## Acceptance criteria
- [ ] Direction first (lent/borrowed), principal in the serif with amount in Indian words underneath (₹10,00,000 → ten lakh)
- [ ] Instalment, due day, start; interest off with a visible 'later' path (disabled in v1)
- [ ] Footer states the consequence (counterparty gets a link, end month) before commit; idempotent create

## Test plan
Goldens 390/360; words-for-amount tests (lakh/crore); widget test create → appears on Home and Loans.

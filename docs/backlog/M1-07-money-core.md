core/money: paise type, INR formatting, splits, debt simplification
area:flutter,type:feature,agent:claude
M1 Auth and backend core
**Owner:** Principal Flutter · **Tests:** Principal QA (codex) · **Depends on:** M0-01

## Acceptance criteria
- [ ] Pure Dart in `packages/core/lib/money/`; `int` paise only, no `double` anywhere
- [ ] Indian grouping (₹6,74,200), amount-in-words for loans (NewLoan note)
- [ ] Splits: equal (remainder paise to payer, payer first in member order), exact, percent, shares
- [ ] Simplification: net per member, greedy largest debtor ↔ largest creditor, ≤ n−1 payments

## Test plan
Property tests: splits always sum to amount; simplified payments settle every net to 0; ≤ n−1 payments. ≥ 80% line coverage.

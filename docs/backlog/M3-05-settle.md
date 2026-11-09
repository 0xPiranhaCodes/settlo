Settle up: simplified payments, request and pay with UPI
area:flutter,type:feature,agent:claude
M3 Spaces end to end
**Owner:** Principal Flutter (+ Principal Mobile Platform for url_launcher/ADR) · **Depends on:** M3-03, M3-06 · **Canvas:** Settle, SettlePay (notes n22, n44)

## Acceptance criteria
- [ ] Simplified payments (≤ n−1) from packages/core greedy simplification
- [ ] Request side framed as a request (n22); pay side in coral with `upi://pay` prefilled payee VPA, name, amount and note, opened through the OS app chooser (url_launcher, ADR)
- [ ] After returning, the user confirms and a settlement is recorded (`add_expense` with `is_settlement`); Settlo never moves money
- [ ] Missing payee UPI ID handled with a plain message

## Test plan
Goldens 390/360 for both sides; unit test for the UPI URI (encoding, amount in rupees with 2 decimals); widget test settle → balances zero.

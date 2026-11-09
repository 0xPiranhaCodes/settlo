Add expense sheet with split types
area:flutter,type:feature,agent:claude
M3 Spaces end to end
**Owner:** Principal Flutter · **Depends on:** M3-02 · **Canvas:** AddExpense (note n13)

## Acceptance criteria
- [ ] Sheet over the space; amount first in the serif; payer(s); split equal / exact / percent / shares using packages/core money functions
- [ ] Live validation that splits sum to the amount; remainder paise to the payer (equal)
- [ ] Calls `add_expense` with a device-generated idempotency key; retry after timeout is safe

## Test plan
Goldens 390/360; widget tests per split type including rounding; repository test that a retry reuses the key.

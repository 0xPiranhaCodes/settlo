Home, Home · empty and Home · ledger found
area:flutter,type:feature,agent:claude
M2 Design system and app shell
**Owner:** Principal Flutter · **Depends on:** M2-04, #9 · **Canvas:** Main, HomeEmpty, HomeFound, HomeLight (notes n03, n40, n41, n33)

## Acceptance criteria
- [ ] Hero net position card, owed/owe/month spend stats, two actions, spaces and loans cards — data from `space_member_balances` and `loan_summaries`
- [ ] Empty state with two job tiles and ₹0 hero in muted type (layout doesn't jump when data arrives)
- [ ] Ledger found: claims recorded against the newly verified number listed for review, balances blank until accepted
- [ ] Light theme matches HomeLight

## Test plan
Goldens for the three states in dark plus Home in light, 390/360; provider tests with fixture data.

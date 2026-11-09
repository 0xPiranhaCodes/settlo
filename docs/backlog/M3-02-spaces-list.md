Spaces list, Space · empty and create space
area:flutter,type:feature,agent:claude
M3 Spaces end to end
**Owner:** Principal Flutter · **Depends on:** #30 · **Canvas:** SpacesList, SpaceEmpty (notes n10, n42) · **Decision:** docs/decisions/2026-11-09-interim-online-repositories.md

## Acceptance criteria
- [ ] Spaces list: each card a mini balance sheet with the stacked paid bar (n10)
- [ ] Create space sheet: name, kind, members by phone (E.164) via `create_space` with an idempotency key
- [ ] Space · empty for a one-member space (n42)
- [ ] Data through a repository interface; no Supabase calls outside it

## Test plan
Goldens 390/360 dark (+ list in light), repository tests with fixtures, widget test create space → appears in list.

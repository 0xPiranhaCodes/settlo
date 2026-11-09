Live Activity and Android ongoing notification
area:platform,type:feature,agent:claude
M5 Platform surfaces and offline
**Owner:** Principal Platform · **Canvas:** LiveActivity (note n32)

## Acceptance criteria
- [ ] iOS Live Activity / Dynamic Island for the two states only: a pending settle-up awaiting you, and a trip in progress; Confirm in the expanded island opens the confirm flow
- [ ] Android: identical state as an ongoing notification with a Confirm action
- [ ] Started/updated/ended from app state (no push in v1); ends when the item resolves
- [ ] Glass tab bar falls back to a flat 92% surface on mid-range Android (n32 review note)

## Test plan
Unit tests for the state mapping; platform channel tests; simulator/emulator recordings for both states.

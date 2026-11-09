Components: card, buttons, chips, segmented control, sheet, glass tab bar
area:flutter,type:feature,agent:claude
M2 Design system and app shell
**Owner:** Principal Flutter · **Depends on:** M2-01 · **Canvas:** Main, AddExpense, Activity, LiveActivity note n32

## Acceptance criteria
- [ ] `SCard` (radius 24–28, hairline border, 1px top specular), primary (gold) and secondary buttons (radius 16, 44pt min), pill chips, segmented control, avatar
- [ ] Amount-entry bottom sheet scaffold (drag handle, close, amount first in serif)
- [ ] Floating glass tab bar (68px pill, blur 28, 62% surface, specular border); flat 92% surface fallback on Android when a `lowEndBlur` flag is set
- [ ] Gold appears only on tappable primary actions (lint-style widget test that no non-button uses the accent)

## Test plan
Golden per component, dark and light, 390 and 360 widths.

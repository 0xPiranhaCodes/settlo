Design system: tokens, themes, typography, money text
area:flutter,type:feature,agent:claude
M2 Design system and app shell
**Owner:** Principal Flutter · **Canvas:** all artboards; notes ov2, ov3, n33 (HomeLight)

## Acceptance criteria
- [ ] `packages/core/lib/theme/`: colour, spacing (8pt), radius, elevation tokens for dark and light exactly as the Context pack › Brand and design
- [ ] `ThemeData` for dark (default) and light; gold primary in dark, ink in light; mint/coral only via a `MoneyTone` API
- [ ] Typography: Figtree (400/500) for text, IBM Plex Serif 500 for amounts ≥ 20px, tabular figures everywhere, via google_fonts with bundled font files for tests
- [ ] `MoneyText` widget: takes `Paise` + tone + size; ₹ in Figtree at 56% aligned to cap height; Indian grouping from core/money
- [ ] Contrast check: every text/background token pair ≥ 4.5:1 (unit test)

## Test plan
Golden tests of a token sheet and `MoneyText` at 13/17/46/52px in both themes; contrast unit test.

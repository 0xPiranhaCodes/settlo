# Issue #278 — Phase 1 sheet chrome

The measured rules in [#278](https://github.com/0xPiranhaCodes/settlo/issues/278)
are authoritative. The owner-provided Figma exports are in [figma/](figma/);
they are half-scale references. Their old dividers/back controls and visible
tab bars are superseded by the issue's final sheet rules.

`before/` contains the committed 390×844 space captures from main
`6a928eb1b177598c1cf1cecd4ebfae40cfa2e324`. `after/` contains real Flutter
Linux golden captures of Expenses and Balances at 390×844, SE 375×667, and
SE at 200% text, in both themes. The data is the repository's deterministic
Flat 402 fixture, so member amounts and expense descriptions differ from Figma.
No generated app imagery is used.

The new header has a 28pt avatar, a 20pt semibold title, and a 44pt Close action
16pt from the right edge. At rest it is flat; scroll tests check that its
80% background and sigma-30 blur activate only while content passes underneath.
The title area preserves access to Members. Expenses and Balances share one
root-navigator sheet identity, and opening Add expense or Settle up preserves
that sheet underneath. Space Activity retains its existing content and route.

Widget tests exercise the iOS 26 `xmark`/`Close` channel payload, neutral tint,
44pt native host size, callback, root presentation on both platforms, in-place
segment replacement, close/drag dismissal, scrolling, row layout and text growth.
The UIKit bridge test uses a fake native host; it is not a physical-device capture.

## Validation

All 1,739 tests passed across the Linux workspace suites and the two
requested native exceptions. Total coverage: 6043/6142 = 98.39% (main baseline 98.11%); money coverage is 100%.
Analysis is clean, and host `flutter pub get` was restored after Docker.
The [validation record](validation.txt) contains commands, package counts,
coverage details, and the corrected compatibility regressions.

## Captures

| Screen | Before | After |
|---|---|---|
| Expenses, light | [390×844](before/spaces_expenses_390x844_light.png) | [390×844](after/sheet_space_expenses_390x844_light.png) |
| Expenses, dark | [390×844](before/spaces_expenses_390x844_dark.png) | [390×844](after/sheet_space_expenses_390x844_dark.png) |
| Balances, light | [390×844](before/spaces_balances_390x844_light.png) | [390×844](after/sheet_space_balances_390x844_light.png) |
| Balances, dark | [390×844](before/spaces_balances_390x844_dark.png) | [390×844](after/sheet_space_balances_390x844_dark.png) |

[Contact sheet of all 12 after captures](after/contact-sheet.png), including SE
and 200% text. All captures were visually inspected; lower content is reachable
by scrolling.

# Issue #202 — Settle Check palette

The owner’s exact light/dark roles and derived surfaces are documented in
[the palette specification](../../design/palette.md). [The literal-colour
audit](color-audit.txt) covers Flutter production sources and native colours.
The app name, launcher icon, supplied in-app S artwork, and website are unchanged.

## iOS 26.1 evidence

The original captures used one disposable iPhone 17 Pro simulator and the real app router
with the repository’s offline fixture repositories. The entry point is
[`palette_app.dart`](../../../app/integration_test/palette_app.dart); no backend,
SMS, or live account was used. XCUITest sends coordinate-based HID taps to the
native tab bar, glass buttons, space tabs, and sheets. Screenshots include native
UIKit views and the system keyboard, not widget-test renders.

Before source: [before-sha.txt](before-sha.txt). Both revisions use the same fixture
entry point; auth starts signed out with `--dart-define=PALETTE_AUTH=true`.
System appearance controls light/dark. The status bar is fixed at 9:41.

| Screen | Before light | After light | Before dark | After dark |
| --- | --- | --- | --- | --- |
| Home | [before light](before/light/home.png) | [after light](after/light/home.png) | [before dark](before/dark/home.png) | [after dark](after/dark/home.png) |
| Spaces | [before light](before/light/spaces.png) | [after light](after/light/spaces.png) | [before dark](before/dark/spaces.png) | [after dark](after/dark/spaces.png) |
| Balances | [before light](before/light/balances.png) | [after light](after/light/balances.png) | [before dark](before/dark/balances.png) | [after dark](after/dark/balances.png) |
| Loans | [before light](before/light/loans.png) | [after light](after/light/loans.png) | [before dark](before/dark/loans.png) | [after dark](after/dark/loans.png) |
| Activity | [before light](before/light/activity.png) | [after light](after/light/activity.png) | [before dark](before/dark/activity.png) | [after dark](after/dark/activity.png) |
| Profile | [before light](before/light/profile.png) | [after light](after/light/profile.png) | [before dark](before/dark/profile.png) | [after dark](after/dark/profile.png) |
| Add Expense | [before light](before/light/add-expense.png) | [after light](after/light/add-expense.png) | [before dark](before/dark/add-expense.png) | [after dark](after/dark/add-expense.png) |
| Welcome | [before light](before/light/welcome.png) | [after light](after/light/welcome.png) | [before dark](before/dark/welcome.png) | [after dark](after/dark/welcome.png) |
| Auth | [before light](before/light/auth.png) | [after light](after/light/auth.png) | [before dark](before/dark/auth.png) | [after dark](after/dark/auth.png) |

Reproduce with an iOS 26.1 simulator, built from `app/`:

```sh
flutter build ios --simulator --debug -t integration_test/palette_app.dart
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,id=<your disposable simulator>' \
  -parallel-testing-enabled NO \
  -only-testing:RunnerUITests/RunnerUITests/testPaletteEvidence
```

Use `simctl ui <id> appearance light` / `dark` for the two appearances.
For Welcome and phone entry, rebuild with `--dart-define=PALETTE_AUTH=true` and
run `testPaletteAuthEvidence`. Export screenshot attachments with
`xcrun xcresulttool export attachments`. Delete the disposable simulator after
verification. The dedicated `Settlo Palette 202` simulator was shut down and
deleted after this run (UUID `7CB778C5-7679-4C9A-A596-57DEF56A877E`).

## PR #206 colour-only correction

The correction after `6efaa2c` removes the per-card **Add expense** button,
its navigation action, and the new settlement-count line. `_SpaceCard` and
`spaces_test.dart` now match main byte for byte. Existing pending lines retain
the approved clock icons. A full production-diff audit also found and reverted
the new primary-button pill shape: the original radius-16 shape is restored.

All 174 affected PNGs were regenerated in the pinned Linux `ci-local` image and
visually inspected, retaining their original dimensions. All 12 Spaces-list
variants now use main's card layout, including both widths and 200% text.

Final validation:

- `flutter analyze`: no issues.
- Full workspace tests with `--coverage --concurrency=2`: **1,516 passed**
  (app 795, core 471, local 73, platform 76, auth 59, profile 42).
- CI LCOV merge and gates: **98.52% (5709/5795)** against **98.11%**;
  money **100% (110/110)**. No #194 exclusion was needed.
- iOS 26.1: all 24 Swift tests and `testPaletteEvidence` passed in each
  appearance. The two **Spaces after** images above were replaced with these
  inspected captures; the other native images remain historical `6efaa2c`
  evidence, including its former button shape. Current button shapes are
  covered by the regenerated Linux goldens.
- Only one simulator was booted for this correction, iPhone 17 Pro
  `45C79D4F-1533-48D2-B4B6-EE35D1FC78FC`; it was shut down, deleted and
  verified absent afterward. No `.github` files changed.

The capture uses the reproduction command above with `-only-testing:RunnerTests`
added. Detailed commands and the initial sheet-golden rerun are recorded in
[validation.txt](validation.txt). Hosted CI remains the merge gate.

## Original validation at `6efaa2c`

The key-pair tests enforce 4.5:1 for normal text, button labels, money amounts,
pending and errors on content surfaces, and 3:1 for control outlines. The exact
12-role table is independently asserted in both appearances. Rendered-pixel
probes cover selected controls and enabled/disabled primary actions; the native
bridge and Swift tests verify tint propagation without recolouring artwork.

Linux goldens and the full coverage run use
`settlo/flutter-goldens:3.47.9-amd64` (the `ci-local` image). The coverage merge
and baseline calculation use the `linux_tests` step extracted from
`scripts/ci-local.sh`; the main baseline is 98.11% at
`7b8539d9440c13aaa05748ebdd8b9c7723b50b86`. Tests were resumed per package
and run serially after the initial parallel run; the LCOV merge and gates are
unchanged. No `.github` files changed.


Results (details and exact commands in [validation.txt](validation.txt)):

- `flutter analyze`: no issues.
- Linux workspace tests: app 797, core 471, local 73, auth 59, Profile 42 passed; platform 75 passed with the known `share_files_test` failure excluded per #194.
- Final Space behavior/golden comparison: 108 passed after the last directional-amount correction. All 388 changed goldens were generated in the pinned Linux image.
- Coverage: **98.52% (5709/5795)** versus **98.11%** on main; money **100% (110/110)**.
- iOS 26.1: 24 Swift tests passed; native header buttons, asserted-tab capture flows and signed-out auth captures passed in both appearances. All 36 before/after PNGs were visually inspected.

Run caveats: the export responsiveness test exceeded its unchanged 250 ms limit
while the simulator was consuming CPU (728 ms parallel, 473 ms serial). After
simulator shutdown, the isolated test passed, including its file-content checks;
its LCOV was merged with the full core run. Initial native capture/header
attempts intermittently missed a tap. The capture test now asserts selected tabs
and waits for sheet dismissal; the final light/dark flows passed, and the original
app's isolated Loans tap also passed in both appearances. These are simulator
results, not physical-device gesture certification.

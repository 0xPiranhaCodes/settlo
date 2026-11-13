# Issue #248 — neutral dark palette

Includes the owner's follow-up: green accents and owed-to-you amounts become
marigold, pending becomes neutral grey with its clock cue, and light mode stays
unchanged. Supplied check/logo artwork remains unchanged as an explicit brand
exception. All dark theme tokens, including action/nav foregrounds, are green-free.

## Native screenshots

Refreshed after screenshots captured on a task-owned iPhone 17 Pro / iOS 26.1 simulator,
`526C032B-5868-4A08-929E-F1A56BB9C22C`, with dark system appearance and a fixed
9:41 status bar. The screenshots include native UIKit glass and use offline
fixtures, not a live account. Before source: [before-sha.txt](before-sha.txt),
with only the capture test added. After source is this PR's palette.

| Screen | Before | After |
| --- | --- | --- |
| Home | [Before](before/home.png) | [After](after/home.png) |
| Spaces | [Before](before/spaces.png) | [After](after/spaces.png) |
| Space detail | [Before](before/space-detail.png) | [After](after/space-detail.png) |
| Loans | [Before](before/loans.png) | [After](after/loans.png) |
| Activity | [Before](before/activity.png) | [After](after/activity.png) |
| Add expense | [Before](before/add-expense.png) | [After](after/add-expense.png) |
| Settle up | [Before](before/settle-up.png) | [After](after/settle-up.png) |

Reproduce from `app/` with your own disposable simulator:

```sh
flutter build ios --simulator --debug -t integration_test/palette_app.dart
xcrun simctl ui "$SIMULATOR_UDID" appearance dark
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:RunnerUITests/RunnerUITests/testNeutralDarkEvidence \
  -resultBundlePath /tmp/dark248.xcresult
xcrun xcresulttool export attachments --path /tmp/dark248.xcresult \
  --output-path /tmp/dark248-attachments
```

If inherited Orca Git overlays have missing keys, prefix Flutter/Xcode/Git
commands with `env -u GIT_CONFIG_COUNT`.

## Palette checks

- Surface steps: black → `#1C1C1E` → `#2C2C2E` → `#3A3A3C`.
- Adjacent surface contrast: 1.234:1, 1.221:1, 1.228:1.
- Secondary/muted/pending `#B8B8B8` on highest surface: 5.72:1.
- Marigold on highest surface: 6.76:1.
- Control outline `#858585` on raised surface: 3.78:1.
- Existing ContrastPair tests retain AA checks for every permitted pair.
- Added tests reject green-dominant dark tokens, preserve glass alphas, check
  surface separation, neutral labels and marigold contrast on all four surfaces.
- Owed/pending/you-owe are three distinct roles: marigold/grey/salmon. Signs,
  explanatory labels and pending clocks continue to convey meaning without hue.
- The original palette failed the new hue and neutral-label regression tests.

See [audit.md](audit.md) for the Dart and native fill audit.

## Linux goldens

Used the Docker image and Linux/amd64 invocation from `scripts/ci-local.sh`,
built with `scripts/Dockerfile.flutter-goldens` and pinned Flutter 3.47.9.
Unlike `ci-local --update-goldens`, both app and core were explicitly updated:

```sh
flutter pub get
(cd packages/core && flutter test --update-goldens --concurrency=2 --reporter expanded)
(cd app && flutter test --update-goldens --concurrency=2 --reporter expanded)
```

The commands above ran inside the container. Host `flutter pub get` must run
after Docker tests to restore `.dart_tool` host paths. Local Linux checks are
preflight evidence; hosted CI remains the merge gate.

Eight `glass_scrolled_*_light_*` PNGs also change: `glass_golden_test.dart`
deliberately paints dark and light cards side by side beneath each appearance
of the tab bar. Their dark fixture content changes. The light token block remains byte-identical.
The review correction also changes Home/Loans light goldens because the
direction words are retained in scheduled subtitles in both appearances;
light colours remain unchanged.

The fairness pixel guard scans the whole card for you-owe salmon and the
rendered delta amounts for owed marigold. Marigold paid bars are intentional;
salmon is forbidden everywhere in the card. Both scans retain ±4/channel
tolerance and expect zero matching pixels.
Disabled primary-button custom glyphs have a separate pixel regression test.

## Initial-head validation (77fd94a; superseded below)

- Root `flutter analyze`: no issues.
- Canonical Docker comparison (no updates): app **795 passed**, core **476 passed**.
- All 204 changed goldens were visually reviewed; hashes and dimensions are
  recorded in [golden-review.json](golden-review.json).
- Final Linux validation used an isolated source copy to avoid overwriting the
  host `.dart_tool` during the native build. All 276 tracked Dart, Swift, YAML
  and lock files matched the working tree byte-for-byte.
- Native Swift unit tests: **24 passed**. Final seven-screen capture test: **1 passed**
  in 69.7 seconds; all seven final images were visually reviewed, including the
  neutral disabled Save expense glyph.
- Final capture needed a clean reset after XCTest idle/app-launch stalls. Only
  the dedicated simulator was reset, then shut down and deleted; its UDID was
  verified absent from the device inventory.
- A first concurrent run exceeded an existing export responsiveness threshold
  under Xcode compilation load. The final single-worker core suite passed with
  the unchanged threshold; no test limit was relaxed.

## Review correction validation

The action/nav ink is now `#111111` in Dart and the Live Activity Swift palette;
no dark token is exempt from the green-hue test. The logo is the sole exception.
See [audit.md](audit.md) and [check-tritanopia.py](check-tritanopia.py) for the
colour-vision check and the direction-cue inventory.

- Focused Home, Loans and Spaces run: **155 passed**, including four new
  scheduled-loan direction tests (lent/borrowed on both screens).
- Fairness negative controls: a salmon paid-bar mutation failed with **2,360**
  forbidden pixels; an owed-marigold delta mutation failed with **98**.
  Both mutations were reverted before regeneration and final comparison.

- Canonical Linux/amd64 regeneration: core **476 passed**, app **799 passed**.
- Separate comparison with updates disabled: core **476 passed**, app **799 passed**.
  Both suites ran single-worker with unchanged test thresholds.
- All **131 PNGs changed by this correction** were visually inspected in
  contact sheets. Updated hashes/dimensions are in `golden-review.json`.
  Scheduled rows retain their direction at normal and 200% text sizes.

- Host `flutter pub get` restored host paths after Docker; root analysis is clean.
  Removed a redundant default month in a new test fixture after analysis; both
  affected scheduled-loan tests passed again on the host.
- Native simulator build succeeded. Swift unit tests: **24 passed**; seven-screen
  capture: **1 passed** in **62.936 seconds**. All seven refreshed after images
  were visually inspected, including action labels and the scheduled-loan cue.
- The dedicated capture simulator was shut down and deleted after review.

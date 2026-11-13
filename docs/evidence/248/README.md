# Issue #248 — neutral dark palette

Includes the owner's follow-up: green accents and owed-to-you amounts become
marigold, pending becomes neutral grey with its clock cue, and light mode stays
unchanged. Supplied check/logo artwork remains unchanged as an explicit brand
exception. Forest foreground labels on marigold retain the existing exception.

## Native screenshots

Captured on a task-owned iPhone 17 Pro / iOS 26.1 simulator,
`334DB8CA-57C5-4913-BFF8-B8C5FAFFAF88`, with dark system appearance and a fixed
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
of the tab bar. Their dark fixture content changes; light-only screen goldens
and the light token block remain byte-identical.

The fairness pixel guard now examines the rendered delta amounts rather than
the whole chart: marigold paid bars and marigold owed amounts intentionally
share a colour. A negative control changed the deltas to owed marigold and was rejected with
98 semantic-colour pixels; the mutation was restored before final tests.
Disabled primary-button custom glyphs have a separate pixel regression test.

## Final validation

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

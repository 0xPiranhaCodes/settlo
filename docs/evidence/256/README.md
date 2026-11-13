# Space Activity segment evidence

Recorded on a dedicated iPhone 17 Pro simulator running iOS 26.1,
UDID `2ECF29C7-D94B-476D-A538-7F85C334AD27`, created for this revision and
deleted after capture. Touches use Simulator's HID path via
`docs/evidence/188/simtouch.m`, without XCUITest or an accessibility client.

The fixture is `docs/evidence/191/glass_capture_app.dart.txt`, copied temporarily
to `app/integration_test/capture_256.dart`. It uses the repository's fake session
and data. `Documents/capture.txt` contains `THEME=light`, `ROUTE=/spaces/s1`,
and `UNREAD=3`.

- `before.mp4`: built from `a662180` (`origin/main~2`, before PR #250 and this
  fix). Tapping Activity in Flat 402 leaves the space and opens the global
  Activity tab with All selected and entries from other spaces and loans.
- `after.mp4`: built from this revision rebased onto `5612e87`. Switching
  Expenses → Activity → Balances → Activity retains the space navigation,
  including the S/R/P avatars, and the space-only feed. Back returns to Spaces.

The videos retain the actual capture timing. They are inspected at the start,
after the segment taps, and at the end to ensure the demonstrated transition is
present in the committed files.

Capture checks: before is 19.53 seconds / 41 frames; after is 75.73 seconds /
103 frames. These are the original H.264 simulator recordings, without retiming.

Validation on the rebased revision: Docker image
`settlo/flutter-goldens:3.47.9-amd64` ran `flutter analyze` (no issues),
`cd app && flutter test` (855 passed, including goldens), and
`cd packages/core && flutter test test/router/routes_test.dart` (passed).
Host `flutter pub get` restored host package paths afterward; final host
`flutter analyze` also found no issues.

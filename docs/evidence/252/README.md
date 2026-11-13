# Liquid-glass back control — #252

The existing `GlassAction` now supports a back capsule. The shared
`SettloScrollScaffold` pushed iOS header and auth `StepHeader` use it; no new
platform view or per-detail-screen implementation was added. Auth uses the
same fallback on Android. Existing icon-only Android detail headers are
unchanged; country/create-space modal Cancel controls remain modal actions.

Native iOS 26 uses the existing `GlassButton` bridge, with a chevron and
optional title in one 44 pt capsule. Older platforms use `glassFallback`.
Long destination names truncate; at accessibility sizes the visible name
can disappear while the full “Back to …” accessibility label stays. The
route's previous title is used when no explicit destination is supplied.

## Simulator evidence

Owned iPhone 17, iOS 26.1, UDID
`636A93B4-6BA1-4F5F-A263-6D1933B0A770`. Screens use real feature widgets and
repository test fixtures, pushed on `CupertinoPageRoute`; the capture
launcher is not production UI. `capture.dart.txt` is the reproducible target.

| Screen | Before | After |
|---|---|---|
| Expenses, light | [before](before-expenses-light.png) | [after](after-expenses-light.png) |
| Expenses, dark | [before](before-expenses-dark.png) | [after](after-expenses-dark.png) |
| Balances, light | [before](before-balances-light.png) | [after](after-balances-light.png) |
| Balances, dark | [before](before-balances-dark.png) | [after](after-balances-dark.png) |
| Empty space, light | [before](before-empty-light.png) | [after](after-empty-light.png) |
| Empty space, dark | [before](before-empty-dark.png) | [after](after-empty-dark.png) |
| Loan, light | [before](before-loan-light.png) | [after](after-loan-light.png) |
| Loan, dark | [before](before-loan-dark.png) | [after](after-loan-dark.png) |

Reviewed all before/after images: dark glass stays neutral, labels are
legible, trailing actions remain visible, and content layout is unchanged.
Real Simulator HID edge swipes returned to the launcher in all eight cases.
A bottom-of-target tap (103 pt from the screen top, within the 44 pt back
control) also returned to the launcher in [light](tap-bottom-light.png) and
[dark](tap-bottom-dark.png). These are touch tests, not accessibility-driven
activation. VoiceOver wording is checked at the platform-channel boundary;
spoken VoiceOver on a physical device was not tested.

## Checks

- Pinned Docker image `settlo/flutter-goldens:3.47.9-amd64`:
  - 42 shared header / liquid glass / scroll chrome widget tests passed.
  - 32 auth screen tests passed.
  - 85 app golden tests regenerated and then passed without `--update-goldens`.
- Visually inspected all 16 updated auth images and eight new shared-header
  images, at 390×844 and 360×800, both themes, normal and 200% text. The
  shared iOS header retains Cupertino's text-scaling clamp; standalone auth
  controls hide their visible destination at 200%, retaining semantics.
- Host `flutter pub get` completed after Docker to restore host package paths.
- The owned simulator was shut down and deleted after capture; confirmed
  absent from `simctl list devices`.

Docker commands (from the checkout root):

```sh
docker run --rm --platform linux/amd64 --env CI=true \
  --volume "$PWD:/workspace" --workdir /workspace \
  settlo/flutter-goldens:3.47.9-amd64 bash -lc '
    set -e
    flutter pub get
    cd packages/core
    flutter test test/widgets/glass_back_test.dart test/widgets/liquid_glass_test.dart test/widgets/scroll_chrome_test.dart
    cd ../features/auth
    flutter test test/screens_test.dart
    cd ../../../app
    flutter test test/auth_golden_test.dart test/glass_back_golden_test.dart test/liquid_glass_golden_test.dart test/spaces_golden_test.dart
  '
flutter pub get
```

To reproduce native captures, copy `capture.dart.txt` to
`app/test/capture252.dart`, create your own simulator, record its UDID in
`build/issue252/udid`, and compile `docs/evidence/188/simtouch.m` to
`build/issue252/simtouch`. Build the capture target, install and launch
`app.settlo`, then run `capture.py before` or `capture.py after` from the
checkout root. Delete only that owned simulator when finished. Capture
scripts and all scratch remain within the worktree.

Final host validation: `flutter analyze` reported no issues, and
`flutter build ios --simulator --debug -t test/capture252.dart` succeeded.
The temporary runnable capture file and the 681 MB native build directory
were removed after verification; the reproducible source is retained here.

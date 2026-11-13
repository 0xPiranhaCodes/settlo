# Native tab bar on home-button iPhones (#258)

Baseline: `cecd375ed08f3ba390ae4b0a0fb4be6e757b3d0a` (`origin/main`).
The screenshots use the signed-in, offline `integration_test/native_tab_bar_app.dart`
fixture, with the same Home data before and after. No production account is used.

## Cause

`UITabBar` supplies its own fitted height. Its flexible-height autoresizing mask
also applied the Flutter host's resize delta, so the actual bar frame could be
larger than the height reported to Flutter. The zero-bottom-inset SE exposed the
labels below the screen; a home-indicator inset hid the error on the iPhone 14.
The fix assigns the bar the host bounds during layout instead of letting the
flexible-height mask accumulate a second adjustment. UIKit still supplies the
height, including its floating margin; Flutter still reserves that reported height.

The original native probe reported an 83-point host but a 166-point bar after
resizing from the 49-point initial host. All eight rendered labels failed the
containment assertion (their bottom was 134 points). The app baseline screenshots
independently reproduce the SE clipping.

## Appearance

The host's app-theme override already resolves correctly; no fixed background,
forced blur, or new tint is needed. The matching-theme baseline reproduced clipping
but did not independently reproduce the reported dark material in light mode.
After captures deliberately keep the system dark and select Light/Dark/Light in
app Settings, checking the real glass rendering as well as inherited UIKit traits.
The status-bar colour in the mismatched-theme light capture is the separate audit
finding #259, outside this tab-bar fix.

## Reproduction

- iOS 26.1, iPhone SE (3rd generation), 375×667: `11E36FE9-E9F3-478D-AE8B-5834FFDCFD4F`.
- iOS 26.1, iPhone 14, 390×844: `C1DB1BC4-7AAD-4DC2-8FC9-9960E4B76B12`.
- Devices were created specifically for this task and run sequentially.
- `flutter build ios --simulator --debug -t integration_test/native_tab_bar_app.dart`
  from `app/`; install and launch by UDID with `xcrun simctl`.
- Switch system appearance with `xcrun simctl ui <UDID> appearance light|dark`.
- Swift tests: `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner
  -destination 'id=<UDID>' -only-testing:RunnerTests
  -only-testing:RunnerUITests/RunnerUITests/testTabBarAppearanceAndLabelTouches
  -parallel-testing-enabled NO` from `app/`.
- App tests: `flutter pub get && cd app && flutter test --concurrency=2` in
  `settlo/flutter-goldens:3.47.9-amd64`, Linux/amd64 Docker, on an isolated source copy.

## Validation results

- SE: 25 Swift tests and `testTabBarAppearanceAndLabelTouches` passed.
- iPhone 14: the same 25 Swift tests and UI test passed.
- The UI test switches app Light → Dark → Light while the system remains dark,
  captures Home each time, and taps all four visible label bands by absolute
  coordinates, asserting the selected tab after each tap.
- Docker full app run: 855 passed, one failed because the isolated copy initially
  omitted `docs/design/home-mock.png`. With that fixture restored, the complete
  `home_golden_test.dart` plus `native_tab_bar_test.dart` rerun passed all 33 tests,
  covering the missing case and both device-size bridge cases. No goldens changed.
- An isolated invocation of just the comparison case showed an 800-pixel logo
  difference; running its complete test file in normal order passed. This is
  recorded rather than presenting that isolated invocation as a successful run.
- Both task-owned simulators were shut down and deleted after capture. Large
  local build/test scratch was removed; only these screenshots and this record
  remain as evidence.

## Screenshots

| Device | Light before | Dark before | Light after | Dark after |
| --- | --- | --- | --- | --- |
| SE | [Before](se-before-light.png) | [Before](se-before-dark.png) | [After](se-after-light.png) | [After](se-after-dark.png) |
| iPhone 14 | [Before](iphone14-before-light.png) | [Before](iphone14-before-dark.png) | [After](iphone14-after-light.png) | [After](iphone14-after-dark.png) |

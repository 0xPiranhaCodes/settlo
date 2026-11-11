# #174 evidence: tab taps and Profile layout on iOS

Captured on 11 Nov 2026 on a dedicated iPhone 17 Pro simulator on iOS 26.1
(created for this, deleted afterwards), in dark theme. The app is
`app/integration_test/native_tab_bar_app.dart`: the production router and
shell on the widget tests' fakes, with the rc7 owner's profile (no name, no UPI
ID). Touches are real UIKit touches sent by XCUITest, not Flutter's synthetic
pointer events. **Before** is `main` at `870db42` (rc7's code), **after** is
this PR.

| File | What it shows |
| --- | --- |
| `owner-profile-rc7.png` | The owner's rc7 report, for reference |
| `before-tab-taps-from-profile.mp4` | Spaces, Home, Loans, Home, Activity and Home tapped from Profile. Nothing happens. |
| `after-tab-taps-from-profile.mp4` | The same taps. Each tab opens, and Home returns to Profile, which the Home tab keeps. |
| `after-tap-{spaces,loans,activity}.png` | The tab each tap opened |
| `after-tap-home-again.png` | Tapping Home again while on Profile goes back to Home |
| `before-profile-top.png`, `after-profile-top.png` | No name: before, an empty line pushes the phone number down beside the `?`. After, it says "Add your name". Contacts matching and App lock, which have no action yet, are hidden. |
| `before-profile-end.png`, `after-profile-end.png` | Scrolled to the end. In both, Delete account ends above the bar. Change number, which has no action yet, is hidden. |

## Root cause

The tap bug is not specific to Profile. Before this PR, the native bar ignored
real taps on every screen, including Home and #157's bare glass probe. Flutter's
gesture arena accepted each tap for the `UiKitView` (`acceptGesture`, seen with
`debugPrintGestureArenaDiagnostics`), but `tabBar(_:didSelect:)` never ran.
Under the default `Eager` blocking policy, iOS 26's `UITabBar` never got the
tap that Flutter released to it. Registering the view with
`FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture` fixes
it. With that policy, the engine asks Flutter's hit test whether the touch
reaches the platform view, so a dialog's barrier over the bar still blocks it.

#160's tests missed this because widget tests can't reach UIKit, and
`RunnerTests` calls the delegate directly.

The bottom inset was never lost. The owner's screenshot is mid-scroll, where
rows are meant to pass under the glass. `before-profile-end.png` shows the last
row clearing the bar.

The gap above the avatar row is the same 24 pt that Space detail leaves under
its large title. On rc7 it looked bigger because the empty name line sat
beside the avatar.

## Tests

- `app/ios/RunnerUITests`: real touches on every tab from Profile, Space,
  Balances and Loan detail (the screens pushed inside the shell). Home from
  Profile goes back to Home, and Profile's last row ends above the bar. All 3
  pass with this PR. Without the policy change, the two tap tests fail. They
  aren't in hosted CI, which builds iOS but doesn't run XCTest. To run them:
  `flutter build ios --simulator --debug -t integration_test/native_tab_bar_app.dart`,
  then `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner
  -destination 'id=<simulator>' -only-testing:RunnerUITests`.
- `app/test/in_shell_tabs_test.dart`, for each of those screens: the engine's
  hit test reaches the bar at every tab, a native tap opens each tab, and the
  lowest text ends above the bar at the end of the scroll. A dialog keeps the
  bar from UIKit.

On the Balances screen, XCUITest's element `tap()` on Loans was delivered to
the selected tab (Spaces) instead, every time it was tried. A coordinate tap
at the same point worked, so the UI tests touch each tab's centre. Whether a
finger can hit the same case is not proven either way.

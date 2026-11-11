# #157 evidence: native iOS tab bar

Captured on 11 Nov 2026 with Xcode 27.2, on the iOS 26.1 (iPhone 17 Pro) and iOS 18.2 (iPhone 16) simulators. The app ran with the widget tests' fake session and data (`fakeSessionApp` with `homeMain`), and the router stepped through Home, Spaces, Loans, Activity and Profile, scrolling each one to the end.

| File | What it shows |
| --- | --- |
| `ios26-light-home.png` | System Liquid Glass bar over Home, with the loan card visible through the glass |
| `ios26-light-*-scrolled.png` | Each tab scrolled to the end, with the last row fully above the bar |
| `ios26-dark-activity.png`, `ios26-dark-home-scrolled.png` | The app's dark theme sets the bar's appearance while the system is light |
| `ios18-light-*.png` | iOS 18.2 gets the standard system tab bar |
| `ios26-switching-tabs.mp4` | Router-driven tab changes, with the native selection following them |

There was no iOS 17 runtime installed, so iOS 18.2 stands in for an earlier iOS. Taps on the native bar are covered by `RunnerTests` and `app/test/native_tab_bar_test.dart`, because `simctl` can't tap.

## Review fixes (PR #160)

Captured on 11 Nov 2026 on a dedicated iOS 26.1 iPhone 17 Pro simulator (`settlo-157`, deleted afterwards), with `glass_probe.dart`. The probe runs the real `SettloShell` and native bar over Settlo cards. For 10 seconds only the background is under the bar, then the "Goa trip" card scrolls under it and stays there.

| File | What it shows |
| --- | --- |
| `glass-light-compare.png`, `glass-dark-compare.png` | Bar crops. Top: nothing under the bar, so the platter is plain background. Bottom: the card under the bar, where the platter turns the card's colour and the blurred "Goa trip" glyphs show through under Home and Spaces. The glass samples Flutter's pixels, so no UITabBarController host is needed. |
| `glass-{light,dark}-{empty,card}.png` | The full frames behind those crops |
| (same frames) | The selected tab uses Settlo's `action` token: ink in light, gold in dark. It is never system blue. |
| `ax5-dark.png` | At the largest accessibility text size (AX5), UIKit keeps the tab bar at its standard size, as it does in Apple's apps. The probe's own fixed-height card text overflowing is the probe's problem, not the bar's. |
| `lifecycle-background-resume-restart.png` | Left to right: backgrounded to Settings; resumed with the same PID and the card still under the bar; after a hot restart (new engine run, new platform view), the bar is recreated with Home selected |
| `xctest-ios26.txt` | `RunnerTests`: 6 of 6 passed on iOS 26.1, including the tint and VoiceOver tests |

VoiceOver is covered by `testTabsAreVoiceOverButtonsWithSelection`. It turns on UIKit's accessibility runtime as an assistive client would, then checks four buttons labelled Home, Spaces, Loans and Activity. Only the router's tab carries the `selected` trait, and that trait follows an `update`.

Not proven: the large-content viewer HUD itself. Showing it needs a long press, and nothing here can send touches to the simulator (`simctl` can't, and the AXe tap is blocked by Homebrew tap trust). UITabBar caps its text at XXL and serves larger sizes through that HUD, as `ax5-dark.png` shows. Reduce Transparency and OS state restoration were also not exercised.

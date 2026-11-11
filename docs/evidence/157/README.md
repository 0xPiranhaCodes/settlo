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

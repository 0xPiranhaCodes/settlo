# #188 evidence: tab lens moves but the tab doesn't switch

Captured on 11 Nov 2026 on a dedicated iPhone 17 Pro simulator on iOS 26.1
(created for this, deleted afterwards). The app is
`app/integration_test/native_tab_bar_app.dart`. **Before** is `main` at
`aceb1d8` (TestFlight build 8), **after** is this PR.

## Reproducing the device failure on the simulator

#182's XCUITest grid passed on the old code because XCUITest is an
accessibility client: while it runs, UIKit fills in `accessibilityLabel` on its
private tab views. A finger on a phone with VoiceOver off has no such client.
These touches go through Simulator's own HID path (`SimDeviceLegacyHIDClient`,
the path idb uses), with no XCUITest in the process:

- `simtouch.m` sends touch-down, move and touch-up through Simulator's HID
  client. Build it with `clang -fobjc-arc -framework Foundation -framework AppKit
  simtouch.m -o simtouch`.
- `hidrun.sh <udid> <prefix>` runs these 9 steps and takes a screenshot after
  each one:
  1. Tap Spaces, Loans, Activity and Home at icon height.
  2. Tap each tab again in the home-indicator band, 61pt down a 83pt bar.
  3. Drag up off the bar from Spaces.

| File | What it shows |
| --- | --- |
| `hid-before.png` | Build 8's code. The lens moves to each tapped tab, then snaps back. All 9 steps stay on Home, as on the owner's iPhone. |
| `hid-after.png` | This PR. Every step opens its tab: 4 taps, 4 band taps and the drag-off. |
| `hid-order.log` | Temporary logging on HID touches with this PR. At icon height, UIKit's `didSelect` sends the tap before the lift. In the band, UIKit selects nothing, so the lift sends it. A touch 11pt above the screen's bottom edge never reaches the app, because the system takes it. |
| `pill-native-parity.png` | Top to bottom: native `UITabBarController` in dark, ours in dark, native in light, ours in light, then the owner's Slack screenshot. |

## Root cause (confirmed)

`lifted(at:)` found the tapped item by walking the hit-test chain and matching
`accessibilityLabel` against the item titles. Without an accessibility client,
every view in that chain has a `nil` label: `_UITabButton`, `ContentView` and
`_UITabBarPlatterView`, dumped in `RunnerTests` without the accessibility
runtime. So no item ever matched, and the bar snapped back to the old tab.
Meanwhile `tabBar(_:didSelect:)` was ignored while the finger tracked, so
UIKit's own correct selection was dropped. The lens moved, because UIKit
selected, but no `tap` reached Flutter.

The other suspects in #188 aren't needed to explain the bug, but the fix covers
them too. A cancelled touch now leaves UIKit's selection in place, and the
hit-test chain is no longer used.

## Fix

- **UIKit's selection counts:** `didSelect` always sends `tap`, including on
  drag-off, as in a native tab bar.
- **Lift fallback:** the lift sends a tap only when UIKit selected nothing for
  that touch, which happens in the home-indicator band. It finds the item by
  geometry: the nearest tab button (`UIControl`) centre across the bar. It
  handles right-to-left layouts.
- **One tap per touch:** a touch sends at most one `tap`. Selections with no
  touch, such as VoiceOver's, are always sent.
- **Cancelled touches:** a cancel sends nothing and doesn't reset the selection.
- **Refused tabs:** the router still snaps a refused tab back via `update`.

## Selected-tab pill

On the simulator, our bar matches a native `UITabBarController` drawn over the
same page colour (`#0A0B0D`):

| | Pill | Platter |
| --- | --- | --- |
| Native, dark | 66,66,68 | 14,14,16 |
| Ours, dark | 57,58,61 | 20,22,25 |

Light mode matches too. Our selected icon is dark there because Settlo's light
action token is dark. Slack's lighter platter and darker pill come from its
lighter page (27,29,33) behind the glass. The black pill the owner sees is
device-only and can't be reproduced here. The suspect is that on device GPUs
the glass doesn't sample Flutter's Metal layer behind the platform view. A
follow-up needs a screenshot from the owner's device. No tint was guessed here.

## Tests

- `RunnerTests`: 17/17 pass. The new tests cover:
  - UIKit selection then lift (one tap)
  - drag-off
  - cancel after UIKit's selection
  - cancel with no selection
  - a lift in the home-indicator band with no `didSelect`, then a router refusal
  - every tab found by geometry with all labels cleared
  - right-to-left layout
  - VoiceOver selections after a touch
- `RunnerUITests`: the 180-point grid (`testEveryPointOfEveryTabSelectsIt`) and
  the 4 other existing tests pass. The new `testDragOffTheBarSelectsTheTab`
  passes on its own run. It replaces `testDragFromTheBarKeepsTheTab`, which
  asserted the old behaviour, where drag-off snapped back.

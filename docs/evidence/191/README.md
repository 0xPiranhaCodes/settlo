# #191 phase 2: Liquid Glass header buttons, soft scroll edge, S mark

Captured on 12 Nov 2026 on a dedicated iPhone 17 Pro simulator running iOS 26.1, created for this task and deleted afterwards. Before is `main` at `767087a`; after is this PR. The app is `glass_capture_app.dart.txt`, which uses the fakes and reads the theme, route and unread count from `Documents/capture.txt`. Copy it to `app/integration_test/glass_capture_app.dart` to build it. Touches go through Simulator's HID path (`docs/evidence/188/simtouch.m`). Every capture has 3 unread entries, so the bell shows its badge.

## Files
- `home.png`, `space.png`, `balances.png`, `profile.png`, `spaces.png`, `loans.png`, `activity.png` and `loan.png`: for each screen, the top row is before and the bottom row after. The columns are dark at rest, dark scrolled, light at rest and light scrolled. Driver: `capture.sh <before|after>`.
- `home-scroll-before-after.mp4`: Home scrolled by the same scripted HID drags. Before is on the left and after on the right, with dark on top and light below.
- `hid-taps.png`: Home, then an HID tap on the glass bell (Activity opens), then an HID tap on the glass avatar (Profile opens, with its one-off reminder prompt).
- `frames-<build>-<theme>.txt`: one line per frame, as `build,raster,total` µs, recorded by `perf.sh` over the same scroll.

## Frame timing (Home, scripted scroll, about 14 s per run)
Flutter has no profile mode on the simulator (`Profile mode is not supported for simulators`), and no device was attached. These numbers come from **debug** builds on the simulator, with both builds measured the same way, so they are only good for comparing before with after. Profile numbers on a device are still needed (#190).

| Run | Frames | Build p50 / p90 / p99 (ms) | Raster p50 / p90 / p99 (ms) | Frames over 16.7 ms |
|---|---|---|---|---|
| before, dark | 486 | 1.3 / 1.7 / 6.2 | 2.9 / 3.9 / 5.1 | 0 |
| after, dark | 465 | 1.1 / 1.5 / 6.0 | 2.6 / 3.5 / 4.3 | 0 |
| before, light | 495 | 1.3 / 1.7 / 6.4 | 3.0 / 3.9 / 4.8 | 0 |
| after, light | 494 | 1.1 / 1.5 / 6.4 | 2.6 / 3.4 / 4.3 | 0 |

## Notes
- **Taps, drags and the gesture policy.** Under the eager blocking policy, an HID tap on the glass button did nothing, the same iOS 26 problem #174 hit with the tab bar. The factory uses `DoNotBlockGesture`, and Flutter holds only a `TapGestureRecognizer`, so a drag that starts on a button still scrolls the page. That was checked with HID: a drag down from the bell opened the refresh control, and the tap didn't fire.
- **Soft edge.** No blur. A `ShaderMask` over a `BackdropFilter` rendered nothing under Impeller, so any blur had to be clipped, and a clipped blur always ended on a visible blur-to-sharp line. The edge is a page-colour scrim only: 94% at the top, 90% at the bar's bottom, then an eased fade to 0 over the 32pt of content below. Without the blur layers, raster p50 drops from 3.4 ms to 2.6 ms in these debug runs, below `main`.
- **Large-title screens.** Space, Balances, Profile and loan detail keep the native collapsing bar, made clear, and get the same edge from a sliver that takes no space and paints under the bar.
- **Native views.** The header keeps the same widget tree at rest and when scrolled, so scrolling never recreates the glass buttons (`scrolling keeps the native view IDs` in `liquid_glass_test.dart`).

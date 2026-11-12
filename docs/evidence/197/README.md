# #197: bell and avatar on every tab, header scrolls away, status-bar blur only

Captured on 12 Nov 2026 on a dedicated iPhone 17 Pro simulator running iOS 26.1, created for this task and deleted afterwards. The app is `docs/evidence/191/glass_capture_app.dart.txt` (fakes; theme, route and unread count from `Documents/capture.txt`), copied to `app/integration_test/glass_capture_app.dart` to build. Touches go through Simulator's HID path (`docs/evidence/188/simtouch.m`). The scripts expect `simtouch` and a `udid` file next to them. Every capture has 3 unread entries.

## Files
- `tabs-dark.png`, `tabs-light.png`: Home, Spaces, Loans and Activity (rows), each at rest, mid-scroll and scrolled (columns), top 45% of the screen. Mid is a held drag, so short tabs (Spaces) show the header under the island before bouncing back. Driver: `cap.sh`. Captured at `3113832`, before the inset clip: the glass actions there fade out over the first 4pt; `offsets-*.png` supersede them.
- `island-mid.png`: the mid frames' status bar at full resolution, dark on the left and light on the right.
- `scroll.mp4`: scripted HID scrolls of Home dark, Home light and Activity dark, side by side.
- `hid-taps.png`: Spaces with its +, bell and avatar; an HID tap on the bell opens Activity, which shows only the avatar; an HID tap on Loans' avatar opens Profile.
- `offsets-dark.png`, `offsets-light.png`: Activity, Home, Loans and Spaces (rows) at rest and after held HID drags aimed at 4, 20, 40 and 60pt of scroll (columns), top of the screen. Driver: `capoff.sh`. The host's load average was about 550 while this ran, so the real offsets drift from the targets, and the Loans light rest frame caught the app still launching; its 4pt frame shows the rest state.
- `frames-<before|after>-<tab>-<theme>.txt`: one line per frame, as `build,raster,total` in µs, from `perf.sh` over the same scroll. Before is `main` at `648c88d`.

## Frame timing (scripted scroll, about 14 s per run)
These are **debug** builds on the simulator, since Flutter has no profile mode there. The host was heavily loaded (load average about 50), so the numbers are only good for comparing before with after. The last column counts frames whose build plus raster exceeds 16.7 ms, as in #191.

| Run | Frames | Build p50 / p90 / p99 (ms) | Raster p50 / p90 / p99 (ms) | Over 16.7 ms |
|---|---|---|---|---|
| before, Home dark | 299 | 1.2 / 1.8 / 14.9 | 2.9 / 3.9 / 5.6 | 3 |
| after, Home dark | 396 | 1.1 / 1.8 / 12.5 | 3.0 / 4.1 / 6.3 | 5 |
| before, Home light | 454 | 1.1 / 1.7 / 5.9 | 2.7 / 3.7 / 4.7 | 2 |
| after, Home light | 458 | 1.0 / 1.4 / 5.1 | 2.8 / 3.5 / 5.4 | 2 |
| after, Activity dark | 467 | 2.7 / 3.3 / 8.9 | 1.2 / 1.9 / 3.0 | 0 |

The blur adds about 0.1 ms to raster p50.

## Decisions
- **Status bar.** On tab roots (`SettloScrollScaffold(stickyHeader: false)`), the only pinned element is the status bar: on iOS, a blur with sigma 8 clipped to the top inset, under a 90% page-colour veil that runs past the blur and eases out over 10pt. Both fade in over the first 16pt of scroll, so nothing shows at rest. The blur's clipped edge sits under the veil, so there's no visible line. Measured on Home light, the step from veil to content is a smooth ramp over the 10pt. Android and high contrast use the veil alone (Android at 90%, high contrast opaque), with no blur.
- **Native glass actions.** Flutter's blur doesn't reach a platform view, so each glass action is clipped where it enters the status-bar band (`GlassActionInset`): the clip line is the top inset, measured from the action's painted position, so the actions scroll 1:1 with the title and only the part inside the band disappears, the bell's badge overhang included. Flutter titles keep scrolling under the blur. The clip is always in the tree, so scrolling never recreates the views (`scrolling keeps the native view IDs, sticky: false`); `native actions scroll with the title, clipped at the inset` checks lockstep and the clip line at 0, 4, 20, 40 and 60pt.
- **Activity has no bell.** Activity is the notifications list, and opening it marks everything seen, so it shows only the avatar. Its old "show newest" bell action is gone; tapping the status bar still scrolls to the top. With the + on Spaces and Loans, the actions still line up at the right edge of every tab.
- **Inner screens are unchanged.** Large-title screens keep the native collapsing bar and #195's soft edge. A status-bar-only edge would leave the collapsed title and back chevron over unveiled content. Android inner screens and sheets keep their sticky header.
- **Avatar initial.** Features can't read Home's provider (ADR 0002), so `accountNameProvider` in core is pointed at Home's data in `main.dart`. The avatar opens Profile from one place, `SettloTabActions` in `tab_actions.dart`: `context.push(SettloRoutes.profileSheet)`, #200's root-navigator sheet, over whichever tab is open. `push`, since `go` would leave nothing behind the sheet.

# #196 evidence: Profile as a sheet

Captured on 12 Nov 2026 on a dedicated iPhone 17 Pro simulator on iOS 26.1
(created for this, deleted afterwards). The app is
`app/integration_test/native_tab_bar_app.dart`, the fakes' signed-in Home.
Every touch went through Simulator's HID path (`docs/evidence/188/simtouch.m`),
with no XCUITest in the process. Each drag was sent as one `simtouch` call; a
drag split across calls is dropped, because each call opens a new HID client.

| File | What it shows |
| --- | --- |
| `dark-open.png`, `light-open.png` | The avatar opened the sheet. Home recedes behind it, and the Close button is UIKit's glass. |
| `dark-scrolled.png`, `light-scrolled.png` | Scrolled: the header and Close stay pinned over iOS 26's soft edge. |
| `dark-middismiss.png`, `light-middismiss.png` | A drag down from the header, held a third of the way. Home and the tab bar show behind it. |
| `dark-export-pushed.png` | Export pushed inside the sheet, with its own Back. |
| `open-swipe-dismiss.mp4` | Dark mode: open (with the fresh-install reminders prompt), Export pushed, a drag down on Export that returns to Profile, a held drag that snaps back, scroll, a swipe that dismisses, reopen, and Close. |

A drag down while Export is showing returns to Profile rather than closing the
whole sheet: the sheet's pop handler gives back to the inner page first.

`RunnerUITests` passed on the same simulator:
`testAvatarOpensProfileSheetThatCloseDismisses` (Close and swipe down),
`testProfileLastRowIsOnScreen`, `testDragOffTheBarSelectsTheTab` and
`testHeaderGlassButtonsOpenTheirScreens`.

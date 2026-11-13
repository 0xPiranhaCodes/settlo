# Profile settings polish (#254)

The baseline is `5612e87e6605c1d6a643dfd3b60ef9869f0a9dc6` (origin/main,
including dark-mode #250). Both builds use the same offline Profile fixture,
the real Profile screen, and `SettloNavigatorSheetPage`; no backend is needed.
The capture entry point is retained as `capture.dart.txt`: copy it to
`app/test/settings_capture.dart` to build with the existing test fakes.

## Behavior

- A 68-point pinned task header contains a grabber, neutral 44-point Close
  target on the left, and centered Profile title.
- Header to identity card: 24 points. Section label to card: 8 points.
  Card to next section label: 24 points.
- The header uses the background at rest and an opaque surface plus hairline
  when content passes beneath it. It is inside the same viewport as the list.
- Clamping physics prevent negative list offsets. Cupertino's sheet scroll
  controller consumes header and content drags; the sheet moves only at top.
- The permission explanation (audit W3) is unchanged: it is implemented in
  `packages/platform/lib/src/reminder_permission.dart` and shared with loan
  creation, acceptance, and manual nudges, rather than local to Profile.

## Verification

- Profile package: 45 widget/repository tests passed, including light/dark
  header structure, measured token gaps, opaque scrolled chrome, and native
  routed-sheet drag ownership.
- Core scroll chrome: 22 tests passed.
- The new header assertions fail on the unchanged baseline (no Profile title).
- Linux golden regeneration uses `settlo/flutter-goldens:3.47.9-amd64`.
  Host dependency resolution is run again afterward.

## Native evidence

Recordings use task-owned iPhone 14 (390×844) and iPhone SE 3rd generation
(375×667) simulators on iOS 26.1. Touches go through SimulatorKit HID using
`docs/evidence/188/simtouch.m`, never semantic element activation. Each recording
opens Profile, scrolls upward, drags the pinned header downward, returns to the
top, and drags down again. Light and dark use the simulator appearance.
The first-run permission explanation is dismissed before the comparison.

The final Linux run passed all 145 Profile-golden and sheet-hit tests, including
200% text. All 72 changed PNGs were visually inspected. Existing truncation in
the UPI and secondary row copy at 200% is outside this header/spacing change.
The Android route's own handle is disabled for Profile to avoid a duplicate
handle; its default remains enabled for other navigator sheets.

Analysis passed with no issues. The navigator-sheet regression suite passed
4 tests, and the routed Profile test verifies Android has only the new grabber.

Reproduce: compile `simtouch.m` with `clang -fobjc-arc -framework Foundation
-framework AppKit`, place the executable at `/tmp/settings254-simtouch`, and
save the task-owned simulator UDID to a text file. Install and launch the
fixture app, wait for Open Profile, and dismiss the first permission prompt.
From Open Profile, run `python3 docs/evidence/254/record.py <output-prefix>
<light|dark> <udid-file>`. The recording script does not relaunch the app.
Videos are downscaled to logical phone width with H.264 CRF 20 for review;
PNG screenshots retain the native simulator resolution.

Both task-owned simulators were deleted after capture:

- `83FC35F1-9291-41E7-998D-C9F5D75FE126`
- `AAF644C4-EA2E-4C93-830E-F424A521E762`

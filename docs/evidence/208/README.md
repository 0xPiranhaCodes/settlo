# #208: safe demo VPA

The demo profile and settlement fixtures now use `demo@upi`, including validation,
repository, SQL, canvas, and documentation examples. The existing VPA validation
test accepts it and still rejects a handle with no local part.

## Images

- 60 affected app goldens were regenerated with Flutter 3.47.9 in the
  `settlo/flutter-goldens:3.47.9-amd64` ci-local Linux image. This includes Profile,
  Settle, Edit profile, and the Profile visible behind other sheets.
- 26 historical reference/evidence PNGs retain their original UI and dimensions.
  A current-app capture would misrepresent their old layouts, palettes, and
  before/after comparisons, so opaque gray rectangles cover the owner's real VPA,
  including four truncated fragments at 200% text size. `redactions.json` records
  each rectangle as inclusive `[left, top, right, bottom]` image-pixel coordinates.
  Pixel comparison against the parent revision confirms no changes outside them.
- Fresh `profile`, `edit-upi`, and `settle` screenshots in both themes show the
  current app on a dedicated iPhone 15 Plus simulator running iOS 26.1, at
  1290×2796. These are native simulator screenshots with offline app fixtures.
  The task-owned simulator was shut down and deleted after capture.
  `capture_app.dart.txt` preserves the local entry point, derived from #191;
  copy it into `app/integration_test/demo_capture_app.dart` to build it. Its
  Documents/capture.txt accepts `THEME`, `ROUTE`, and `UNREAD` key/value lines.
  Profile uses `/home/profile`; Settle uses `/settle?space=s1&member=m3`.
- Fourteen fresh website shots (Home, Balances, Loans, Activity, Profile,
  Add expense, Spaces; light and dark) were saved to the requested external
  scratchpad location, not added to this PR. Each is 1290×2796.

All 1,050 pre-existing tracked raster assets, including `site/images` PNG, WebP,
AVIF, and JPEG files, were scanned with Apple's Vision text recognition. That
initial scan missed six readable instances across the Profile and Edit profile
comparisons. A
separate scan of all 20 fresh evidence and website captures reported no matches. The existing website assets needed no
redaction. The initial visual review also missed those six instances; the follow-up
below records their correction.

## Validation

- `flutter analyze`: no issues.
- All workspace members with tests passed in the pinned Linux image, using
  `flutter test --coverage --concurrency=2`: app 795, core 471, local 73,
  platform 76, auth 59, profile 42 (1,516 tests total).
- The initial core run hit the existing large-export scheduling assertion:
  323 ms versus a 250 ms limit. The unchanged full core rerun passed all 471
  tests; no tests or thresholds were changed or skipped.
- The exact CI coverage enforcement step, run against the merged LCOV and
  origin/main baseline: **98.52% (5,706/5,792)** versus **98.11%** required.
  Money coverage: **100% (110/110)**.
- Host `flutter pub get` restored `.dart_tool` after Linux golden regeneration;
  the full Linux tests used an isolated source copy. All tracked Dart and SQL
  files in that copy match the submitted tree.
- Original bank-handle search over tracked text: no matches. `.github` unchanged.
- All six evidence captures and fourteen external website shots are 1290×2796;
  both OCR and visual review passed. The dedicated simulator was deleted.

## PR #209 review follow-up

Added six opaque `#777777` rectangles in the existing style:

- Edit profile comparison: middle column, rows 3 and 4 (the review finding),
  plus left column, row 2 (found during follow-up visual inspection).
- Profile comparison: left column, rows 1, 2, and 4 (found by the full audit).

Both corrected images were visually inspected. Pixel comparisons against
`ecadc81` confirm unchanged dimensions and no changes outside the six new
inclusive rectangles recorded in `redactions.json`.

The follow-up uses Tesseract 5.5.4, sparse-text mode, on whole images and on
1,200-pixel-high overlapping crops (1,050-pixel step) for images taller than
1,500 pixels. The unredacted Edit profile comparison is a positive control:
the whole-image pass detects all three exposed fields, and the cropped passes
detect each again. The two corrected comparisons pass all ten whole/cropped
passes with zero matches and zero errors.

The full repository audit completed all 1,056 tracked raster assets: 1,019 PNG,
24 AVIF, and 13 WebP (there are no tracked JPG/JPEG files), across 2,382
whole-image/crop passes with zero decode or OCR execution errors. After fixing
the Profile findings and rescanning both corrected comparisons, no owner-VPA
matches remain. The only remaining broad bank-suffix matches are in the Settle
comparison; visual inspection confirms they belong to the unrelated fictional
settlement fixture, not the owner's VPA.

A supplementary Apple Vision scan detected the missed Profile fields but
encountered recognition errors; it is not counted as a complete clean audit.
`flutter analyze` was rerun and reports no issues. No application code changed.

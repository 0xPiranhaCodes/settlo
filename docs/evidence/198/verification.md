# Issue 198 verification

Validated locally with Xcode 27.2, iOS 26.1 (iPhone 17 Pro simulator) and an
Android API 35 emulator. Hosted CI is pending the manager's CI window; no
`.github` files changed.

## Results

- `flutter analyze`: no issues.
- `flutter build ios --simulator --debug`: passed. `flutter build apk --debug`: passed.
- App tests: 418 passed (`flutter test --no-pub --name '^(?!.*golden)'` over
  non-golden files, excluding the image-only `statement_name_image_test.dart`,
  which differs on macOS as noted in #192). Other workspace packages are
  untouched by this asset-only change and were not rerun.
- Master: `app/assets/icon/app-icon-v2.png`, 2576×2576 RGB, from the JPEG,
  unchanged. Its mark spans 75.4% of the width.
- Spacing (owner follow-up): `derive-app-icon.py --margin 0.18` (the default)
  writes `app/assets/icon/app-icon.png`, the unmatted mark scaled so it spans
  64% and centred on white; iOS and legacy Android are generated from it.
  Measured: 1024 iOS icon 63.96% span, centred within 1px.
- All 21 iOS catalog PNGs are RGB (no alpha) at their slot sizes.
- Adaptive foreground: mark trimmed to 1942×1941, scaled 0.2067 (the 66%
  safe-circle fit, 0.2435, times 0.64/0.754), so it shrinks from 473px to
  401px like iOS; furthest nontransparent pixel is 283.5px from centre. Background `#FFFFFF`. The unmatte recomposites to the
  master within 7/255 (only JPEG ringing in the white, zeroed below 8).
- Regeneration is byte-for-byte stable and leaves `project.pbxproj` unchanged.

## Evidence

- `ios26-home-light.png`, `ios26-home-dark.png`: SpringBoard captures via
  `simctl io screenshot`, refreshed for the spacing change on owned simulator
  `13CAA84C-A3F6-4536-A1BC-87BE7026E37C`, deleted afterwards.
- `android-app-drawer.png`: Pixel launcher All apps on an owned API 35
  emulator (AVD `icon198pad`, deleted afterwards), refreshed for the spacing
  change. The #198 `android-home.png` was removed as stale; `mask-preview.png`
  stands in for the home-screen masks.
- `mask-preview.png`: foreground on white under circle, squircle and rounded
  square masks over the 72dp viewport, before (top) and after (bottom); no
  foreground pixel falls outside any mask.
- `before-after-180.png`: the 180px iOS icon (60pt @3x) before and after.
- `monochrome-preview.png`: themed-icon silhouette tinted with light and dark
  Material palettes under the same masks.

## Unchanged

In-app S mark (`packages/core/assets/brand/`), website favicon/header/touch
icon (`site/`, `design/brand/website/`), splash images and
`app/flutter_native_splash.yaml`. No Play Store 512 icon exists in the repo.

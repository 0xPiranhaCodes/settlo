# Issue 198 verification

Validated locally with Xcode 27.2, iOS 26.1 (iPhone 17 Pro simulator) and an
Android API 35 emulator. Hosted CI is pending the manager's CI window; no
`.github` files changed.

## Results

- `flutter analyze`: no issues.
- `flutter build ios --simulator --debug`: passed. `flutter build apk --debug`: passed.
- App tests: 422 passed (`flutter test --no-pub --name '^(?!.*golden)'` over
  non-golden files, excluding the image-only `statement_name_image_test.dart`,
  which differs on macOS as noted in #192). Other workspace packages are
  untouched by this asset-only change and were not rerun.
- Master: `app/assets/icon/app-icon-v2.png`, 2576×2576 RGB, from the JPEG.
- All 21 iOS catalog PNGs are RGB (no alpha) at their slot sizes.
- Adaptive foreground: mark trimmed to 1942×1941, scaled 0.2435; furthest
  nontransparent pixel is within the 337.92px (66%-diameter) safe circle of
  the 1024 canvas. Background `#FFFFFF`. The unmatte recomposites to the
  master within 7/255 (only JPEG ringing in the white, zeroed below 8).
- Regeneration is byte-for-byte stable and leaves `project.pbxproj` unchanged.

## Evidence

- `ios26-home-light.png`, `ios26-home-dark.png`: SpringBoard captures via
  `simctl io screenshot`. Owned simulator `7323C90F-FCCF-4D0C-85AE-9850B828F033`
  was deleted afterwards.
- `android-home.png`: Pixel launcher home screen with Settlo dragged onto it
  (the dock ring is the launcher's "Predicted app: Settlo" slot).
  `android-app-drawer.png`: the same icon in All apps. The app was uninstalled
  first so the launcher had no cached #192 icon. Emulator was killed with no
  snapshot save; the existing AVD was not deleted.
- `mask-preview.png`: foreground on white under circle, squircle and rounded
  square masks over the 72dp viewport; the script asserts no foreground pixel
  falls outside any mask.
- `monochrome-preview.png`: themed-icon silhouette tinted with light and dark
  Material palettes under the same masks.

## Unchanged

In-app S mark (`packages/core/assets/brand/`), website favicon/header/touch
icon (`site/`, `design/brand/website/`), splash images and
`app/flutter_native_splash.yaml`. No Play Store 512 icon exists in the repo.

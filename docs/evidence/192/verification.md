# Issue 192 verification

Validated locally with Flutter 3.47.9 / Dart 3.13.7, Xcode 27.2, iOS 26.1
(iPhone 17 Pro), and an Android API 35 emulator. Hosted CI and Linux golden
comparisons remain pending the manager's CI window; no `.github` files changed.

## Results

- `flutter analyze`: no issues.
- `flutter build apk --debug`: passed; APK installed on emulator-5580.
- `flutter build ios --simulator --debug --no-pub`: passed with final assets.
- Temporary, uncommitted XCTest launcher capture: 1 test passed. It pressed
  Home and located the actual Settlo SpringBoard icon before capture.
- Functional tests: app 421, core 407, local 73, platform 76, auth 59,
  profile 41: 1,077 cases. One core export responsiveness assertion initially
  took 291 ms against a 250 ms limit under concurrent builds/emulator startup;
  `flutter test --no-pub --concurrency=1 test/export/large_export_test.dart`
  passed on isolated retry. This is not an uninterrupted green full-suite run.
- Test selection: run each workspace member with `flutter test --no-pub
  --concurrency=2 --reporter expanded --name '^(?!.*golden)'`, selecting
  `*_test.dart` files without `golden` in their name and excluding the image-only
  `statement_name_image_test.dart`. Initial macOS golden comparisons differ
  from Linux references; no reference images were changed. Docker works, but
  no Flutter image was cached and disk was low; coordinator explicitly deferred
  Docker/hosted goldens.
- `SITE_IMAGE_PYTHON=python3 scripts/site-build-images.sh`: passed.
- `scripts/site-check.cjs`: passed at 360, 390, 768 and 1440 px, light/dark,
  landing/privacy/support, including JavaScript-disabled rendering, image
  density, motion and link checks. See `site-check.json`.
- Owner source PNG copied byte-for-byte; all 25 iOS catalog slots are correctly
  sized RGB images with no alpha and no unassigned PNGs. All Android densities
  regenerated; adaptive XML includes foreground, #0A0B0D background and
  monochrome. The 1024px foreground's furthest nontransparent pixel is
  335.259px from center, inside the 337.92px (66%-diameter) safe circle.
- The regeneration wrapper preserves the existing Xcode project byte-for-byte;
  it prevents flutter_launcher_icons from rewriting unrelated ASSETCATALOG
  boolean settings to `AppIcon`.
- Regeneration is byte-for-byte stable across 68 launcher source/output files.
- `mask-preview.png`: no foreground pixels clipped by circle/squircle masks.

## iOS optional appearances

flutter_launcher_icons 0.14.4 supports dark/tinted inputs, but its generated
appearance-aware catalog causes Xcode 27.2 warnings for missing required
60@2x/76@2x/83.5@2x icons and unassigned legacy PNGs. Per the conditional task
requirement, optional variants are omitted. The standard gold-on-dark artwork
is the same in both home-screen modes. An early build also reported a transient
asset-compiler “Distill failed”; direct asset compilation and subsequent full
builds passed. The final catalog uses the original, fully assigned slot layout.

## Evidence and remaining artwork

- iOS screenshots are actual SpringBoard captures, with the temporary test
  runner removed. Owned simulator UDID `0843A1B7-7C08-43E8-B130-3E2F36A672AB`
  was shut down and deleted after capture.
- Android screenshot is the actual API 35 Pixel launcher with Settlo placed on
  the home screen. The owned emulator-5580 process was stopped with no snapshot
  save; the pre-existing Medium_Phone_API_35 AVD template was not deleted.
- Website header captures are actual Chromium renders. Favicon images show
  the browser-selected icon rendered at 16/32/64px on matching tab-like surfaces;
  these are explicitly previews, not screenshots of browser chrome. Before
  captures serve the original HEAD HTML/CSS/mark via request interception.
- Website favicon/header/social-card mark now use the owner's white/black S;
  Apple touch icon uses the opaque gold app artwork.
- Unchanged old mark: `design/brand/derived/splash.png`, `android12-splash.png`,
  iOS `LaunchImage.imageset/LaunchImage*.png`, Android `drawable-*/splash.png`
  and `drawable[-night]-*/android12splash.png`, and in-app brand assets under
  `packages/core/assets/brand/`. `app/flutter_native_splash.yaml` still points
  to these old splash inputs.
- Marketing product screenshots remain faithful to current in-app branding:
  `site/images/home_main.webp`, `home_main-phone.webp`, `home_main-phone.avif`
  and its @2x/@3x variants, plus the embedded phone in `social.png`, still show
  the previous in-app S. The standalone social-card logo is updated.
- `app/web/favicon.png` and `app/web/icons/*.png` are Flutter defaults, not the
  old Settlo S, and remain unchanged.

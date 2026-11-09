# 0009 Native splash and app icon: flutter_native_splash and flutter_launcher_icons

## Status
Proposed (9 Nov 2026), with the native splash issue (#32).

## Context
The context pack fixes the splash: the mark alone on #0A0B0D, "via `flutter_native_splash`" (canvas note nsplash). It has to show from process start, before the Flutter engine draws, so it lives in native launch config: the iOS `LaunchScreen.storyboard` and its image set, the Android pre-12 `launch_background` drawable with density buckets, and the Android 12+ `windowSplashScreen*` theme attributes in `values-v31`. The app icon has the same shape of problem: about 20 iOS sizes in `AppIcon.appiconset`, five Android mipmap densities, and an adaptive icon for Android 8+. [0005](0005-dependency-policy.md) asks for an ADR for every new package, dev ones included.

## Decision
- Use **`flutter_native_splash`** (`^2.4.8`) and **`flutter_launcher_icons`** (`^0.14.4`) as **dev_dependencies of `app`**. They are code generators run by hand; nothing in `lib/` imports them and they ship nothing in the app binary.
- Their config lives in `app/flutter_native_splash.yaml` and `app/flutter_launcher_icons.yaml`, not in `app/pubspec.yaml`, so the pubspec only gains the two dev_dependency lines. Source images are the owner's marks in `design/brand/` plus the sized variants in `design/brand/derived/`, made by `derive.sh` there (the Android 12+ and adaptive-icon foregrounds need a transparent mark, cut from `mark-cream-on-black.png` by luminance and recoloured #D8B36A). None are bundled as Flutter assets.
- The generated files under `app/ios/` and `app/android/` are committed. To change the mark: replace the owner PNGs, run `design/brand/derived/derive.sh`, then `dart run flutter_native_splash:create` and `dart run flutter_launcher_icons` from `app/`, and commit the output. Revert generator edits to `Info.plist` and `project.pbxproj` that are only reformatting, and set the `LaunchScreen.storyboard` view background back to #0A0B0D: the generator writes it white, which shows as a white flash in the iOS launch zoom.
- The splash is removed on the first Flutter frame (the default). We do not call `FlutterNativeSplash.preserve`, which would make the package a runtime dependency; the in-app splash with the ledger-sync bar is a Flutter screen.
- The icon is `mark-gold-on-black.png` full-bleed on iOS; on Android it is the adaptive icon (#0A0B0D background, gold S inside the 66 dp safe zone). The splash is the gold S on #0A0B0D (canvas note nsplash).

## Alternatives considered
- **Hand-written native config.** One-off, but every mark change means re-exporting about 40 PNGs at the right sizes and keeping three Android splash paths in sync by hand. Easy to get a density or the Android 12 safe circle wrong.
- **Only one of the two packages.** They solve different files; neither generates the other's output.

## Consequences
- 12 packages enter the lockfile, all dev-only: the two tools plus `ansicolor`, `archive`, `cli_util`, `csslib`, `html`, `image`, `petitparser`, `posix`, `universal_io`, `xml`. No change to app size or the native build beyond the generated resources.
- Android 12+ shows the system splash (icon on a circle mask, #0A0B0D); Android 8–11 and iOS 16.1+ show the full-bleed mark. Both hand over to Flutter on the first frame.

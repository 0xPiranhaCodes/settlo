# 0006 Fonts: bundled Figtree, no google_fonts

## Status
Accepted (9 Nov 2026). Amended after the PR #35 review to drop google_fonts,
and on 10 Nov 2026 by the owner-approved Home redesign to use Figtree for
amounts too.

## Context
The original type system paired Figtree with IBM Plex Serif for large amounts.
The owner-approved Home mock instead uses Figtree for amounts, and the 10 Nov
2026 manager ruling makes that treatment global. [0001](0001-stack.md) names
`google_fonts`, and [0005](0005-dependency-policy.md) requires a dependency to
arrive with the first code that imports it, which is the design system (#26).

By default `google_fonts` downloads font files over HTTP on first use. That breaks three things we need: the app must render amounts correctly offline ([0004](0004-offline-sync.md)), golden tests must render real glyphs without network access, and first paint should not flash a fallback font. The first version of this ADR bundled the files and kept google_fonts. Review of PR #35 found two problems with that. It pulled about 20 transitive packages into the lockfile, including `http`, `path_provider` with its native platform plugins, `jni`, `objective_c` and `ffi`. And any weight we had not bundled (for example a later `w600`) would still be fetched silently from fonts.gstatic.com in production.

## Decision
- **No font dependency.** `google_fonts` is not used, and this supersedes 0001's mention of it.
- **Bundled files.** The static files live in `packages/core/assets/fonts/`, with
  the Figtree SIL OFL 1.1 licence text. Regular, Medium and SemiBold cover the
  app and exported statements. The unused IBM Plex Serif font and licence were
  removed.
- **Declaration.** The files are declared as the `Figtree` family in
  `packages/core/pubspec.yaml`. Flutter bundles a dependency package's fonts
  into the app automatically.
- **Use.** Styles use plain `TextStyle(fontFamily: …, package: 'settlo_core')`, built only in `lib/theme/typography.dart` (`SettloTypography`). Feature code takes styles from the theme and never names a family.
- **Tests.** Tests load the fonts from the bundle's `FontManifest.json` with `FontLoader`, so goldens render real glyphs offline.

## Alternatives considered
- **google_fonts with bundled files and `allowRuntimeFetching = false`.** This was the first version of this ADR. It adds about 20 transitive packages (several of them native) for no capability we use, and it relies on a runtime flag to stay offline.
- **google_fonts with runtime fetching.** This gives the smallest app. But it has no offline first run, makes tests non-deterministic, and sends a request to Google on first launch.
- **The Figtree variable font.** One file would cover 400–700. But two static weights are simpler, and Flutter's variable-axis support adds complexity we don't need.

## Consequences
- **No new dependency.** The lockfile is unchanged by fonts, and nothing can fetch fonts at runtime: a weight that is not bundled falls back to the nearest bundled weight instead of reaching the network.
- **App size.** Removing the unused IBM Plex Serif file reduces the bundled
  font payload. Adding a weight means adding a file, a pubspec entry and a
  short note here.
- **Licences.** The OFL licences ship as assets. The app shell registers them with `LicenseRegistry` when the licences page exists.
- **Glyphs and figures.** Figtree includes U+20B9. Hero amounts use a 66%-size
  ₹, and figures are tabular through `tnum`.

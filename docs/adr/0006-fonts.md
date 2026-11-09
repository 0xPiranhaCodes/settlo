# 0006 Fonts: google_fonts with bundled Figtree and IBM Plex Serif

## Status
Accepted (9 Nov 2026)

## Context
The type system is Figtree (400 and 500) for text and IBM Plex Serif 500 for amounts at 20px and above, with tabular figures (context pack › Brand and design). [0001](0001-stack.md) names `google_fonts`, and [0005](0005-dependency-policy.md) requires a dependency to arrive with the first code that imports it, which is the design system (#26).

By default `google_fonts` downloads font files over HTTP on first use. That breaks three things we need: the app must render amounts correctly offline ([0004](0004-offline-sync.md)), golden tests must render real glyphs without network access, and first paint should not flash a fallback font.

## Decision
- Add `google_fonts` (^9.0.0) to `packages/core`, the only package that sets type.
- Bundle the static files we use as assets of `packages/core`: `Figtree-Regular.ttf`, `Figtree-Medium.ttf` and `IBMPlexSerif-Medium.ttf` (about 280 KB in total), with their SIL OFL 1.1 licence texts, under `packages/core/assets/fonts/`. The filenames match google_fonts' naming, so it loads them from the asset bundle and never fetches.
- Tests set `GoogleFonts.config.allowRuntimeFetching = false`, so a missing asset fails the test instead of reaching the network.
- Figtree comes from its upstream repository (static TTFs; Google Fonts ships only the variable file); IBM Plex Serif from google/fonts.

## Alternatives considered
- **Fonts declared in `pubspec.yaml` without google_fonts.** No dependency and equally offline. Rejected only because 0001 already chose `google_fonts`, and it gives typed `GoogleFonts.figtree()` styles and an easy path to a further weight later. If google_fonts ever becomes a burden, switching is local to `lib/theme/typography.dart`.
- **google_fonts with runtime fetching.** Smallest app, but no offline first run, non-deterministic tests, and a request to Google on first launch.
- **The Figtree variable font.** One file for 400–700, but google_fonts matches assets by static weight name, and Flutter's variable-axis support adds complexity for two weights.

## Consequences
- About 280 KB of fonts in the app bundle; another weight means another file and a short note here.
- The OFL licences ship with the assets; the app shell registers them with `LicenseRegistry` when the licences page exists.
- The 56%-size ₹ uses Figtree, which includes U+20B9; Plex Serif digits are tabular by default (it has no `tnum` feature), Figtree's via `tnum`.

# Issue 204 verification

Website rebrand to SabkiJeb at https://sabkijeb.app.

Final local verification on 2026-11-12:
- Rebased onto origin/main. JOSH Studio remains the operator and linked footer
  credit, per the owner decision. No `.github` changes.
- `scripts/site-check.cjs`: PASS, served by `scripts/site-serve.py --port 8794`.
  Covers 360, 390, 768 and 1440 px, light/dark, landing/privacy/support,
  JavaScript disabled, motion, density, metadata and policy-body checks.
  Results: `site-check-browser.json`, `site-check-motion.json`,
  `site-check-density.json` and `structured-data.json`.
- `scripts/site-images-ready-check.cjs`: PASS (15 no-JS density runs;
  corrupt image rejected).
- Landing image alternatives: 142,280 / 241,361 / 342,877 bytes at 1x/2x/3x,
  below the 358,400-byte limit.
- Lighthouse mobile performance is **pending** the required 0.95 threshold.
  Final unchanged-source runs scored 0.93 and 0.86, both with slow-host CPU
  warnings; accessibility, best practices and SEO scored 1.00 throughout.
  A concurrent run scored 0.67 with a cache timeout and slow-CPU warning.
  The earlier run before the responsive reminder-width fix scored 0.99.
  `lighthouse-mobile.json` contains the latest final-source run;
  `lighthouse-runs.json` records the isolated final-source measurements.
  The coordinator approved pushing with this limitation and plans live-site
  Lighthouse verification after publishing. Local results are not deployment proof.

All six pinned captures were replaced with the supplied fresh iOS 26 simulator
exports. Profile and the UPI detail show `demo@upi`. `scripts/site-build-images.sh`
rebuilds all phone densities, PNG fallbacks and detail crops without Flutter or
external temporary paths; `site/images/sources.json` records source hashes.
Both site themes use light captures with native system chrome preserved.
Home uses Home; Goa uses Spaces; the flat uses Balances; loans use Loans and Activity.

Apple Vision accurate OCR scanned every site raster and all six pinned captures
(40 images), with zero private-VPA marker matches. `image-privacy-check.json`
records the scope and hashes. The privacy text scan is scoped to this PR's files
per coordinator direction; repository-wide fixture cleanup remains in #209,
which must merge before #207.

The reminders detail now shows the Profile Reminders toggle. The instalments
detail retains Arjun's loan progress card; both PNG and AVIF files differ.
The reminder image scales to its tile width, keeping its toggle visible on mobile.
Landing screenshots were refreshed at 360, 390, 768 and 1440 px in both themes.
The 390/1440 screenshots, mobile detail crop and source-screen contact sheet were
visually inspected. Privacy and support screenshots were also refreshed by the checker.

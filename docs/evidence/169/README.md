# Issue 169 — premium landing pass

Base: `4aee36011fd71b0f1071679cb4f641faf4188232`. Before captures were made before editing this worktree. Production app code, CI golden tests/PNGs and `.github` are unchanged.

## Visual review

- Hero: [before, 390×844](before/hero-390.png) / [after](after/hero-390.png); [before, 1440×900](before/hero-1440.png) / [after](after/hero-1440.png). The product now starts at y=462 on mobile, leaving 382 CSS pixels in the first viewport. It also appears in the first desktop viewport.
- Sharpness: [before at 3x](before/sharpness-3x.png) / [after at 3x](after/sharpness-3x.png), and [before at 2x](before/sharpness-2x.png) / [after at 2x](after/sharpness-2x.png). These are browser screenshots at their native pixel resolution, with the phone displayed at 390 CSS pixels and a fixed 300×180 CSS-pixel clip at (45,140). View at 100%, without fitting to window, to judge the actual pixels. The old file is the original 1x WebP; the new file is the selected density's AVIF. No image model or sharpening filter touched either screen.
- Goa: [desktop story](after/trip-story-1440.png), [tablet](after/trip-story-768.png), [mobile](after/trip-story-390.png). A bounded-height sticky phone accompanies three compact desktop steps. Narrow screens use normal flow so a tall sticky phone cannot obscure the story. Both Goa and Flat 402 have a 432px canvas at 768px, proven in [density.json](after/density.json).
- Features: [desktop](after/features-1440.png), [mobile](after/features-390.png). Four differently sized rounded tiles use full UI controls/cards from the 3x export. Crops were inspected against the real export; no cut-off labels or reconstructed type. The small Remind control stays at its native logical width to retain 3x resolution.
- Scrolling: [before desktop](before/scroll-1440.webm) / [after desktop](after/scroll-1440.webm); [before mobile](before/scroll-390.webm) / [after mobile](after/scroll-390.webm). Before mobile recording used the existing 390×900 recorder; the updated recorder uses the required 390×844 viewport. All hero stills use 390×844. The recording traverses the hero, Goa, feature tiles, flat and loan screens.

Design review: the new hero shows a legible balance before scrolling; the Goa phone has no clipped sticky top and the steps no longer create viewport-sized empty pauses. Native scroll transitions remain restrained. The reminder tile deliberately leaves breathing room around a single small real control; it does not enlarge a screenshot beyond its source density. The large Home amount and smaller secondary labels are materially sharper in the 1:1 comparisons. The owner's visual judgement is still required before merge.

## Validation

- Separate opt-in Flutter exporter: five screens passed; 1170×2532 output, DPR 3, the same fixtures/screen builders as the golden tests. [Run output](after/marketing-export.txt). `dart analyze app/test/marketing_export.dart`: no issues.
- [Browser checks](after/browser.json): 360, 390, 768 and 1440, light/dark, landing/privacy/support, no JavaScript; no horizontal scroll, policy bodies unchanged, resources/FAQ/schema intact.
- [Motion checks](after/motion.json): native, fallback and reduced-motion modes across all four widths and both themes. [Density checks](after/density.json): 1x/2x/3x selection, above-fold mobile hero, solid reduced-transparency nav and tablet phone equality.
- [Decode regression](after/image-decode.txt): 15 fresh no-JS contexts (five per density), plus corrupt bytes that must fail. Loading is made eager only in the checker, loaded state is polled without relying on animation frames, then the actual selected candidate is decoded. A replacement decode is allowed only by independently decoding its selected URL; broken bytes are never ignored.
- [Lighthouse mobile](after/lighthouse-summary.json), three independent cold Chrome launches: performance **99 / 99 / 99**, accessibility **100 / 100 / 100**, CLS **0 / 0 / 0**. Median is **99 / 100**, CLS **0**. Full reports are beside the summary. An earlier run while Flutter/browser export jobs competed for CPU scored 68/83/99; the reported runs are the isolated final runs.
- Images per complete page: **125.3 KiB at 1x, 232.1 KiB at 2x, 343.7 KiB at 3x**. Includes mark, all five full phone images, and four detail crops, even below-fold images. Density alternatives are mutually exclusive; the social card and unused legacy source assets are not page requests. The checker enforces 350 KiB independently at every density.
- Claims checked against `upi.dart`, loan detail/repayment and reminder code, the server's `remind_loan` cooldown/opt-out, and local repositories/sync. The tile copy does not promise offline reminders, payment verification, or erasure of other people's shared records. Details in `docs/brand.md`.

## Reproduce

```sh
(cd app && flutter test test/marketing_export.dart)
# Pillow 13.0.0 with AVIF support:
python scripts/site-images.py --ref HEAD
python scripts/site-phones.py
python -m http.server 8769 --directory site
# In another shell, with Playwright installed and CHROME_PATH if not on macOS:
SITE_CHECK_URL=http://127.0.0.1:8769/ node scripts/site-check.cjs
SITE_CHECK_URL=http://127.0.0.1:8769/ node scripts/site-images-ready-check.cjs
SITE_CHECK_URL=http://127.0.0.1:8769/ node scripts/site-record.cjs
```

`site/images/sources.json` records the pinned golden source hashes, 3x export hashes, exact logical crop boxes, generated frame provenance and encoding recipe. The generated frame was reused; no new generated UI or third-party design assets were introduced.

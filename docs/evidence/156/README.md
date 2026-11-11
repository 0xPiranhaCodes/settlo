# Issue #156 verification — review fixes

Local Chrome evidence, 11 November 2026. Before is `07e7eff3c7545a79bc20579ebdcb17745d966918`; after is this revision. This is local evidence, not deployed Pages performance.

## Review changes

1. Hardware uses one scale factor on both axes (788/746 before final downsampling), with the same opening and model for every screen. Phones use the full pinned 390×844 source goldens rather than stretching hardware around different crop heights. The screen background fills the few spare opening rows. Three phones retain ±3° plain 2D rotation. The older `crop_rows` entries describe the unchanged standalone crop assets; `phone.screen_crop_rows: null` explicitly records the full-screen phone inputs.
2. Removed all five artificial 2x files and srcsets. Each phone is a single 390px-wide WebP, matching the maximum CSS width, encoded at quality 80 for the hero and 88 for the remaining phones, with method 6. The hero is preloaded with high fetch priority, and the existing medium heading font is preloaded to remove its stylesheet discovery delay. No new screen detail is invented.
3. Corrected the rotation comment and extended overlap checks to section headings and the hero figcaption.

## Visual and functional verification

`after-{360,390,768,1440}-{light,dark}.png` contains new full-page captures. I inspected all four dark captures: consistent device proportions, readable UI at display size, and no overlap or clipped hardware. Light/dark preferences share the intentionally dark-only site. Browser geometry checks pass for all three pages at four widths in both preferences, without JavaScript, including resource failures, FAQ/schema and policy-body checks. The trip has an intentional horizontal swipe row.

`density.json` verifies that DPR 2 loads the same native-width composites and that all three trip panels can be reached without page overflow. Lighthouse flags the single-density hero under its high-DPR image-resolution best-practices audit; supplying duplicate pixels would not add real detail. HTML validation passes with exit 0.

`rebuild.json` records identical SHA-256 hashes for all five composites and the manifest after running both generators again. Source golden hashes are verified before composition. No app code or `.github` files changed.

## Reproduction

Pillow 13.0.0; tooling versions are listed in [../140/README.md](../140/README.md). The committed hardware, prompt, source hashes, encoding and geometry are recorded in [sources.json](../../../site/images/sources.json).

```sh
python3 scripts/site-images.py --ref 07e7eff3c7545a79bc20579ebdcb17745d966918
python3 scripts/site-phones.py
python3 -m http.server 8767 --directory site
NODE_PATH=/tmp/settlo-site-tools/node_modules SITE_CHECK_URL=http://127.0.0.1:8767/ SITE_CHECK_OUTPUT=/tmp/156-fixed node scripts/site-check.cjs
/tmp/settlo-site-tools/node_modules/.bin/html-validate --preset standard site/index.html site/privacy/index.html site/support/index.html
# Run sequentially for N=1,2,3, with screenshot work finished first:
CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' /tmp/settlo-site-tools/node_modules/.bin/lighthouse http://127.0.0.1:8767/ --chrome-flags='--headless=new --no-first-run' --only-categories=performance,accessibility,best-practices,seo --output=json --output=html --output-path=docs/evidence/156/lighthouse-mobile-N --quiet
```

## Final mobile performance

Three consecutive runs of the final version, default simulated mobile throttling:

| Run | Performance | LCP | TBT |
| --- | --- | --- | --- |
| 1 | 99 | 1.959s | 0ms |
| 2 | 88 | 1.952s | 434ms |
| 3 | 99 | 1.957s | 0ms |

Median: **99 performance, 1.957s LCP**. All runs have zero CLS. Run 2 includes 434ms TBT; it is retained, not discarded. See [raw summary](performance.json) and the three numbered JSON/HTML reports. The unnumbered report is the median-LCP run.

Landing image payload (all five phones plus the mark): **175,002 bytes (170.9 KiB)**, versus the review measurements of 449 KiB for the original PR and 99 KiB for main. This meets the revised 200 KiB budget but remains above main. The hero alone is 29,022 bytes. Build-only hardware, raw crops and the social preview are not loaded by the landing page.

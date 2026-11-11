# Issue #156 verification

Local Chrome evidence, 11 November 2026. Before is `07e7eff3c7545a79bc20579ebdcb17745d966918`; after is this PR. The near-black site intentionally looks the same under light and dark system preferences.

- `before-{360,390,768,1440}-{light,dark}.png` and corresponding `after-*` files show the complete page at 1x DPR. Mobile and desktop compositions were visually inspected; automated geometry checks cover all eight captures. Three of five phones rotate ±3°; Home and repayment remain straight. Existing whole-card crops remain intact.
- [Browser checks](browser.json): all three pages at four widths in both themes, JavaScript disabled. No horizontal page overflow, no failed/external requests, no phone/copy or phone/phone intersections. FAQ/schema, canonical/social URLs and unchanged policy bodies pass. The trip's intentional internal swipe row remains usable.
- [2x and swipe check](density.json): all five images select and decode the 2x source; all three trip panels scroll into view without page overflow.
- [Mobile Lighthouse](lighthouse-mobile.report.html): **96 performance, 100 accessibility, 100 best practices, 100 SEO**, default simulated mobile throttling, LCP 2.8s, TBT 0ms, CLS 0. [Raw report](lighthouse-mobile.report.json). Run separately from screenshot capture to avoid competing browser raster work. This is local evidence, not deployed Pages performance.
- [HTML validation](html-validation.txt): html-validate standard preset, all three pages, exit 0. Current CI contains no site validation job; Pages only uploads/deploys. No `.github` files changed.
- [Rebuild proof](rebuild.json): all ten WebPs and the manifest remain byte-identical after a second generation. RGB comparisons confirm the five screen interiors match the original crop pixels before rotation/downsampling (excluding the blank rounded corners). The raw screenshots and goldens are unchanged.

## Artwork and reproduction

The built-in image-generation tool produced only [this unbranded hardware asset](../../../site/images/device/studio-frame.png), using the [committed prompt](../../../site/images/device/prompt.txt). It never received or generated app UI. The deterministic compositor desaturates hardware edge fringes, pastes real screenshots into the measured opening, and rotates the entire composition. The source golden commit, hashes, crop rows, opening and angles are in [sources.json](../../../site/images/sources.json).

Use Pillow 13.0.0 and the tooling versions in [../140/README.md](../140/README.md):

```sh
python3 scripts/site-images.py --ref 07e7eff3c7545a79bc20579ebdcb17745d966918
python3 scripts/site-phones.py
python3 -m http.server 8765 --directory site
NODE_PATH=/tmp/settlo-site-tools/node_modules node scripts/site-check.cjs
/tmp/settlo-site-tools/node_modules/.bin/html-validate --preset standard site/index.html site/privacy/index.html site/support/index.html
CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' /tmp/settlo-site-tools/node_modules/.bin/lighthouse http://127.0.0.1:8765/ --chrome-flags='--headless=new --no-first-run' --only-categories=performance,accessibility,best-practices,seo --output=json --output=html --output-path=/tmp/156-lighthouse --quiet
```

The 390px and 780px lossless assets total approximately 370 KiB and 480 KiB respectively; only the selected density is downloaded. The 2x variant uses integer replication of the final composition to avoid invented UI detail and unnecessary lossless transfer cost. Source goldens contain 390px of real UI detail. Generated frame inputs are build-time assets, never requested by the page. All below-hero images remain lazy-loaded in normal browsing.

# Issue #164 — Settlo product page

Local Chrome evidence, 11 November 2026. Before: `874f3aad7462a299cbd2c3a6cd5ce438dd2bf345`. The after artifacts cover the site files hashed in `performance.json`. These are local checks, not a deployed Pages measurement.

## Result and visual judgment

The page now opens on warm paper with a centred 132px desktop headline, a real Home screen, and generous whitespace. Two near-black sections punctuate the light page; the system dark preference supplies a complete dark variant. The Goa narrative pins its introduction on desktop and its heading on mobile while the three steps pass. Phones rise, fade and gently tilt using native CSS view timelines. A small IntersectionObserver fallback handles older browsers; no-JS content remains available and reduced motion removes animations and sticky positioning.

I inspected all eight final full-page captures and sampled both actual scroll recordings throughout their duration. The result meets the requested product-page feel: restrained colours, large type, isolated phones and deliberate pauses. It is still recognisably Settlo through Figtree, gold, the S mark, real balances and precise confirmation language. The Goa section is intentionally a slower, tall narrative; the loan phones stack on narrow screens so the product does not become a pair of unreadable thumbnails. This is a design judgment, not a claim that visual similarity is measurable by Lighthouse.

The generated frame from #156 already works against light backgrounds; it is reused with CSS shadows and a soft gold glow rather than adding another raster backdrop. No new model-generated UI or device assets were needed. All screens remain full pinned app goldens composited in code. The 433px tilted canvases now retain the same physical scale as 390px upright canvases; paired CSS columns use those exact proportions. The manifest scale is derived from the screen and frame opening, and `rebuild.json` proves byte-identical regeneration. Historical #156 audit summaries remain; duplicated bulky HTML/JSON reports were removed for #163.

## Evidence

- `before-{360,390,768,1440}-{light,dark}.png` and matching `after-*.png`: full-page, reduced-motion captures. This exposes every section without a sticky element masking another section in a long screenshot.
- `scroll-390.webm` and `scroll-1440.webm`: real 22-second scroll sequences plus brief holds, with normal motion enabled. Reproduce with `scripts/site-record.cjs`.
- `browser.json`: all three public pages at four widths in both themes, JavaScript disabled; no horizontal overflow, resource failures, image/copy overlap, FAQ/schema mismatch or policy-body changes.
- `motion.json`: 24 native/fallback/reduced-motion cases, four widths × two themes × three modes; no horizontal overflow, correct sticky/reduced-motion states, fallback reveal, and equal phone scales. The checker also verifies equal rendered loan-device scale and correct intrinsic dimensions.
- `accessibility.json`: axe WCAG A/AA checks on all three public pages at four widths in both themes, zero violations.
- `html-validation.txt`: HTML validation passes.
- `performance.json`: three sequential Lighthouse 13.6.0 mobile runs, each **100 performance / 100 accessibility**, median **100 / 100**, **CLS 0** throughout. LCP is about 1.88 seconds. Landing image requests total **191,080 bytes (186.6 KiB)**, below 250 KiB; build-only frame assets, standalone source crops and the social preview are not landing-page requests.

An intermediate audit caught low contrast from fading the text in illustrative cards. The final version animates phones only; all HTML copy and illustration labels remain fully opaque. The three reported runs are after that correction. Raw Lighthouse output stays in `/tmp` to avoid repeating #163's report bloat.

## Reproduce

Pillow 13.0.0, Playwright, Chrome, Lighthouse 13.6.0, axe-core and html-validate 11.21.0. No app code or `.github` files changed.

```sh
python3 scripts/site-images.py --ref 07e7eff3c7545a79bc20579ebdcb17745d966918
python3 scripts/site-phones.py
python3 -m http.server 8774 --directory site
NODE_PATH=/tmp/settlo-site-tools/node_modules SITE_CHECK_URL=http://127.0.0.1:8774/ SITE_CHECK_OUTPUT=/tmp/164-check node scripts/site-check.cjs
NODE_PATH=/tmp/settlo-site-tools/node_modules SITE_CHECK_URL=http://127.0.0.1:8774/ SITE_CHECK_OUTPUT=/tmp/164-video node scripts/site-record.cjs
/tmp/settlo-site-tools/node_modules/.bin/html-validate --preset standard site/index.html site/privacy/index.html site/support/index.html
# Run sequentially three times, with browser evidence work finished first:
CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' /tmp/settlo-site-tools/node_modules/.bin/lighthouse http://127.0.0.1:8774/ --chrome-flags='--headless=new --no-first-run' --only-categories=performance,accessibility --output=json --output-path=/tmp/164-lighthouse.json --quiet
```

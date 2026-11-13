# #244 evidence: image budget without an allowlist

- **Studio frame:** `site/images/device/studio-frame.png` (744,627 B) and its prompt moved to `scripts/phones/`, outside the published tree. Nothing composites it; `site-phones.py` records its path and SHA-256 under `device.historical_frame` in `sources.json`.
- **Phone PNG fallbacks:** `site-phones.py` rounds each fallback's RGB to the nearest multiple of 3 (alpha untouched) before the optimised PNG encode, so no channel moves more than 1/255. Palette quantising was tried first and rejected: 256-colour octree gave a mean error of 2.1–2.6/255 (max 30), and Pillow here has no libimagequant. Two runs give byte-identical PNGs; the AVIFs are unchanged. The rule applies to all five fallbacks, so the three under budget also gain headroom.

| Fallback | Before | After | Mean diff /255 | Max diff /255 |
| --- | ---: | ---: | ---: | ---: |
| settle_pay-phone.png | 162,459 | 120,059 | 0.44 | 1 |
| spaces_balances-phone.png | 181,381 | 136,393 | 0.42 | 1 |
| home_main-phone.png | 141,583 | 106,571 | 0.45 | 1 |
| loans_detail-phone.png | 143,101 | 106,432 | 0.46 | 1 |
| confirm_repayment-phone.png | 125,005 | 97,494 | 0.54 | 1 |

- `visual-diff.py` regenerates `diff.json`, the ×128 difference maps and the 2x nearest-neighbour before/after crops (text, a soft card shadow, the blurred tab bar) against 4ed95b1. No banding is visible in the crops, including when they are contrast-stretched 6×.
- `site-build-check.py` has no allowlist now: 47 site images within budget.
- `lighthouse-summary.json`: landing, default mobile. The first run scored 0.81, with TBT 690 ms on a host at load average ~20. Three reruns scored 0.98, 0.99 and 0.99, with LCP 2.25–2.33 s, CLS 0 and TBT ≤ 1 ms. Accessibility, best practices and SEO were 1 in every run.

## Checks (all pass, served by `scripts/site-serve.py --port 8794`)

```sh
python3 scripts/site-phones.py              # twice; byte-identical outputs
python3 scripts/site-build.py --check
python3 scripts/site-build-check.py
node scripts/site-check.cjs
node scripts/site-images-ready-check.cjs
node scripts/site-menu-check.cjs
node scripts/site-accessibility-check.cjs
```

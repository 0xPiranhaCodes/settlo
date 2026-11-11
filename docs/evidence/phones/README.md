# Phone frame correction — issue #176

The original measured generated-frame opening was 746×1636 (aspect 0.4560), while the pasted screenshot was 390×844 (0.4621); scaling by width left spare rows. Its independent 24px screen mask also disagreed with the generated inner rim. Finally, the zero-inset 390px Confirm export itself ended halfway through the secondary button.

The pipeline now renders the real widgets at 430×932 with 54px top and 34px bottom safe-area insets. A deterministic concentric frame has an exact 430×932 display, 52px display radius, 8px bezel and illustrative system chrome. No app text or controls are reconstructed. The Confirm export asserts the complete secondary button lies above the bottom safe area. Every phone export checks button and tappable-widget rectangles against the glass tab bar (excluding the navigation controls themselves). The Loans phone uses a pending-repayment-only fixture and asserts that its complete card ends at least 16px above the bar; Home scrolls 24px to keep its pending-repayment action clear too. Existing 390px detail sources and their crops remain unchanged.

## Evidence

- `before/corners-and-bottom-2x.png` and `after/corners-and-bottom-2x.png`: all four corners and bottom strips of every phone at exactly 2x nearest-neighbour zoom. The baseline AVIFs are kept beside the before sheet.
- `after/landing-{360,390,768,1440}-{light,dark}.png`: full Chromium page captures from `scripts/site-check.cjs`.
- `after/webkit-*-full.png`: full WebKit pages at the same widths, including 360×664 and 390×664 mobile Safari-size content viewports. `*-confirm.png` captures the visible viewport at the Confirm phone. These are WebKit emulations, not physical-iPhone captures.
- The owner screenshot, all five individual rebuilt phone images, the 2x sheets, and full mobile/desktop light/dark captures were visually inspected. The frame is even; Confirm and payment buttons are complete; sheet backgrounds continue through the bottom display corners. Loans now ends with a complete pending-repayment card and an empty gap above navigation, with no older repayment text underneath. Other scroll content behind floating navigation is the real widget rendering.

## Checks

- `scripts/site-build-images.sh`: all 10 Flutter exports passed, including the control-overlap, repayment-card gap and Confirm visibility assertions. No local dependency overrides were needed for this refresh. `flutter analyze test/marketing_export.dart` passed.
- Regression proof: before the fixture fix, the new assertion failed on Loans with a control spanning y=808–852 intersecting the tab bar at y=842–910. It also caught Home’s tappable repayment row at y=796–852 before the 24px scroll adjustment.
- `scripts/site-check.cjs`: passed all viewport, theme, motion, density, geometry, policy and resource checks; see `after/browser.json`, `after/density.json`, `after/motion.json`.
- WebKit captures and overflow assertions: passed for all eight width/theme combinations.
- Lighthouse mobile, three sequential runs: **99 / 99 / 99**, median **99**, CLS **0 / 0 / 0**. Full reports and summary are in `after/`.
- Image alternatives including all phones, details and mark: **136,650 / 236,994 / 331,804 bytes** at 1x/2x/3x; maximum **324.03 KiB**, under the unchanged 350 KiB budget.

Reproduce with Pillow 13 and the repository's Flutter version, then serve `site/` locally:

```sh
scripts/site-build-images.sh
SITE_CHECK_URL=http://127.0.0.1:8877/ SITE_CHECK_OUTPUT=docs/evidence/phones/after node scripts/site-check.cjs
SITE_CHECK_URL=http://127.0.0.1:8877/ node scripts/site-phone-evidence.cjs
python3 scripts/site-phone-crops.py site/images docs/evidence/phones/after/corners-and-bottom-2x.png
```

Playwright plus its WebKit runtime are required. Lighthouse used its standard mobile simulated throttling, headless Chrome, and no budget changes. Local measurements are evidence for the image/site change; hosted CI must independently pass the pushed PR head.

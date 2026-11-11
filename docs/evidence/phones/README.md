# Phone frame correction — issue #176

The original measured generated-frame opening was 746×1636 (aspect 0.4560), while the pasted screenshot was 390×844 (0.4621); scaling by width left spare rows. Its independent 24px screen mask also disagreed with the generated inner rim. Finally, the zero-inset 390px Confirm export itself ended halfway through the secondary button.

The pipeline now renders the real widgets at 430×932 with 54px top and 34px bottom safe-area insets. A deterministic concentric frame has an exact 430×932 display, 52px display radius, 8px bezel and illustrative system chrome. No app text or controls are reconstructed. The Confirm export asserts the complete secondary button lies above the bottom safe area. Every phone export with glass navigation checks Text, RichText, Icon, progress-indicator, button and tappable-widget rectangles against the full-width region from the bar top to the display bottom (excluding navigation descendants). This includes the strip below the bar and does not rely on hit testing. The Loans phone uses a pending-repayment-only fixture and asserts that its complete card ends at least 16px above the bar; Home uses an empty activity-feed fixture and scrolls 72px: its complete Loans card, including the progress indicator that previously appeared as a light sliver, ends 23px above navigation, with a minimum 16px gap assertion. The stronger check also found clipped category text in Spaces; that phone scrolls 300px to show its complete category card and a clean bottom gap. Existing 390px detail sources and their crops remain unchanged.

## Evidence

- `before/corners-and-bottom-2x.png` and `after/corners-and-bottom-2x.png`: all four corners and bottom strips of every phone at exactly 2x nearest-neighbour zoom. The baseline AVIFs are kept beside the before sheet.
- `after/landing-{360,390,768,1440}-{light,dark}.png`: full Chromium page captures from `scripts/site-check.cjs`.
- `after/webkit-*-full.png`: full WebKit pages at the same widths, including 360×664 and 390×664 mobile Safari-size content viewports. `*-confirm.png` captures the visible viewport at the Confirm phone. These are WebKit emulations, not physical-iPhone captures.
- The owner screenshot, all five individual rebuilt phone images, the 2x sheets, and full mobile/desktop light/dark captures were visually inspected. The frame is even; Confirm and payment buttons are complete; sheet backgrounds continue through the bottom display corners. Loans now ends with a complete pending-repayment card and an empty gap above navigation, with no older repayment text underneath. Home likewise ends with the complete Loans card and empty space around navigation, with no activity heading or trailing icon at the display bottom. Spaces shows the lower fairness row, settlements and complete category card at a natural scroll position.

## Checks

- `scripts/site-build-images.sh`: all 10 Flutter exports passed, including the content-overlap, Home/repayment-card gap and Confirm visibility assertions. No local dependency overrides were needed for this refresh. `flutter analyze test/marketing_export.dart test/home_golden_test.dart` passed.
- Earlier regression proof: before the fixture fix, the new assertion failed on Loans with a control spanning y=808–852 intersecting the tab bar at y=842–910. It also caught Home’s tappable repayment row at y=796–852 before the 24px scroll adjustment.
- New regression proof: restore Home's populated activity fixture and 24px scroll, bypass only its card-gap check, and the new assertion fails on `LinearProgressIndicator Rect.fromLTRB(41, 842, 389, 846)`. Removing only the progress-indicator predicate for a second probe makes it fail on `Text Rect.fromLTRB(41, 926, 345, 942)`, intersecting the reserved y=842–932 region. Both mutations were reverted before the final 10/10 rebuild.
- `scripts/site-check.cjs`: passed all viewport, theme, motion, density, geometry, policy and resource checks; see `after/browser.json`, `after/density.json`, `after/motion.json`.
- WebKit captures and overflow assertions: passed for all eight width/theme combinations.
- Lighthouse mobile, three sequential runs: **97 / 99 / 99**, median **99**, CLS **0 / 0 / 0**. Full reports and summary are in `after/`.
- Image alternatives including all phones, details and mark: **135,605 / 235,306 / 332,100 bytes** at 1x/2x/3x; maximum **324.32 KiB**, under the unchanged 350 KiB budget.

Reproduce with Pillow 13 and the repository's Flutter version, then serve `site/` locally:

```sh
scripts/site-build-images.sh
SITE_CHECK_URL=http://127.0.0.1:8877/ SITE_CHECK_OUTPUT=docs/evidence/phones/after node scripts/site-check.cjs
SITE_CHECK_URL=http://127.0.0.1:8877/ node scripts/site-phone-evidence.cjs
python3 scripts/site-phone-crops.py site/images docs/evidence/phones/after/corners-and-bottom-2x.png
```

Playwright plus its WebKit runtime are required. Lighthouse used its standard mobile simulated throttling, headless Chrome, and no budget changes. Local measurements are evidence for the image/site change; hosted CI must independently pass the pushed PR head.

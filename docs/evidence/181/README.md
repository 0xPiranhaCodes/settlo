# Composed phones — issue #181

Same real phone exports, no new images. The hero is a group: Home in front and centre, with Spaces and Loans behind at 88% scale, lowered and offset to each side. They keep their exported ±3° tilt. Depth comes from overlap, a two-layer shadow on the front phone and a soft contact shadow under the group. In the loan section, Confirm overlaps the Loan phone in front and lower, at the same physical scale. At 600px and below, the hero shows Home alone: the back phones are lazy and `display: none`, so they are never fetched. The loan pair keeps a tidy overlap. On scroll, the back hero phones drift slightly outward and down (`animation-timeline: scroll()`). There is no motion under `prefers-reduced-motion`.

`scripts/site-check.cjs` now lets phones overlap only inside their own group (`.hero-screen`, `.loan-screens`). It also asserts that the hero CTA is above the fold at 390×844. The Home alt text now matches the current export.

## Evidence

- `landing-{360,390,768,1440}-{light,dark}.png`: full Chromium pages from `scripts/site-check.cjs`.
- `webkit-*-full.png`, `webkit-*-confirm.png`: WebKit pages from `scripts/site-phone-evidence.cjs`. These are emulations, not physical-iPhone captures.
- `scroll-1440-light.webm`: about 9s. It shows the hero settle, then the loan pair entering.

## Checks

- `scripts/site-check.cjs`: passed (viewports, themes, motion/fallback/reduced, density, geometry, budget).
- WebKit overflow and captures: passed at all eight width/theme combinations.
- Lighthouse mobile ×3: **99 / 99 / 99**, CLS **0 / 0 / 0** (`lighthouse-*.json`).
- Images: unchanged, max **325,903 bytes** across density sets (budget 350 KiB).

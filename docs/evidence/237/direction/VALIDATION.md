# Direction checkpoint verification

Scope: new hero and one pinned Goa balance story. The lower landing-page sections remain the existing design pending owner approval. The mobile header now uses a native popover sheet and the mobile hero uses a centred 78vw (maximum 340px) phone with its caption below. Desktop header styling, footer, feature flags, sitemap, policy wording and `.github` are unchanged.

## Browser evidence

- `scroll-{390,1440}-{light,dark}.webm`: Playwright `recordVideo`, 18-second continuous scroll followed by a resting final state; refreshed 390px recordings first open and close the menu.
- `hero-*`, `settled-*`: viewport screenshots; `reduced-*`: complete static walkthrough; `before-*`: original main hero rendered against its original shared stylesheet.
- `browser-checks.json`: separate native state checks, reduced-motion visibility and positioning, 360px overflow, external-request inventory.
- Forced unsupported-timeline mode independently produced `[1,0,0]`, `[0,1,0]`, `[0,0,1]` panel opacities. These checks also live in `site-check.cjs`, alongside capture geometry, density selection, mobile phone width and stacked-caption geometry, legal pages and structured data checks.
- `axe.json`: no WCAG A/AA violations in either new section, light/dark. Axe leaves some image/background contrast checks incomplete; `contrast.json` independently verifies the text palette at AA. Real app captures are unchanged.

All three build/browser/image-readiness commands passed. The image readiness run exercised 15 fresh no-JS density contexts and rejected the deliberate corrupt-image negative control. `site-check-*.json` contains the full page matrix. Initial runs against Python’s concurrent development server encountered socket failures; the completed checks used a local Node static server.

## Performance

`lighthouse-summary.json` records Lighthouse's default simulated mobile run on local Chrome. This is lab evidence, not a physical mid-range Android or deployed-field measurement. The full Lighthouse report is retained locally in `/tmp/237-lighthouse-final.json`.

## Reproduce

Serve `site/`, then set `SITE_CHECK_URL` (including trailing slash) and run:

```sh
python3 scripts/site-build-check.py
node scripts/site-check.cjs
node scripts/site-menu-check.cjs
node scripts/site-images-ready-check.cjs
node scripts/site-direction-evidence.cjs
```

Playwright and Chrome are required. The evidence recorder defaults to port 8237; use `SITE_CHECK_OUTPUT` for an alternate output folder.

Native view timelines, sticky scenes, container queries, `:has()`, fluid type and a registered integer counter are used. No library or scroll handler is shipped. There is no interactive state toggle requiring View Transitions in this checkpoint. Figtree's existing self-hosted static fonts are retained; no unsupported variable optical axis is assumed. No reference assets were copied.

## Mobile-header revision

- `menu-open-390-{light,dark}.png`: full-width sheet with four navigation links, space for the future Blog link, and the beta CTA at the bottom.
- `menu.json`: 12 mobile contexts (360/390/720, light/dark, motion/reduced motion) passed; desktop menu-button visibility checked at 721 and 1440. Covers 56px header height, focus containment, Escape and link dismissal, expanded state, 44px targets, sticky scrolled surface, reduced motion, and horizontal overflow.
- `menu-axe.json`: no WCAG A/AA violations with the sheet open in either theme. The existing text palette is retained; the sheet uses an opaque navigation background.
- Lighthouse mobile: performance 0.98, accessibility 1.00, CLS 0, 1,498 combined gzip bytes for the two shipped JS files. Full local report: `/tmp/237-menu-lighthouse.json`.
- Build flag/schema checks, the complete site browser/motion/density matrix, and 15 no-JS image-readiness contexts passed; the corrupt-image control was rejected.
- Both refreshed mobile videos were decoded and menu-open/menu-closed frames inspected, alongside the hero and menu screenshots. Desktop evidence remains from the unchanged desktop design.

The larger phone intentionally moves the inline hero CTA below the first viewport; the same CTA is immediately available from Menu. The old above-fold CTA assertion is replaced by a 78vw phone-width and caption-below-phone check. Header opacity uses `scroll()`; an IntersectionObserver sentinel supplies the scrolled surface in reduced motion and browsers without scroll timelines. Menu entry animates only opacity and transform and is instant under reduced motion.

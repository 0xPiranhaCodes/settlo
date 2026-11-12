# Direction checkpoint verification

Scope: new hero and one pinned Goa balance story. The lower landing-page sections remain the existing design pending owner approval. Nav/footer markup, feature flags, sitemap, policy wording and `.github` are unchanged.

## Browser evidence

- `scroll-{390,1440}-{light,dark}.webm`: Playwright `recordVideo`, 18-second continuous scroll followed by a resting final state.
- `hero-*`, `settled-*`: viewport screenshots; `reduced-*`: complete static walkthrough; `before-*`: original main hero rendered against its original shared stylesheet.
- `browser-checks.json`: separate native state checks, reduced-motion visibility and positioning, 360px overflow, external-request inventory.
- Forced unsupported-timeline mode independently produced `[1,0,0]`, `[0,1,0]`, `[0,0,1]` panel opacities. These checks also live in `site-check.cjs`, alongside capture geometry, density selection, primary CTA visibility, legal pages and structured data checks.
- `axe.json`: no WCAG A/AA violations in either new section, light/dark. Axe leaves some image/background contrast checks incomplete; `contrast.json` independently verifies the text palette at AA. Real app captures are unchanged.

All three build/browser/image-readiness commands passed. The image readiness run exercised 15 fresh no-JS density contexts and rejected the deliberate corrupt-image negative control. `site-check-*.json` contains the full page matrix. Initial runs against Python’s concurrent development server encountered socket failures; the completed checks used a local Node static server.

## Performance

`lighthouse-summary.json` records Lighthouse's default simulated mobile run on local Chrome. This is lab evidence, not a physical mid-range Android or deployed-field measurement. The full Lighthouse report is retained locally in `/tmp/237-lighthouse-final.json`.

## Reproduce

Serve `site/`, then set `SITE_CHECK_URL` (including trailing slash) and run:

```sh
python3 scripts/site-build-check.py
node scripts/site-check.cjs
node scripts/site-images-ready-check.cjs
node scripts/site-direction-evidence.cjs
```

Playwright and Chrome are required. The evidence recorder defaults to port 8237; use `SITE_CHECK_OUTPUT` for an alternate output folder.

Native view timelines, sticky scenes, container queries, `:has()`, fluid type and a registered integer counter are used. No library or scroll handler is shipped. There is no interactive state toggle requiring View Transitions in this checkpoint. Figtree's existing self-hosted static fonts are retained; no unsupported variable optical axis is assumed. No reference assets were copied.

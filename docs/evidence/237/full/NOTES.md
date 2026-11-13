# Full landing page — #237

The owner-approved opening at `00e5694` continues into an editorial lower page. Feature explanations use ruled rows with real app details; the fictional conversation is a marginal note, not a chat-card UI. The comparison remains a semantic table. The notebook story steps down the mobile page, followed by Flat 402 and a keyboard-scrollable, scroll-snapped strip of the four shipped split methods. Reduced motion lays out all four methods without scrolling.

The loan record and confirmation captures sit beside the explanation at the same physical scale, without overlap. The free section makes ₹0 the focal point. Safety has a desktop sticky aside and five readable boundaries; reduced motion removes that pin. The FAQ remains native `details`, with intrinsic-size transitions only where supported. A full-width, quiet beta invitation closes the page.

Only the approved Goa scene has scroll-driven product motion. No extra scroll scene, animation library, generated product imagery, decorative glow or uniform card grid was added. The old landing CSS and unused reveal script were removed. Shared mobile chrome now also serves Privacy, Support, Terms and Delete account; their main content is unchanged. The feature flags and conditional content remain intact, and the build still generates FAQ structured data from the visible answers.

Blog PR #236 was still open during final integration. Explicit Blog slots remain in desktop navigation, mobile navigation and the footer; no dead Blog link is published.

## Evidence and checks

- `full-{390,1440}-{light,dark}.png`: full-page screenshots with native motion enabled. The tall Goa pin intentionally has scroll space; use the recordings to see its states.
- `scroll-{390,1440}-{light,dark}.webm`: 50-second continuous full-page scroll recordings, including desktop dark in addition to the requested minimum.
- `reduced-{390,1440}-{light,dark}.png`: complete static page, including all three Goa steps and four split methods.
- `splits-*` and `safety-*`: readable detail screenshots of the new sections.
- `browser.json`, `motion.json`, `density.json`: full site-check matrix, no-JS policy routes, no overflow at 360/390/768/1440, no third-party requests, real capture geometry/density and native/fallback/reduced narrative states.
- `menu.json`: menu behavior on the landing page and all four policy pages, both themes and motion preferences, including keyboard containment, Escape, links, header height, scrolled background and target sizes.
- `axe.json`: zero WCAG A/AA violations in 30 full-page/open-menu contexts, including all FAQ answers open and all four policy pages. Axe's incomplete image-related checks are recorded; they are not counted as passes.
- `contrast.json`: all text/background and action-label pairs exceed 4.5:1; the minimum is 5.97:1. Existing app capture artwork is unchanged.
- `lighthouse-summary.json`: local Chrome, default Lighthouse simulated mobile: performance **0.99**, accessibility **1.00**, best practices **1.00**, SEO **1.00**; LCP **2.254s**, CLS **0**, TBT **10ms**. Shipped JS is **1,090 bytes gzip**.

These are local browser/lab results, not a physical mid-range Android measurement or deployed field data. Full Lighthouse output is retained locally at `/tmp/237-full-lighthouse.json`. Hosted CI status must be assessed separately on the pushed head.

## Reproduce

Serve `site/` locally, set `SITE_CHECK_URL` to that URL with a trailing slash, and provide Playwright, axe-core and Chrome. Run:

```sh
python3 scripts/site-build-check.py
node scripts/site-check.cjs
node scripts/site-images-ready-check.cjs
node scripts/site-menu-check.cjs
node scripts/site-accessibility-check.cjs
node scripts/site-full-evidence.cjs
```

The image readiness check passes 15 fresh no-JS density contexts and rejects a deliberately corrupt image. The browser suite also checks the Privacy/Support main content against the original policy baseline. No `.github` files changed.

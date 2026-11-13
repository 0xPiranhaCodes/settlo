# Full landing page — #237

The owner-approved opening at `00e5694` continues into an editorial lower page. Feature explanations use ruled rows with real app details; the fictional conversation is a marginal note, not a chat-card UI. The comparison remains a semantic table. The notebook story is two connected paragraphs, followed by Flat 402 and a keyboard-scrollable, scroll-snapped strip of the four shipped split methods. Reduced motion lays out all four methods without scrolling.

The loan record and confirmation captures sit beside the explanation at the same physical scale, without overlap. The free section makes ₹0 the focal point. Safety has a desktop sticky aside and five readable boundaries; reduced motion removes that pin. The FAQ remains native `details`, with intrinsic-size transitions only where supported. A full-width, quiet beta invitation closes the page.

Only the approved Goa scene has scroll-driven product motion. No extra scroll scene, animation library, generated product imagery, decorative glow or uniform card grid was added. The old landing CSS and unused reveal script were removed. Shared mobile chrome now also serves the blog index and all articles, Privacy, Support, Terms and Delete account; their main content is unchanged. The feature flags and conditional content remain intact, and the build still generates FAQ structured data from the visible answers.

Blog PR #236 was still open during final integration. Explicit Blog slots remain in desktop navigation, mobile navigation and the footer; no dead Blog link is published.

## Evidence and checks

- `full-{390,1440}-{light,dark}.png`: full-page screenshots with native motion enabled. The tall Goa pin intentionally has scroll space; use the recordings to see its states.
- `scroll-{390,1440}-{light,dark}.webm`: 50-second continuous full-page scroll recordings, including desktop dark in addition to the requested minimum.
- `reduced-{390,1440}-{light,dark}.png`: complete static page, including all three Goa steps and four split methods.
- `splits-*` and `safety-*`: readable detail screenshots of the new sections.
- `browser.json`, `motion.json`, `density.json`: 72 page/theme/width contexts; full site-check matrix, no-JS policy routes, no overflow at 360/390/768/1440, no third-party requests, real capture geometry/density and native/fallback/reduced narrative states.
- `menu.json`: 108 mobile contexts plus desktop visibility checks; menu behavior on the landing page, all four policy pages and all four blog routes, both themes and motion preferences, including keyboard containment, Escape, links, header height, scrolled background and target sizes.
- `axe.json`: zero WCAG A/AA violations in 54 full-page/open-menu contexts, including all FAQ answers open, all four policy pages, the blog index and all three articles. Axe's incomplete image-related checks are recorded; they are not counted as passes.
- `contrast.json`: all text/background and action-label pairs exceed 4.5:1; the minimum is 5.97:1. Existing app capture artwork is unchanged.
- `lighthouse-summary.json`: retained pre-review measurement at `8f4d085`, not rerun for this revision; local Chrome, default Lighthouse simulated mobile: performance **0.99**, accessibility **1.00**, best practices **1.00**, SEO **1.00**; LCP **2.254s**, CLS **0**, TBT **10ms**. The recorded JS size was **1,090 bytes gzip**.

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

## Review correction after the blog rebase

Rebased onto `39a45e1` (merged blog #236). Every page now links to Blog in its desktop header, mobile menu and footer, including Support; blog chrome comes from the landing page generator and uses the same menu behavior. Browser checks cover all nine pages and the build check still rejects changed blog sources, outputs and covers.

The Goa capture is identified as the Spaces list: ₹3,650 owed to the space, with no claimed recipient. Payment and confirmation are plain explanations of subsequent steps, explicitly not screens shown here. The invented Kabir payment and zero-balance end state are gone, along with the arrow on the non-link payment instruction.

The four feature rows have no eyebrow labels; the two additional details are an inline-emphasis list, and the notebook story is connected prose. Direction CSS has one mobile layout block at 760px, a 720px header-offset variable, no appended patch blocks, no always-true `:has`, and no `!important`. Stale link and hero selectors were removed; the overlap negative control still rejects ungrouped phones.

The large real hero capture intentionally puts the in-content beta CTA below the first mobile viewport. Beta access remains available from the mobile menu. The pinned mobile Spaces capture remains an overview at small size, with its balance and screen limitations stated in adjacent text.

# Website v3 full build — #249

This builds on the approved direction (hero, sticky story, trust centre, capsule header at 5d4e134) and carries the same grid, type scale and motion tokens to every page.

## Landing page
- **Why SabkiJeb** (`#why`) replaces the old features, "old way", flat, loan, free and comparison sections. It has two feature cards: shared spaces, with the four split methods, and personal loans, with the real Activity capture. Four fact cards follow (UPI, reminders, offline, statements), then a ₹0 band (Free, folded in) and the comparison table. Every sentence comes from the previous page.
- **Feature gating is unchanged.** All 13 flags in `site-features.json` still gate the same copy. Gated "more" cards render as Why cards. `future-grid` keeps its own empty-block removal, and the language and feed sections share the same rules. `site-build-check.py` renders every flag on its own and all of them together.
- **FAQ** sits under Trust. Its head is pinned beside ruled questions, and the plus icon rotates to a close icon. The questions and answers and the FAQ schema are unchanged.
- **Final CTA**: the page's single forest band, with a light button, a marigold eyebrow and the beta QR. The site header still reaches 4.5:1 over it (`site-direction-evidence` headerContrast passes).
- **Footer**, on every page: brand, then Product / Legal / Contact columns and a hairline legal row. The policy pages carry the same footer; their `<main>` sections are untouched, and `site-check` still diffs privacy and support against the baseline.
- **Removed CSS**: every rule for the deleted sections, the illustration-spot rules, `blog.css` (merged into `site.css`, saving one request on blog pages) and the duplicated tokens. A scan of the CSS class selectors against every page, the template and the JS finds no unused classes.

## Other pages
The blog index, posts and policy pages now use the shared tokens, which moved from `direction.css` to `site.css`.
- **Blog index**: the display size for the index H1, h2 for post H1s and h3 for card titles.
- **Policies**: a 720px reading column, with ruled h2 sections and the shadowed "In short" card.
- **Blog cards**: the whole card is clickable, lifts on hover, and its arrow nudges.

## LCP fix
The hero's LCP paint lands 40–150 ms after the `load` event, so loading the story captures on `load` still put them in the hero's LCP window (measured: no improvement).

The fix has two parts:
- The story `<img>`s are `display:none` under `(scripting: enabled)` until `html.story-ready`.
- `direction.js` sets that class when a `largest-contentful-paint` entry for the hero product image is reported. It falls back to 3 s, or to `load` where the API is missing.

Lazy images that aren't rendered are never requested. The capture frame (`.phone`) now holds the size and aspect ratio, so revealing the images can't shift layout (CLS 0). Without JS the images show normally.

## Results
- **Lighthouse 13.6, simulated mobile, home page, 3 runs**: performance 0.98, LCP 2.33–2.36 s (was 2.56–2.65 s), CLS 0, TBT 0–66 ms. Accessibility, best practices and SEO are 1.00. See `lighthouse-summary.json`.
- **Blog, a post and privacy**: performance 1.00, CLS ≤ 0.0001.
- **JS**: `direction.js` is 2.1 KB gzip, the only script.
- **Third-party requests**: none, per Lighthouse and `site-check`.
- **AA**: axe reports no WCAG 2.1 AA violations across 27 page and menu contexts (`axe.json`).
- **No horizontal scroll** at 360, 390, 768 or 1440 (`site-check`, `browser-checks.json`).
- **Reduced motion**: a static, complete page, with every story panel visible and the pin static (`reduced-*.png`).
- **Checks**: `site-build-check.py`, including the image budgets, passes. So do `site-check`, `site-images-ready-check`, `site-menu-check`, `site-accessibility-check`, `site-phone-evidence`, `site-record`, `site-direction-evidence` and `site-full-evidence`.

Lab numbers come from a dev machine, not field data.

## Files
- **Recordings**: `scroll-390-light.webm` and `scroll-1440-light.webm`, full-page scrolls with motion on.
- **Full-page screenshots**: `full-*.png` (motion on, taken after the scroll pass) and `reduced-*.png`.
- **Section screenshots**: `why-*`, `trust-*`, `faq-*` and `closing-*`.

# Issue #153 verification

Local pre-deployment evidence, 11 November 2026, served with `python3 -m http.server 8765 --directory site`.

- **Screenshots:** full page, 1× DPR, fresh headless Chrome contexts. `before-*` is `main` at `cda882a`; `after-*` is this branch. Widths 390 and 1440, `prefers-color-scheme` light and dark. The site is near-black in both schemes by design (docs/brand.md), so the light and dark captures are pixel-identical; both are kept to show that.
- **Lighthouse 13.6.0 mobile** (default simulated throttling): Performance 99, Accessibility 100, Best Practices 96, SEO 100. CLS 0, LCP 2.0 s. [HTML](lighthouse-mobile.report.html), [JSON](lighthouse-mobile.report.json). The Best Practices deduction is `image-size-responsive`: the app goldens are rendered at 1× (390×844), so a 3× phone gets fewer pixels than it could use. Higher-density screens need goldens rendered at a higher device pixel ratio. Cache and document-latency hints come from the local Python server, not the Pages host.
- **scripts/site-check.cjs:** passes. 360 and 1440, JavaScript disabled, reduced motion: no overflow, no external requests, FAQ matches JSON-LD, canonical and social URLs at `https://settlo.hellojosh.studio/`, policy `<main>` byte-identical to `0f61006`. [Results](browser.json).
- **html-validate 11.21.0** standard preset: all three pages, 0 errors.

Reproduce with the commands in [../140/README.md](../140/README.md), plus the screenshot capture used here (Playwright `colorScheme` light/dark at 390 and 1440).

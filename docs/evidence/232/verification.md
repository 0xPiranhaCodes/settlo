# Issue 232 verification

Terms of Use page at `site/terms/` (draft, needs owner/legal approval).

Local verification on 2026-11-12, served by `scripts/site-serve.py --port 8794`:
- `scripts/site-check.cjs`: PASS. `terms/` is now in its page list, so it is covered at
  360, 390, 768 and 1440 px in light and dark: canonical URL, no horizontal overflow,
  no external requests, no failed requests, JavaScript disabled.
- `scripts/site-images-ready-check.cjs`: PASS.
- Lighthouse mobile on `/terms/`: performance, accessibility, best practices and SEO
  all 1.00 (`lighthouse-mobile.json`).
- `terms-360-light.png` and `terms-360-dark.png` are the checker's full-page captures,
  inspected visually.

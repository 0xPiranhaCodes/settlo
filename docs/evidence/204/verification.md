# Issue 204 verification

Website rebrand to SabkiJeb at https://sabkijeb.app.

- `scripts/site-check.cjs` (served by `scripts/site-serve.py --port 8794`): passed at
  360, 390, 768 and 1440 px, light and dark, landing/privacy/support, with
  JavaScript disabled, motion, density and the 350 KiB image budget
  (max 154,457 bytes). The policy-body guard now allows only the name and
  support-address swap. Results: `site-check-browser.json`, `site-check-motion.json`.
- `scripts/site-images-ready-check.cjs`: PASS (15 no-JS density runs; corrupt image rejected).
- Lighthouse 12.3.0, mobile, local server: performance 0.99, accessibility 1,
  best practices 1, SEO 1 (`lighthouse-mobile.json`).
- Structured data: `structured-data.json` (SoftwareApplication + FAQPage, URL
  https://sabkijeb.app/, email support@sabkijeb.app; FAQ matches visible copy per site-check).
- Palette contrast (WCAG AA): jade #01672D on #FBF8EF 6.64:1, secondary #50645A
  5.97:1, ivory on jade 6.23:1; marigold #FEBD11 on #000000 12.5:1, forest label
  on marigold 7.88:1; forest band text #FEF0CE 11.71:1, #A9BCB0 6.63:1, marigold 7.88:1.
- Screenshots: `landing-1440-{light,dark}.png` (desktop), `landing-390-{light,dark}.png`
  (mobile), `privacy-360-*.png`, `support-360-*.png`.

Phone images and close-ups are neutral, text-free wireframes in the #202 dark
palette (`scripts/site-phones.py --placeholders`): the previous captures showed
the gold UI and the Settlo name. Follow-up: rebuild with
`scripts/site-build-images.sh` once #202 and #203 land in the app, and restore
descriptive alt text.

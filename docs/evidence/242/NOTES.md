# Illustration set, social cards and What's new dating — #242 (closes #239)

The illustration language is written down in `docs/brand.md` › Illustration: cut paper on a table, flat-lay or elevation only, no people (their things stand in), one 6-unit ink line on paper only, one hard 8/10 shadow, one grain, marigold once per piece on the money or the moment, and per-file `prefers-color-scheme` styles for dark. Every piece is hand-written SVG of about 1 KB gzipped (limit 15 KB).

- **Blog covers:** the Goa bill cut into three shares with one paid (guide), the shirt pocket (*jeb*) holding the record (rebrand) and the khata with today's entry highlighted (What's new).
- **Landing spots (2):** a blank price tag snipped off, in Free, and the chaiwala's carrier with the tab clipped on, under the FAQ heading. Both are decorative (`alt=""`), lazy, `decoding="async"`, with width and height. A third spot for the closing CTA was drawn (an envelope) and cut: the beta QR already does that job, so the envelope is used only on the Support card.
- **Social cards (9):** 1200×630 palette PNGs (17–29 KB) for landing, blog index, each post, Privacy, Support, Terms and Delete account, rendered by `node scripts/site-cards.cjs` from the SVG art and self-hosted Figtree. Every page has `og:image` (with width, height and alt), `twitter:card=summary_large_image`, `twitter:image` and its alt. The Article JSON-LD publisher now has its url, and its image is the post's PNG card. The Pillow social card (`social.png`) is gone; the landing page and its SoftwareApplication schema use `cards/home.png`.
- **Drift guard:** `scripts/cards/manifest.json` records hashes for every card input and output; `site-build.py --check` rejects a changed cover, spot, post, font, mark or card. `site-build-check.py` mutates a cover, a spot and a card PNG in its fixture to prove each is rejected.
- **Card weight:** `site-cards.cjs` now replaces each piece's grain with its mean tone inside the cards only (the `feTurbulence` becomes a 50% `feFlood` through the same tint and clip; the SVG files and the site keep the real grain), then palette-quantises every card with Pillow: 128 colours, median cut, no dither, `optimize`. Two runs give byte-identical PNGs. The settings live in the script, which the manifest hashes, so CI needs neither Playwright nor Pillow to catch drift. Mean pixel difference from the approved cards is 0.2/255 at half size. `site-build-check.py` now fails any card over 100,000 bytes and any other published image over 150,000 bytes; three older images (`settle_pay-phone.png`, `spaces_balances-phone.png`, `device/studio-frame.png`) are allowlisted until #244.

  | Card | Before (bytes) | After (bytes) |
  | --- | ---: | ---: |
  | `split-bills-with-friends.png` | 425,362 | 29,315 |
  | `whats-new.png` | 377,519 | 23,926 |
  | `settlo-is-now-sabkijeb.png` | 348,393 | 20,653 |
  | `blog.png` | 249,732 | 27,540 |
  | `support.png` | 152,032 | 17,703 |
  | `delete-account.png` | 150,252 | 19,172 |
  | `terms.png` | 143,028 | 19,790 |
  | `privacy.png` | 122,632 | 21,192 |
  | `home.png` | 109,542 | 19,213 |
  | **Total** | 2,078,492 | 198,504 |
- **What's new (#239):** the rebrand, palette and deletion information are now under 12 November (the announcement's date and the merge dates of #205/#206/#235); 13 November lists the redesigned website, this blog and the Terms.

## Evidence

- `contact-sheet.png`: every cover, spot and card-only illustration in light and dark, then all nine cards (the optimised PNGs). Cards are light-only by design; the card-only art has no dark variant because it is published only inside the PNG cards.
- `landing-{390,1440}-{light,dark}.png`: full landing page, reduced motion so every section is static and all lazy images are loaded.
- `post-390-{light,dark}.png`: the guide post at 390.
- `lighthouse-summary.json`: Lighthouse 13.6 default mobile on local Chromium. Landing 0.98 / 1 / 1 / 1, LCP 2.26 s, CLS 0; blog index, guide post and Privacy 0.99 / 1 / 1 / 1. The blog index CLS is 0.00004 (rounds to 0).

## Checks (all pass, served by `scripts/site-serve.py --port 8794`)

```sh
python3 scripts/site-build-check.py         # now also: card 100 KB and site image 150 KB budgets
node scripts/site-check.cjs                 # now also: every page's card tags, and each card resolves as a 1200x630 PNG
node scripts/site-images-ready-check.cjs
node scripts/site-menu-check.cjs
node scripts/site-accessibility-check.cjs   # 54 contexts, 0 WCAG A/AA violations
```

og:image URLs were confirmed locally (site-check fetches each card from the preview server). The public `https://sabkijeb.app/images/cards/*.png` URLs resolve only after this deploys. `.github` is unchanged; wiring site-build-check into CI (#239's third item) stays for a `.github`-scoped PR.

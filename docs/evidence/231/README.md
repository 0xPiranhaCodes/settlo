# Blog #231 evidence

The static blog has three launch posts, original palette-based SVG covers, shared
navigation/footer, individual metadata and Article JSON-LD. No new application or
build dependency, external request, or `.github` change was introduced.

## Publication boundary

Pages uploads `site/` wholesale and dereferences symlinks. Authoring Markdown is
therefore in `scripts/blog/posts/`, rather than the issue's proposed
`site/blog/posts/`, to keep sources out of the public artifact. This follows the
existing `scripts/site-features.json` boundary. The standard Python builder emits
only the four blog HTML pages and three covers under `site/blog/`, and regenerates
the sitemap. `docs/brand.md` describes authoring and the supported Markdown subset.

## Checks

- `python3 scripts/site-build-check.py`: PASS. Existing feature gates plus metadata,
  escaping, unsafe-link rejection, sitemap, mutated HTML/source/cover freshness,
  removed posts and unpublished Markdown.
- `NODE_PATH=/tmp/settlo-site-tools/node_modules SITE_CHECK_URL=http://127.0.0.1:8871/ SITE_CHECK_OUTPUT=/tmp/blog231-check node scripts/site-check.cjs`: PASS.
  All nine routes at 360, 390, 768 and 1440 in light/dark (72 page states); no
  horizontal overflow or third-party requests, internal blog links resolve,
  metadata agrees, shared navigation exists, and policy main byte guards pass.
  The 24 landing motion states and density checks also pass. See `browser.json`,
  `motion.json` and `density.json`.
- `NODE_PATH=/tmp/settlo-site-tools/node_modules SITE_CHECK_URL=http://127.0.0.1:8871/ node scripts/site-images-ready-check.cjs`: PASS,
  15 fresh no-JS density runs and corrupt-image rejection.
- axe-core WCAG 2 A/AA and 2.1 AA: zero violations on all four blog routes at
  360, 390 and 1440, both themes (24 audits). See `accessibility.json`.
- Mobile Lighthouse, default simulated mobile throttling, local production HTML:

| Page | Performance | Accessibility | Best practices | SEO |
| --- | --- | --- | --- | --- |
| `/blog/` | 99 | 100 | 100 | 100 |
| `/blog/split-bills-with-friends/` | 99 | 100 | 100 | 100 |

Full reports: `lighthouse-index.json`, `lighthouse-post.json`; compact scores:
`lighthouse-scores.json`. These are local browser checks, not hosted CI evidence.
The preview was started with `python3 scripts/site-serve.py --port 8871`.

## Visual evidence

All eight images below were opened and inspected. The guide is the longest post;
the announcement and product-update mobile renderings were also inspected.

| Page | 390 light | 390 dark | 1440 light | 1440 dark |
| --- | --- | --- | --- | --- |
| Index | [image](index-390-light.png) | [image](index-390-dark.png) | [image](index-1440-light.png) | [image](index-1440-dark.png) |
| Guide | [image](post-390-light.png) | [image](post-390-dark.png) | [image](post-1440-light.png) | [image](post-1440-dark.png) |

Full-page captures use a 390×844 or 1440×900 viewport. No generated app UI or
stock photos are used. The covers are abstract illustrations, not product screens.

## Copy review

Claims were checked against README, the published Terms/deletion/privacy pages,
and the expense split, Space settlement, UPI handoff, settlement confirmation and
loan detail implementations listed in `docs/brand.md`. Copy says iPhone TestFlight
beta; money moves in the user's UPI app and the recipient confirms separately.
It does not advertise settle links or other unshipped M7 features.

The PR body contains the full text and summaries of all three launch posts. Owner
copy approval and independent review remain required before merge.

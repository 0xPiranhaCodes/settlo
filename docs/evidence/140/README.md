# Issue #140 verification

Refreshed after rebasing onto merged main `0f610060b640b23f0a7a7b73f7783a140e70680b` (#142 and #143), 10 November 2026. Lighthouse capture: `2026-11-10T13:54:50.828Z`. This is pre-deployment evidence, not a claim about production Pages performance.

- **Mobile Lighthouse 13.6.0:** Performance 100, Accessibility 100, Best Practices 100, SEO 100. Default mobile simulated throttling: 150ms RTT, 1,638.4Kbps throughput, 4× CPU slowdown. [HTML report](lighthouse-mobile.report.html), [raw JSON](lighthouse-mobile.report.json).
- **Screenshots:** [360px landing](landing-360.png), [1440px landing](landing-1440.png), [360px privacy](privacy-360.png), [360px support](support-360.png). Inspected for wrapping, hierarchy and full screen imagery.
- **Browser:** fresh headless Chrome, Playwright ephemeral context, JavaScript disabled, reduced motion enabled. All three pages at 360 and 1440: no horizontal overflow and no third-party requests. FAQ opens without JavaScript; all six visible questions/answers match JSON-LD exactly. Privacy/support body bytes match base `0f610060b640b23f0a7a7b73f7783a140e70680b`. [Results](browser.json).
- **HTML:** html-validate 11.21.0 standard preset, all three documents, zero errors/warnings. [Result](html-validation.txt).
- **Structured data:** submitted the exact landing HTML to `https://validator.schema.org/validate`; two objects (SoftwareApplication and FAQPage), zero errors and zero warnings. [Full response](structured-data.json). No ratings, reviews, offers or invented price. Schema validity does not promise a search rich result.
- **Imagery:** [source manifest](../../../site/images/sources.json), merged main commit after PRs #142 and #143: `0f610060b640b23f0a7a7b73f7783a140e70680b`. Social image is 1200×630. [Regeneration instructions](../../brand.md#regenerating-imagery).

## Reproduce

Dependencies stay outside the repository. Chrome launchers create temporary profiles; never pass a personal user-data directory.

```sh
npm install --prefix /tmp/settlo-site-tools playwright@1.65.0 lighthouse@13.6.0 html-validate@11.21.0
python3 -m http.server 8765 --directory site
# In another terminal, from the repository root:
NODE_PATH=/tmp/settlo-site-tools/node_modules node scripts/site-check.cjs
/tmp/settlo-site-tools/node_modules/.bin/html-validate --preset standard site/index.html site/privacy/index.html site/support/index.html
CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' /tmp/settlo-site-tools/node_modules/.bin/lighthouse http://127.0.0.1:8765/ --chrome-flags='--headless=new --no-first-run' --only-categories=performance,accessibility,best-practices,seo --output=json --output=html --output-path=/tmp/settlo-lighthouse --quiet
curl -sS https://validator.schema.org/validate --data-urlencode html@site/index.html --data 'options='
```

Set `CHROME_PATH` for a different local Chrome installation. The verification script defaults to Chrome's macOS path. The policy-byte comparison pins merged main after #143, including its operator footers and updated deletion policy.

## Deployment boundary

The existing Pages workflow deploys `site/` on a push to main that changes the site; it dereferences the existing bundled-font symlinks. It was not dispatched, and this PR was not merged. Canonicals and social URLs use the Pages API's configured public URL, `https://0xpiranhacodes.github.io/settlo/`.

GitHub project Pages hosts this site's `robots.txt` at `/settlo/robots.txt`; crawlers only treat the origin-root `/robots.txt` as authoritative. This repository cannot alter that origin-root file. The site is crawlable by default and includes an absolute sitemap URL, but root robots ownership or a dedicated domain remains a hosting concern. Do not imply that the project-level file controls all crawling.

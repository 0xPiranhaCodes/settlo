// Additional WebKit evidence: iPhone Safari-size layout and visible viewport.
const { webkit } = require('playwright');
const { waitForImages } = require('./site-images-ready.cjs');
const fs = require('fs');
(async () => {
  const out = process.env.SITE_CHECK_OUTPUT || 'docs/evidence/phones/after';
  fs.mkdirSync(out, { recursive: true });
  const browser = await webkit.launch();
  for (const width of [360, 390, 768, 1440]) {
    for (const colorScheme of ['light']) {
      const height = width < 768 ? 664 : 900;
      const context = await browser.newContext({
        viewport: { width, height }, colorScheme,
        deviceScaleFactor: 1, isMobile: width < 768,
        reducedMotion: 'reduce', javaScriptEnabled: false,
      });
      const page = await context.newPage();
      await page.goto(process.env.SITE_CHECK_URL || 'http://127.0.0.1:8876/');
      await page.evaluate(() => document.fonts.ready);
      await waitForImages(page);
      if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth))
        throw Error(`WebKit overflow at ${width} ${colorScheme}`);
      await page.screenshot({ path: `${out}/webkit-${width}-${height}-${colorScheme}-full.png`, fullPage: true });
      if (width < 768) {
        await page.locator('img[src="images/confirm_repayment-phone.png"]').scrollIntoViewIfNeeded();
        await page.screenshot({ path: `${out}/webkit-${width}-${height}-${colorScheme}-confirm.png` });
      }
      await context.close();
    }
  }
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });

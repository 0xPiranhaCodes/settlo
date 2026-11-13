// WCAG A/AA on complete pages and open menus, including expanded FAQ answers.
const { chromium } = require('playwright');
const fs = require('node:fs');
const url = process.env.SITE_CHECK_URL || 'http://127.0.0.1:8238/';
const output = process.env.SITE_CHECK_OUTPUT || 'docs/evidence/237/full';
const { waitForImages } = require('./site-images-ready.cjs');
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  });
  const results = [];
  for (const width of [390, 1440]) for (const colorScheme of ['light']) {
    for (const path of ['', 'privacy/', 'support/', 'terms/', 'delete-account/', 'blog/', ...fs.readdirSync('site/blog', {withFileTypes:true}).filter(e=>e.isDirectory() && fs.existsSync(`site/blog/${e.name}/index.html`)).map(e=>`blog/${e.name}/`)]) {
      const page = await browser.newPage({ viewport: { width, height: 844 }, colorScheme, reducedMotion: 'reduce' });
      await page.goto(url + path);
      await waitForImages(page);
      await page.evaluate(async () => {
        document.querySelectorAll('details').forEach(detail => detail.open = true);
        await document.fonts.ready;
      });
      await page.addScriptTag({ path: require.resolve('axe-core/axe.min.js') });
      const audit = () => page.evaluate(async () => {
        const result = await axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } });
        return { violations: result.violations, incomplete: result.incomplete.map(item => item.id) };
      });
      results.push({ width, colorScheme, path, menu: false, ...await audit() });
      if (width === 390) {
        await page.getByRole('button', { name: 'Menu', exact: false }).click();
        results.push({ width, colorScheme, path, menu: true, ...await audit() });
        await page.keyboard.press('Escape');
      }
      await page.close();
    }
  }
  await browser.close();
  fs.mkdirSync(output, { recursive: true });
  fs.writeFileSync(`${output}/axe.json`, JSON.stringify(results, null, 2) + '\n');
  if (results.some(result => result.violations.length)) throw Error('WCAG violations; see axe.json');
  console.log(`PASS: ${results.length} full-page and menu accessibility contexts`);
})();

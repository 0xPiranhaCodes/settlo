// Mobile navigation contract: native dismissal, keyboard containment and layout.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const url = process.env.SITE_CHECK_URL || 'http://127.0.0.1:8237/';
(async () => {
 const browser = await chromium.launch({executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 const results=[];
 for (const path of ['', 'privacy/', 'support/', 'terms/', 'delete-account/', 'blog/', ...fs.readdirSync('site/blog', {withFileTypes:true}).filter(e=>e.isDirectory() && fs.existsSync(`site/blog/${e.name}/index.html`)).map(e=>`blog/${e.name}/`)]) for (const width of [360,390,720,721,1440]) for (const colorScheme of ['light']) for (const reducedMotion of ['reduce','no-preference']) {
  const page=await browser.newPage({viewport:{width,height:844},colorScheme,reducedMotion});
  await page.goto(url+path);
  for (const selector of ['header nav', '#mobile-menu nav', 'footer']) {
   const blog = page.locator(selector).getByRole('link', {name:'Blog', exact:true, includeHidden:true});
   assert.equal(await blog.count(),1);
   assert.equal(await blog.evaluate(e=>new URL(e.href).pathname),'/blog/');
  }
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  const button=page.locator('.mobile-menu-button'), menu=page.locator('#mobile-menu');
  if(width>720) {assert.equal(await button.isVisible(),false);await page.close();continue;}
  assert.equal((await page.locator('header').boundingBox()).height,56);
  await button.click();
  await page.waitForTimeout(400);
  assert.equal(await button.getAttribute('aria-expanded'),'true');
  assert.equal(await menu.evaluate(e=>e.contains(document.activeElement)),true);
  await page.keyboard.press('Shift+Tab');
  assert.equal(await menu.locator('a').last().evaluate(e=>e===document.activeElement),true);
  await page.keyboard.press('Tab');
  assert.equal(await menu.locator('button').evaluate(e=>e===document.activeElement),true);
  for(const target of await menu.locator('a,button').all()) assert.ok((await target.boundingBox()).height>=44);
  if(reducedMotion==='reduce') assert.equal(await menu.evaluate(e=>getComputedStyle(e).animationName),'none');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(400);
  assert.equal(await menu.isVisible(),false);
  assert.equal(await button.getAttribute('aria-expanded'),'false');
  assert.equal(await button.evaluate(e=>e===document.activeElement),true);
  await button.click();
  await menu.getByRole('link',{name:'Trust',exact:true}).click();
  await page.waitForTimeout(400);
  assert.equal(await menu.isVisible(),false);
  assert.equal(new URL(page.url()).hash,'#trust');
  assert.equal(await page.locator('header').evaluate(e=>getComputedStyle(e).position),'sticky');
  assert.ok(await page.locator('header').evaluate(e=>Number(getComputedStyle(e,'::before').opacity)>.9));
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  results.push({path,width,colorScheme,reducedMotion,passed:true});
  await page.close();
 }
 await browser.close();
 const output=process.env.SITE_CHECK_OUTPUT || '/tmp/settlo-site-check';fs.mkdirSync(output,{recursive:true});fs.writeFileSync(`${output}/menu.json`,JSON.stringify(results,null,2));
 console.log(`Passed ${results.length} mobile menu contexts and desktop visibility checks`);
})();

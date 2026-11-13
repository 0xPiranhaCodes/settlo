// #237 full-page evidence. Run against a local server with Playwright + axe-core.
const {chromium}=require('playwright');
const fs=require('node:fs');
const {waitForImages}=require('./site-images-ready.cjs');
const url=process.env.SITE_CHECK_URL || 'http://127.0.0.1:8238/';
const output=process.env.SITE_CHECK_OUTPUT || 'docs/evidence/237/full';
(async()=>{
 fs.mkdirSync(output,{recursive:true});
 const browser=await chromium.launch({executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--disable-gpu']});
 const results=[];
 for(const width of [390,1440]) for(const colorScheme of ['light']) {
  const viewport={width,height:width===390?844:900};
  const context=await browser.newContext({viewport,colorScheme,recordVideo:{dir:output,size:viewport}});
  const page=await context.newPage();const external=[],failures=[];
  page.on('request',r=>{if(!r.url().startsWith(url))external.push(r.url());});
  page.on('pageerror',e=>failures.push(e.message));
  await page.goto(url);await page.evaluate(()=>document.fonts.ready);
  await page.evaluate(async()=>{document.querySelectorAll('img').forEach(i=>i.loading='eager');await Promise.all([...document.images].map(i=>i.decode()));});
  await page.screenshot({path:`${output}/full-${width}-${colorScheme}.png`,fullPage:true});
  await page.waitForTimeout(600);
  const end=await page.evaluate(()=>document.documentElement.scrollHeight-innerHeight);
  await page.evaluate(async end=>{const start=performance.now();await new Promise(resolve=>{function frame(now){const t=Math.min(1,(now-start)/50000);scrollTo({top:end*t,behavior:'instant'});if(t<1)requestAnimationFrame(frame);else resolve();}requestAnimationFrame(frame);});},end);
  await page.waitForTimeout(700);
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
  const video=page.video();await context.close();await video.saveAs(`${output}/scroll-${width}-${colorScheme}.webm`);await video.delete();
  results.push({width,colorScheme,external,failures,overflow});
  const p=await browser.newPage({viewport,colorScheme,reducedMotion:'reduce'});await p.goto(url);await waitForImages(p);await p.evaluate(()=>document.fonts.ready);
  await p.screenshot({path:`${output}/reduced-${width}-${colorScheme}.png`,fullPage:true});
  await p.locator('.flat').screenshot({path:`${output}/splits-${width}-${colorScheme}.png`});
  await p.locator('.quiet').screenshot({path:`${output}/safety-${width}-${colorScheme}.png`});
  results.push({width,colorScheme,reduced:await p.locator('.direction-pin').evaluate(e=>getComputedStyle(e).position),safety:await p.locator('.safety-aside').evaluate(e=>getComputedStyle(e).position),visiblePanels:await p.locator('.direction-panel').evaluateAll(es=>es.every(e=>getComputedStyle(e).opacity==='1'))});
  await p.close();console.log(`Recorded ${width} ${colorScheme}`);
 }
 fs.writeFileSync(`${output}/browser-checks.json`,JSON.stringify(results,null,2));
 await browser.close();
 if(results.some(r=>r.overflow||r.external?.length||r.failures?.length||r.visiblePanels===false||r.reduced&&r.reduced!=='static'||r.safety&&r.safety!=='static'))throw Error('Full-page checks failed');
})();

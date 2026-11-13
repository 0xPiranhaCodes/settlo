// #249: reproducible direction recordings (hero, sticky story, trust), state checks and static screenshots.
const {chromium}=require('playwright');
const {waitForImages}=require('./site-images-ready.cjs');
const fs=require('fs');
const url=process.env.SITE_CHECK_URL || 'http://127.0.0.1:8237/';
const output=process.env.SITE_CHECK_OUTPUT || 'docs/evidence/249/direction';
(async()=>{
 fs.mkdirSync(output,{recursive:true});
 const browser=await chromium.launch({executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 const results=[];
 for(const width of [390,1440]) {
  const viewport={width,height:width===390?844:900};
  const context=await browser.newContext({viewport,recordVideo:{dir:output,size:viewport}});
  const page=await context.newPage();const external=[];
  page.on('request',r=>{if(!r.url().startsWith(url))external.push(r.url());});
  await page.goto(url);await page.evaluate(()=>document.fonts.ready);
  await page.waitForTimeout(1600);
  await page.screenshot({path:`${output}/hero-${width}.png`});
  // A steady scroll from the hero through the trust section; the story pins on the way.
  const end=await page.locator('.trust').evaluate(el=>el.offsetTop+el.offsetHeight-innerHeight);
  await page.evaluate(async end=>{const start=performance.now();await new Promise(resolve=>{function frame(now){const t=Math.min(1,(now-start)/24000);scrollTo({top:end*t,behavior:'instant'});if(t<1)requestAnimationFrame(frame);else resolve();}requestAnimationFrame(frame);});},end);
  await page.waitForTimeout(1200);
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
  const video=page.video();await context.close();await video.saveAs(`${output}/scroll-${width}.webm`);await video.delete();
  const checkPage=await browser.newPage({viewport});await checkPage.goto(url);
  const states=[];
  for(const [i,progress] of [.1,.48,.9].entries()) {
   await checkPage.evaluate(progress=>{const e=document.querySelector('.direction-story');scrollTo({top:e.offsetTop+(e.offsetHeight-innerHeight)*progress,behavior:'instant'});},progress);
   await checkPage.waitForTimeout(400);
   states.push(await checkPage.locator('.direction-panel').evaluateAll(els=>els.map(e=>Number(getComputedStyle(e).opacity))));
   await checkPage.screenshot({path:`${output}/story-${i+1}-${width}.png`});
  }
  await checkPage.locator('.trust').evaluate(el=>scrollTo({top:el.offsetTop-80,behavior:'instant'}));
  await checkPage.waitForTimeout(1500);
  await checkPage.screenshot({path:`${output}/trust-${width}.png`});
  results.push({width,external,states,overflow});await checkPage.close();
  const staticPage=await browser.newPage({viewport,reducedMotion:'reduce'});await staticPage.goto(url);await waitForImages(staticPage);await staticPage.evaluate(()=>document.fonts.ready);
  const bottom=await staticPage.locator('.trust').evaluate(el=>el.offsetTop+el.offsetHeight);
  await staticPage.screenshot({path:`${output}/reduced-${width}.png`,fullPage:true,clip:{x:0,y:0,width,height:bottom}});
  results.push({width,reduced:await staticPage.locator('.direction-pin').evaluate(el=>getComputedStyle(el).position),visiblePanels:await staticPage.locator('.direction-panel').evaluateAll(els=>els.every(e=>getComputedStyle(e).opacity==='1'))});
  await staticPage.close();
 }
 const p=await browser.newPage({viewport:{width:360,height:800}});await p.goto(url);results.push({width:360,overflow:await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth)});await p.close();
 fs.writeFileSync(`${output}/browser-checks.json`,JSON.stringify(results,null,2)+'\n');await browser.close();
 if(results.some(r=>r.overflow||r.external?.length||r.visiblePanels===false||r.reduced&&r.reduced!=='static'))throw Error('Direction checks failed');
})();

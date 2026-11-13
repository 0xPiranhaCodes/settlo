// #237: reproducible direction recordings, state checks and static screenshots.
const {chromium}=require('playwright');
const fs=require('fs');
const url=process.env.SITE_CHECK_URL || 'http://127.0.0.1:8237/';
const output=process.env.SITE_CHECK_OUTPUT || 'docs/evidence/237/direction';
(async()=>{
 fs.mkdirSync(output,{recursive:true});
 const browser=await chromium.launch({executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 const results=[];
 for(const width of [390,1440]) for(const colorScheme of ['light']) {
  const viewport={width,height:width===390?844:900};
  const context=await browser.newContext({viewport,colorScheme,recordVideo:{dir:output,size:viewport}});
  const page=await context.newPage();const external=[];
  page.on('request',r=>{if(!r.url().startsWith(url))external.push(r.url());});
  await page.goto(url);await page.evaluate(()=>document.fonts.ready);
  await page.screenshot({path:`${output}/hero-${width}-${colorScheme}.png`});
  await page.waitForTimeout(700);
  if(width===390) {
   await page.getByRole('button',{name:'Menu',exact:false}).click();
   await page.waitForTimeout(350);
   await page.screenshot({path:`${output}/menu-open-${width}-${colorScheme}.png`});
   await page.waitForTimeout(700);
   await page.getByRole('button',{name:'Close',exact:false}).click();
   await page.waitForTimeout(500);
  }
  const end=await page.locator('.direction-story').evaluate(el=>el.offsetTop+el.offsetHeight-innerHeight);
  await page.evaluate(async end=>{const start=performance.now();await new Promise(resolve=>{function frame(now){const t=Math.min(1,(now-start)/18000);scrollTo({top:end*t,behavior:'instant'});if(t<1)requestAnimationFrame(frame);else resolve();}requestAnimationFrame(frame);});},end);
  await page.waitForTimeout(800);
  await page.screenshot({path:`${output}/settled-${width}-${colorScheme}.png`});
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
  const video=page.video();await context.close();await video.saveAs(`${output}/scroll-${width}-${colorScheme}.webm`);await video.delete();
  const checkPage=await browser.newPage({viewport,colorScheme});await checkPage.goto(url);
  const states=[];
  for(const progress of [.1,.48,.9]) {
   await checkPage.evaluate(progress=>{const e=document.querySelector('.direction-story');scrollTo({top:e.offsetTop+(e.offsetHeight-innerHeight)*progress,behavior:'instant'});},progress);
   await checkPage.waitForTimeout(100);
   states.push(await checkPage.locator('.direction-panel').evaluateAll(els=>els.map(e=>Number(getComputedStyle(e).opacity))));
  }
  results.push({width,colorScheme,external,states,overflow});await checkPage.close();
  const staticPage=await browser.newPage({viewport,colorScheme,reducedMotion:'reduce'});await staticPage.goto(url);await staticPage.evaluate(()=>document.fonts.ready);
  await staticPage.locator('.direction-story').screenshot({path:`${output}/reduced-${width}-${colorScheme}.png`});
  results.push({width,colorScheme,reduced:await staticPage.locator('.direction-pin').evaluate(el=>getComputedStyle(el).position),visiblePanels:await staticPage.locator('.direction-panel').evaluateAll(els=>els.every(e=>getComputedStyle(e).opacity==='1'))});
  await staticPage.close();
 }
 for(const colorScheme of ['light']) {const p=await browser.newPage({viewport:{width:360,height:800},colorScheme});await p.goto(url);results.push({width:360,colorScheme,overflow:await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth)});await p.close();}
 fs.writeFileSync(`${output}/browser-checks.json`,JSON.stringify(results,null,2));await browser.close();
 if(results.some(r=>r.overflow||r.external?.length||r.visiblePanels===false))throw Error('Direction checks failed');
})();

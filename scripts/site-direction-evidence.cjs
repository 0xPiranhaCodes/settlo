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
  // Header at rest, then hover (desktop) or the menu opening and closing (mobile).
  const top={x:0,y:0,width,height:96};
  if(width===1440) {
   await page.screenshot({path:`${output}/header-1440-rest.png`,clip:top});
   for(const link of await page.locator('header nav a').all()) {await link.hover();await page.waitForTimeout(500);}
   await page.mouse.move(width/2,500);await page.waitForTimeout(600);
  } else {
   await page.screenshot({path:`${output}/header-390.png`,clip:top});
   await page.locator('.mobile-menu-button').click();await page.waitForTimeout(1000);
   await page.screenshot({path:`${output}/menu-390.png`});
   await page.locator('#mobile-menu .mobile-menu-heading button').click();await page.waitForTimeout(800);
  }
  // A steady scroll from the hero through the trust section; the story pins on the way.
  const end=await page.locator('.trust').evaluate(el=>el.offsetTop+el.offsetHeight-innerHeight);
  await page.evaluate(async end=>{const start=performance.now();await new Promise(resolve=>{function frame(now){const t=Math.min(1,(now-start)/24000);scrollTo({top:end*t,behavior:'instant'});if(t<1)requestAnimationFrame(frame);else resolve();}requestAnimationFrame(frame);});},end);
  await page.waitForTimeout(1200);
  if(width===1440) {
   for(const link of await page.locator('header nav a').all()) {await link.hover();await page.waitForTimeout(500);}
   await page.mouse.move(width/2,500);await page.waitForTimeout(600);
   await page.screenshot({path:`${output}/header-1440-scrolled.png`,clip:top});
  }
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
  // AA for header text composited over the capsule surface above each section and the footer.
  const headerContrast=[];
  for(const index of await checkPage.locator('main > section, body > footer').evaluateAll(els=>els.map((_,i)=>i))) {
   await checkPage.evaluate(i=>{const e=document.querySelectorAll('main > section, body > footer')[i];scrollTo({top:e.getBoundingClientRect().top+scrollY,behavior:'instant'});},index);
   await checkPage.waitForTimeout(450);
   headerContrast.push(await checkPage.evaluate(i=>{
    const parse=c=>{const n=c.match(/[\d.]+/g).map(Number);return c.startsWith('color(')?[n[0]*255,n[1]*255,n[2]*255,n[3]??1]:[n[0],n[1],n[2],n[3]??1];};
    const over=(top,base,alpha=top[3])=>[0,1,2].map(k=>top[k]*alpha+base[k]*(1-alpha));
    const lum=c=>{const [r,g,b]=c.map(v=>{v/=255;return v<=.03928?v/12.92:((v+.055)/1.055)**2.4;});return .2126*r+.7152*g+.0722*b;};
    const ratio=(a,b)=>{const [x,y]=[lum(a),lum(b)].sort((m,n)=>n-m);return (x+.05)/(y+.05);};
    const header=document.querySelector('header');const box=header.getBoundingClientRect();
    header.style.visibility='hidden';let under=document.elementFromPoint(box.left+box.width/2,box.top+box.height/2);header.style.visibility='';
    let bg=[255,255,255];const chain=[];for(let e=under;e;e=e.parentElement)chain.unshift(e);
    for(const e of chain){const c=parse(getComputedStyle(e).backgroundColor);if(c[3])bg=over(c,bg);}
    const before=getComputedStyle(header,'::before'),after=getComputedStyle(header,'::after');
    let surface=over(parse(before.backgroundColor),bg);surface=over(parse(after.backgroundColor),surface,parse(after.backgroundColor)[3]*Number(after.opacity));
    const texts=[...header.querySelectorAll('.wordmark, nav a, .mobile-menu-button')].filter(e=>e.offsetParent);
    const section=document.querySelectorAll('main > section, body > footer')[i];
    return {section:section.id||section.className.split(' ')[0]||section.tagName.toLowerCase(),min:Math.min(...texts.map(e=>ratio(parse(getComputedStyle(e).color),surface))).toFixed(2)};
   },index));
  }
  results.push({width,external,states,overflow,headerContrast});await checkPage.close();
  const staticPage=await browser.newPage({viewport,reducedMotion:'reduce'});await staticPage.goto(url);await waitForImages(staticPage);await staticPage.evaluate(()=>document.fonts.ready);
  const bottom=await staticPage.locator('.trust').evaluate(el=>el.offsetTop+el.offsetHeight);
  await staticPage.screenshot({path:`${output}/reduced-${width}.png`,fullPage:true,clip:{x:0,y:0,width,height:bottom}});
  results.push({width,reduced:await staticPage.locator('.direction-pin').evaluate(el=>getComputedStyle(el).position),visiblePanels:await staticPage.locator('.direction-panel').evaluateAll(els=>els.every(e=>getComputedStyle(e).opacity==='1'))});
  await staticPage.close();
 }
 const p=await browser.newPage({viewport:{width:360,height:800}});await p.goto(url);results.push({width:360,overflow:await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth)});await p.close();
 fs.writeFileSync(`${output}/browser-checks.json`,JSON.stringify(results,null,2)+'\n');await browser.close();
 if(results.some(r=>r.headerContrast?.some(c=>c.min<4.5)||r.overflow||r.external?.length||r.visiblePanels===false||r.reduced&&r.reduced!=='static'))throw Error('Direction checks failed');
})();

// Local browser design verification. Requires Playwright; not an app test suite.
const {chromium}=require('playwright');
const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'..');
const base=process.env.DODDY_DESIGN_URL||'http://127.0.0.1:8768/';
const checks=[],errors=[],bad=[];
const check=(name,ok,detail='')=>{checks.push({name,passed:!!ok,detail});if(!ok)throw new Error(name+': '+detail);};
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.DODDY_CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 const page=await browser.newPage({viewport:{width:1400,height:1240},deviceScaleFactor:1});
 page.on('pageerror',e=>errors.push(String(e)));
 page.on('response',r=>{if(r.status()>=400)bad.push({url:r.url(),status:r.status()});});
 for(const [direction,file]of[['notebook','01-pocket-notebook'],['quiet','02-quiet-companion'],['investigation','03-tiny-investigation']]){
  await page.goto(base+'?view=directions&direction='+direction+'&shot=1');await page.evaluate(()=>document.fonts.ready);
  check(direction+' 3 comparable screens',await page.locator('.phone').count()===3);
  check(direction+' original art loaded',await page.locator('.phone img').evaluateAll(xs=>xs.every(x=>x.complete&&x.naturalWidth>0)));
  await page.screenshot({path:path.join(root,'previews',file+'.png'),fullPage:true});
 }
 for(const [filter,file]of[['core','04-core-gallery'],['failure','05-failure-recovery'],['voice','06-planned-voice'],['variants','07-appearance-accessibility']]){
  await page.goto(base+'?view=gallery&filter='+filter+'&shot=1');await page.evaluate(()=>document.fonts.ready);
  await page.screenshot({path:path.join(root,'previews',file+'.png'),fullPage:true});
  for(const p of await page.locator('.phone').all()){
   check('No horizontal clipping: '+await p.getAttribute('aria-label'),await p.locator('.app-body').evaluate(el=>el.scrollWidth<=el.clientWidth+1));
  }
 }
 await page.goto(base+'?view=storyboard&shot=1');await page.evaluate(()=>document.fonts.ready);await page.screenshot({path:path.join(root,'previews/08-motion-storyboard.png'),fullPage:true});
 await page.goto(base+'?view=gallery');await page.evaluate(()=>document.fonts.ready);
 check('All 42 screen studies present',await page.locator('.phone').count()===42);
 for(const key of ['home','capture','recall','detail','dark-home','polish-home','large-home','small-home','save-failed','unknown']){
  await page.locator(`.phone[aria-label="${key} design"]`).screenshot({path:path.join(root,'previews',key+'.png')});
 }
 await page.goto(base+'?view=prototype');await page.evaluate(()=>document.fonts.ready);
 const device=page.locator('#prototype-device');
 await device.locator('[data-action="skip-setup"]').click();
 await device.locator('[data-action="skip-intro"]').click();
 const click=async action=>device.locator(`[data-action="${action}"]`).first().click();
 const jump=async s=>page.locator('#jump-screen').selectOption(s);
 await click('capture');await device.locator('textarea').fill('The spare keys are in the blue tin above the fridge.');await click('save');
 await device.locator('.stamp').waitFor();check('Confirmed save follows mock commit',await device.textContent().then(s=>s.includes('Save confirmed')));
 await click('home');await click('recall');await device.locator('[data-field="query"]').fill('spare keys');await device.locator('[data-form="search"]').evaluate(f=>f.requestSubmit());
 check('Keyword recall returns saved candidate',await device.locator('.result-row').count()===1);
 await click('detail');check('Exact source detail opens',await device.textContent().then(s=>s.includes('Your typed note')));
 await click('edit');await device.locator('textarea').fill('The spare keys are now in the kitchen drawer.');await click('update');await device.locator('.detail-meta').waitFor();
 check('Correction preserves original capture',await device.textContent().then(s=>s.includes('kitchen drawer')&&s.includes('Original capture')&&s.includes('blue tin')&&s.includes('REVISION 2')));
 await click('delete-confirm');await click('confirm-delete');check('Delete removes candidate',await device.locator('.result-row').count()===0);
 await page.locator('[data-option="outcome"]').selectOption('failure');await jump('home');await click('capture');await device.locator('textarea').fill('A failed draft must stay here.');await click('save');await device.locator('.callout.error').waitFor();
 check('Failure preserves draft',await device.locator('textarea').inputValue()==='A failed draft must stay here.');
 check('Failure does not show success',await device.locator('.stamp').count()===0);
 await page.locator('[data-option="outcome"]').selectOption('unknown');await click('save');await device.locator('.callout').filter({hasText:'confirm the outcome'}).waitFor();
 check('Unknown has no success or direct write retry',await device.locator('.stamp,[data-action="save"],[data-action="update"]').count()===0);
 await page.locator('[data-option="outcome"]').selectOption('slow');await jump('home');await click('capture');await device.locator('textarea').fill('Cancelled draft stays.');await click('save');await click('cancel-save');await page.waitForTimeout(2300);
 check('Cancelled late receipt cannot create success',await device.locator('textarea').inputValue()==='Cancelled draft stays.'&&await device.locator('.stamp').count()===0);
 await click('home');await click('recall');check('Failure/unknown/cancel did not create memory',await device.locator('.result-row').count()===0);
 await page.locator('[data-option="outcome"]').selectOption('success');await click('capture');await click('save');await device.locator('.stamp').waitFor();await click('home');await click('settings');await click('delete-all');await click('confirm-delete-all');check('Delete all does not reseed samples',await device.locator('.result-row').count()===0);
 await jump('home');await page.locator('[data-option="dark"]').selectOption('true');check('Dark mode uses original dark SVG',await device.locator('img').getAttribute('src').then(s=>s.includes('-dark-')));
 await page.locator('[data-option="large"]').selectOption('true');check('Large text removes decorative staging',await device.locator('.personal-greeting img').evaluate(el=>getComputedStyle(el).display)==='none');
 await page.locator('[data-option="small"]').selectOption('true');await page.locator('[data-option="lang"]').selectOption('pl');check('Small/large Polish layout wraps without horizontal clipping',await device.locator('.app-body').evaluate(el=>el.scrollWidth<=el.clientWidth+1));
 await page.locator('[data-option="reduced"]').selectOption('true');check('Reduced motion disables character animation',await device.locator('img').evaluate(el=>getComputedStyle(el).animationName)==='none');
 await page.locator('[data-option="large"]').selectOption('false');await page.locator('[data-option="small"]').selectOption('false');await page.locator('[data-option="lang"]').selectOption('en');await page.locator('[data-option="dark"]').selectOption('false');await jump('voice-listening');
 check('Voice scene carries simulation disclosure',await device.textContent().then(s=>s.includes('SIMULATION')&&s.includes('NO MICROPHONE')));await click('voice-interrupted');check('Interruption gives user the floor',await device.textContent().then(s=>s.includes('Over to you.')));
 await page.emulateMedia({reducedMotion:'reduce'});await jump('home');await page.locator('[data-option="reduced"]').selectOption('false');check('OS reduced motion overrides normal selector',await device.locator('img').evaluate(el=>getComputedStyle(el).animationName)==='none');
 await page.setViewportSize({width:390,height:844});await page.goto(base+'?view=prototype');check('Mobile studio has no page horizontal overflow',await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await page.goto('file://'+path.join(root,'index.html')+'?view=prototype');await page.evaluate(()=>document.fonts.ready);check('Portable file opening works',await page.locator('#prototype-device .phone').count()===1);check('Portable font loaded',await page.evaluate(()=>document.fonts.check('16px Inter')));
 check('No JavaScript runtime errors',errors.length===0,JSON.stringify(errors));check('No failed local asset requests',bad.length===0,JSON.stringify(bad));
 const report={date:'2026-10-08',scope:'Local Chrome browser design prototype. No native/device tests.',checksPassed:checks.length,checks,errors,bad,limitations:['No SwiftUI implementation','No live AI/voice/reminders/system surfaces','No physical-device, VoiceOver or bilingual user study','Large-text study is a browser approximation, not native Dynamic Type validation']};
 fs.writeFileSync(path.join(root,'verification/browser-results.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({checksPassed:checks.length,runtimeErrors:errors.length,failedAssets:bad.length}));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});

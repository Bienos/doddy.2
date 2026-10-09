import fs from 'node:fs';
import path from 'node:path';
import {chromium} from '/Users/popcorn/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
const out=path.resolve('outputs/Doddy-Dynamic-Island-v4'),m=JSON.parse(fs.readFileSync(path.join(out,'manifest.json')));
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];
 page.on('pageerror',e=>errors.push(String(e)));
 await page.goto('file://'+out+'/Gallery.html');
 let checks=0;
 for(const c of m.components){
  await page.selectOption('#direction',c.direction);
  await page.selectOption('#activity',c.activity);
  await page.selectOption('#state',c.state);
  for(const scale of [1,2]){
   await page.selectOption('#scale',String(scale));
   await page.waitForFunction(()=>['detailImage','phoneImage'].every(id=>{const im=document.getElementById(id);return im.complete&&im.naturalWidth>0}));
   const sizes=await page.evaluate(()=>{const d=document.getElementById('detailImage');return {width:d.width,height:d.height}});
   if(Math.abs(sizes.width-c.width*scale)>1||Math.abs(sizes.height-c.height*scale)>1)throw Error('Unexpected display size '+c.path);
   checks++;
  }
 }
 for(let i=0;i<m.boards.length;i++){
  await page.selectOption('#boardPick',String(i));
  await page.waitForFunction(()=>{const im=document.getElementById('boardImage');return im.complete&&im.naturalWidth===2560});
  checks++;
 }
 await page.selectOption('#direction','language-bridge');await page.selectOption('#activity','1');await page.selectOption('#state','expanded');
 await page.locator('#inspector').scrollIntoViewIfNeeded();
 await page.screenshot({path:out+'/04-review/Gallery-preview.png',fullPage:false});
 if(errors.length)throw Error(errors.join('\n'));
 const svgPage=await browser.newPage(),bounds=[],collisions=[];
 for(const c of m.components){
  await svgPage.setContent(fs.readFileSync(path.join(out,c.path),'utf8'));
  const result=await svgPage.evaluate(({w,h,state})=>{
   const s=document.querySelector('svg').getBoundingClientRect(),hw=document.querySelector('[data-hardware]')?.getBoundingClientRect();
   const leaves=[...document.querySelectorAll('[data-content] text,[data-content] path,[data-content] circle,[data-content] ellipse,[data-content] rect')];
   const outside=[],overlap=[];
   for(const e of leaves){const b=e.getBoundingClientRect();if(b.width===0&&b.height===0)continue;
    const label=e.textContent||e.tagName;
    if(b.left<s.left-.15||b.top<s.top-.15||b.right>s.left+w+.15||b.bottom>s.top+h+.15)outside.push(label);
    if(hw&&b.left<hw.right&&b.right>hw.left&&b.top<hw.bottom&&b.bottom>hw.top)overlap.push(label);
   }
   const surface=document.querySelector('[data-surface]');
   return {outside,overlap,surfaces:document.querySelectorAll('[data-surface]').length,radius:+surface.getAttribute('rx')};
  },{w:c.width,h:c.height,state:c.state});
  if(result.outside.length)bounds.push({path:c.path,elements:result.outside});
  if(result.overlap.length)collisions.push({path:c.path,elements:result.overlap});
  if(result.surfaces!==1||(c.state==='expanded'&&result.radius!==44))throw Error('Surface geometry '+c.path);
 }
 const boardBounds=[];
 for(const b of [...m.boards,...Object.values(m.review)]){
  await svgPage.setContent(fs.readFileSync(path.join(out,b.svg),'utf8'));
  const bad=await svgPage.evaluate(()=>{
   const s=document.querySelector('svg').getBoundingClientRect();
   return [...document.querySelectorAll('text')].filter(e=>{const b=e.getBoundingClientRect();return b.left<s.left-.5||b.top<s.top-.5||b.right>s.right+.5||b.bottom>s.bottom+.5}).map(e=>e.textContent);
  });
  if(bad.length)boardBounds.push({path:b.svg,text:bad});
 }
 const core=m.catalog.filter(x=>x.family==='CORE DIRECTION');
 if(core.length!==6||core.some(x=>!x.variants.some(v=>v.label==='VOICE SESSION')||!x.variants.some(v=>v.label==='FOCUS TIMER')))throw Error('Core scenarios missing');
 const report={boards:m.boards.length,states:m.components.length,galleryChecks:checks,contentBoundsChecks:m.components.length,hardwareExclusionChecks:64,boardTextBoundsChecks:m.boards.length+Object.values(m.review).length,pageErrors:errors,overflow:bounds,hardwareCollisions:collisions,boardOverflow:boardBounds,scope:'Local static design/gallery validation only. No native iOS, simulator, device, motion, accessibility or live-service validation.'};
 fs.writeFileSync(path.join(out,'Validation.json'),JSON.stringify(report,null,2));
 if(bounds.length||collisions.length||boardBounds.length)throw Error(JSON.stringify(report));
 console.log(JSON.stringify(report));
}finally{await browser.close();}

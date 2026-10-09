import fs from 'node:fs';
import path from 'node:path';
import sharp from '/Users/popcorn/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs';
const out=path.resolve('outputs/Doddy-Dynamic-Island-v4'),m=JSON.parse(fs.readFileSync(path.join(out,'manifest.json')));
const embed=(s,x,y,w,h)=>'<image href="data:image/svg+xml;base64,'+Buffer.from(s).toString('base64')+'" x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'"/>';
const text=(x,y,s,z=23,c='#080808')=>'<text x="'+x+'" y="'+y+'" font-size="'+z+'" fill="'+c+'">'+s+'</text>';
let b='<rect width="2560" height="1760" fill="#F5EFE2"/>'+text(88,90,'DODDY / COMPLETE REDESIGN',23)+text(88,177,'Same Doddy. A different way to show up.',70)+text(88,238,'The character and the action now form one useful little instrument.',28,'#756F63');
const targets=[['orbit',1,'A / Orbit','From a corner avatar and flat oval to a precise face-centred dial.'],['thought-drop',1,'G / Thought Pocket','From a completion bowl to a thought token being tucked safely away.'],['ink-ripple',0,'B / Ink Ripple','From two bottom strokes to sculpted ink, a listening hand and voice energy.'],['language-bridge',1,'H / Language Bridge','From language initials on a line to two recognisable dialogue forms.']];
for(const [i,[slug,vi,title,copy]] of targets.entries()){
 const x=88+(i%2)*1210,y=300+Math.floor(i/2)*666;
 b+=text(x,y+40,title,31)+text(x,y+83,copy,20,'#756F63')+text(x,y+128,'BEFORE / V3',15,'#756F63')+text(x+590,y+128,'AFTER / V4',15,'#756F63');
 const before=fs.readFileSync('outputs/Doddy-Dynamic-Island-v3/02-states/'+slug+'-'+vi+'-expanded.svg','utf8'),after=fs.readFileSync(path.join(out,'02-states',slug+'-'+vi+'-expanded.svg'),'utf8');
 b+=embed(before,x,y+155,530,224)+embed(after,x+590,y+155,530,224);
 const a=m.catalog.find(c=>c.slug===slug),v=a.variants[vi];
 b+=text(x,y+460,'Primary status: '+v.status,24)+text(x,y+501,'Context: '+v.context.replaceAll('&','&amp;'),21,'#756F63')+text(x,y+542,'Next action: '+({stop:'Stop',pause:'Pause',open:'Open',play:'Hear it'}[v.control]),21,'#756F63');
}
b+=text(88,1670,'All sixteen boards have new vector compositions; previous versions are preserved.',23,'#756F63')+text(88,1716,'Static mockups / motion proposed / native behaviour untested',18,'#756F63');
const s='<svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1760" viewBox="0 0 2560 1760"><title>Doddy V4 redesign comparison</title><style>text{font-family:Arial,Helvetica,sans-serif;font-weight:500}</style>'+b+'</svg>';
fs.writeFileSync(path.join(out,'04-review/Visual-audit.svg'),s);await sharp(Buffer.from(s)).png().toFile(path.join(out,'04-review/Visual-audit.png'));
m.review.audit={title:'What changed',svg:'04-review/Visual-audit.svg',png:'04-review/Visual-audit.png'};fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(m,null,2));
console.log('Before/after sheet written.');

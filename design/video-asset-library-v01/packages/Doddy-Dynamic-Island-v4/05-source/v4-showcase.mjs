import fs from 'node:fs';
import path from 'node:path';
import sharp from '/Users/popcorn/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs';
const out=path.resolve('outputs/Doddy-Dynamic-Island-v4'),m=JSON.parse(fs.readFileSync(path.join(out,'manifest.json')));
const text=(x,y,s,z=24,c='#080808',a='')=>'<text x="'+x+'" y="'+y+'" font-size="'+z+'" fill="'+c+'" '+a+'>'+s+'</text>';
const embed=(file,x,y,w,h)=>'<image href="data:image/svg+xml;base64,'+fs.readFileSync(path.join(out,file)).toString('base64')+'" x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'"/>';
let b='<rect width="2560" height="1440" fill="#F5EFE2"/>'+text(88,75,'DODDY / LITTLE INSTRUMENTS',20,'#080808','font-weight="600" letter-spacing="2"')+text(88,180,'Small actions. Proper Doddy.',82,'#080808','letter-spacing="-3"')+text(88,242,'A new language for focus, capture, saved thoughts and translation.',28,'#756F63');
b+=embed('03-phone-reference/thought-drop-1-expanded.svg',88,351,369.9,783)+text(88,1202,'ON YOUR PHONE / 0.90× REFERENCE',16,'#756F63');
const sample=[['orbit',1,'A / ORBIT','Keep a little momentum.'],['ink-ripple',0,'B / INK RIPPLE','Let the thought take shape.'],['thought-drop',1,'G / THOUGHT POCKET','Keep it somewhere good.'],['language-bridge',1,'H / LANGUAGE BRIDGE','Different words. Same understanding.']];
for(const [i,[slug,vi,title,copy]] of sample.entries()){const x=650+(i%2)*940,y=325+Math.floor(i/2)*470;b+=text(x,y,title,21,'#080808','font-weight="600" letter-spacing="1"')+embed('02-states/'+slug+'-'+vi+'-expanded.svg',x,y+31,834.75,351)+text(x,y+422,copy,22,'#756F63');}
b+=text(88,1359,'16 separate boards / compact, expanded and minimal / PNG + editable SVG',22,'#080808')+text(2472,1394,'Static mockups. Motion proposed. Native behaviour untested.',15,'#756F63','text-anchor="end"');
const s='<svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1440" viewBox="0 0 2560 1440"><title>Doddy Little Instruments / V4 showcase</title><style>text{font-family:Arial,Helvetica,sans-serif;font-weight:500;font-variant-numeric:tabular-nums}</style>'+b+'</svg>';
fs.writeFileSync(path.join(out,'04-review/Direction-showcase.svg'),s);await sharp(Buffer.from(s)).png().toFile(path.join(out,'04-review/Direction-showcase.png'));
console.log('Showcase exported.');

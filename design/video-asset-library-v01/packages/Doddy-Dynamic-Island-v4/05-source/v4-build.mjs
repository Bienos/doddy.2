import fs from 'node:fs';
import path from 'node:path';
import sharp from '/Users/popcorn/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.cjs';
export const out=path.resolve('outputs/Doddy-Dynamic-Island-v4');
for(const f of ['01-boards','02-states','03-phone-reference','04-review','05-source'])fs.mkdirSync(path.join(out,f),{recursive:true});
const old=JSON.parse(fs.readFileSync('outputs/Doddy-Dynamic-Island-v3/catalog.json'));
export const C={cream:'#F5EFE2',ink:'#080808',orange:'#EC803F',muted:'#756F63',quiet:'#BDB7AA',rule:'#D9D2C4'};
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;');
export const t=(x,y,s,size=14,c=C.cream,weight=500,a='')=>'<text x="'+x+'" y="'+y+'" font-size="'+size+'" fill="'+c+'" font-weight="'+weight+'" '+a+'>'+esc(s)+'</text>';
export const r=(x,y,w,h,z,c,a='')=>'<rect x="'+x+'" y="'+y+'" width="'+w+'" height="'+h+'" rx="'+z+'" fill="'+c+'" '+a+'/>';
export const p=(d,c=C.orange,w=1.8,a='')=>'<path d="'+d+'" fill="none" stroke="'+c+'" stroke-width="'+w+'" stroke-linecap="round" stroke-linejoin="round" '+a+'/>';
const fill=(d,c,a='')=>'<path d="'+d+'" fill="'+c+'" '+a+'/>';
export const dot=(x,y,z,c=C.orange)=>'<circle cx="'+x+'" cy="'+y+'" r="'+z+'" fill="'+c+'"/>';
export const g=(x,y,z,b,a='')=>'<g transform="translate('+x+' '+y+') scale('+z+')" '+a+'>'+b+'</g>';
export const svg=(w,h,b,title)=>'<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="'+h+'" viewBox="0 0 '+w+' '+h+'" role="img"><title>'+esc(title)+'</title><style>text{font-family:Arial,Helvetica,sans-serif;font-variant-numeric:tabular-nums;font-kerning:normal}.caps{letter-spacing:2px}</style>'+b+'</svg>';
export async function save(folder,name,w,h,b,title){const s=svg(w,h,b,title),file=path.join(out,folder,name);fs.writeFileSync(file+'.svg',s);await sharp(Buffer.from(s)).png().toFile(file+'.png');return {name,title,svg:folder+'/'+name+'.svg',png:folder+'/'+name+'.png'};}
export function face(x,y,size=36,mood='listen'){
 let b=dot(0,0,20,C.cream)+p('M0-20A20 20 0 1 1-.01-20',C.ink,1.4);
 b+='<ellipse cx="-5.5" cy=".7" rx="1.9" ry="'+(mood==='calm'?2.4:3.4)+'" fill="'+C.ink+'"/><ellipse cx="6.4" cy="-2.1" rx="1.9" ry="'+(mood==='calm'?2.4:3.4)+'" fill="'+C.ink+'"/>';
 b+=p(mood==='think'?'M3-12Q8-18 12-11':'M3-11Q8-16 12-11',C.ink,1.9);
 const mouth={listen:'M-5 8Q4 17 12 5',think:'M-4 9Q2 12 8 7',focus:'M-5 9Q3 13 10 6',proud:'M-7 6Q3 18 13 2',calm:'M-5 8Q3 13 10 5',speak:'M-6 6Q3 16 12 3Q10 17 3 17Q-3 15-6 6Z'}[mood]||'M-5 8Q4 17 12 5';
 b+=mood==='speak'?fill(mouth,C.ink):p(mouth,C.ink,2.1);
 return g(x,y,size/40,b);
}
function hand(x,y,z=14,pose='offer'){
 let b=fill(pose==='hold'?'M-11 4Q-14-2-9-4L-2-2L-3-9Q-1-15 3-9L6-2L10-1Q15 0 13 7Q8 14 0 13Q-8 13-11 4Z':'M-12 5Q-17 0-13-3L-5 0L-9-7Q-10-12-6-10L2-4L-3-11Q-3-15 1-12L8-5L4-11Q5-15 9-11L14-3Q19-1 15 7Q11 15 1 14Q-8 13-12 5Z',C.cream);
 b+=p('M-5 5Q2 1 9 5',C.ink,1.5);return g(x,y,z/30,b);
}
const arc=(x,y,rx,ry,f=.35,c=C.orange,w=2)=>{const a=Math.PI*2*f;return p('M'+(x+rx)+' '+y+'A'+rx+' '+ry+' 0 '+(f>.5?1:0)+' 1 '+(x+rx*Math.cos(a))+' '+(y+ry*Math.sin(a)),c,w);};
const ellipse=(x,y,rx,ry,c=C.quiet,w=1,a='')=>'<ellipse cx="'+x+'" cy="'+y+'" rx="'+rx+'" ry="'+ry+'" fill="none" stroke="'+c+'" stroke-width="'+w+'" '+a+'/>';
const check=(x,y,z=1,c=C.orange)=>g(x,y,z,p('M-5 0L-1 4L6-5',c,2));
const mood=v=>v.kind==='think'?'think':v.kind==='done'?'proud':v.kind==='speak'?'speak':v.kind==='focus'?'focus':v.kind.includes('paused')||v.kind.startsWith('breathe')?'calm':'listen';
const focus=v=>v.status==='12:48';
const titleMap={voice:'Lean In',focus:'Tiny Promise',music:'Pocket Radio',companion:'Here With You',orbit:'Orbit', 'ink-ripple':'Ink Ripple','negative-space':'Negative Space','kinetic-ribbon':'Kinetic Ribbon',editorial:'Editorial','abstract-landscape':'Abstract Horizon','thought-drop':'Thought Pocket','language-bridge':'Language Bridge','reminder-pin':'Reminder Knot','step-path':'Step Stones','spoken-mark':'Story Spool','calm-pulse':'Calm Tide'};
const ideas={voice:'A little lean-in. A proper conversation.',focus:'One small promise, kept one minute at a time.',music:'A tiny pocket radio, with Doddy on the dial.',companion:'Here with you, without taking over.',orbit:'A small instrument for a little momentum.','ink-ripple':'Thoughts take shape before they become words.','negative-space':'The island becomes part of Doddy’s gesture.','kinetic-ribbon':'Speech folds. Focus finds its line.',editorial:'Less illustration. More confidence. Still Doddy.','abstract-landscape':'A quiet horizon for the thing ahead.','thought-drop':'Catch it. Keep it close.','language-bridge':'Different words. Same understanding.','reminder-pin':'Tie a little knot for later.','step-path':'Make the big thing a few smaller things.','spoken-mark':'A good story, kept rolling.','calm-pulse':'A little room to reset.'};
const rationales={voice:'The cupped hand and short voice bars show attentive capture; the mouth changes when Doddy speaks.',focus:'A measured dial holds Doddy close to the countdown. The paused state keeps the same time and progress.',music:'Vinyl-like rings and a restrained orange needle make playback identifiable without an album cover.',companion:'Two small hands and a held conversation loop convey presence. Thinking replaces the active voice cue.',orbit:'Three quiet ticks give the elliptical dial precision; one orange segment carries focus progress or voice activity.','ink-ripple':'An organic cream silhouette and an orange energy contour form one speech instrument, rather than a decorative waveform.','negative-space':'A cream crescent cut from the island supports Doddy’s face and an offered hand. The black surface completes the gesture.','kinetic-ribbon':'The ribbon wraps the identity and changes from a controlled speech fold to a measured focus loop.','editorial':'Large tabular numerals and a small character signature let the information do the work. A caret marks active capture.','abstract-landscape':'Two cream contours form a horizon beneath Doddy. An orange marker indicates the active phase or timer progress.','thought-drop':'An orange thought token drops into a cream pocket. The proud face and offered hand turn completion into a Doddy moment.','language-bridge':'Two dialogue shapes carry EN and FR. The crossing turns orange when the phrase is ready to hear.','reminder-pin':'A cream reminder tag and a small orange knot connect setup to confirmation. The scheduled time stays primary metadata.','step-path':'Three stepping stones encode the plan. The orange first stone identifies the next step; the app contains the full breakdown.','spoken-mark':'An open paper spool and an orange word marker give read-aloud its own identity. Pause holds the marker in place.','calm-pulse':'A tide line and phase arc support the literal In/Out labels. The face remains calm as the breathing phase changes.'};
const motions={voice:'Replace the capture bars and mouth only with voice-state updates.',focus:'Countdown and dial follow actual remaining time. Pause holds both.',music:'The orange record segment follows playback progress and holds when paused.',companion:'Replace the conversation loop with thought points while processing.',orbit:'Dial segment follows progress; voice uses a bounded activity segment.', 'ink-ripple':'Speech updates change the energy contour. Focus settles it into a quiet curve.', 'negative-space':'The gesture stays still; the orange state point changes with useful updates.', 'kinetic-ribbon':'A bounded fold change follows voice-state updates. Focus has a stable measured loop.',editorial:'Numeric content changes stay on a fixed baseline; a caret indicates active capture.', 'abstract-landscape':'The horizon stays still; only the state/progress marker changes.', 'thought-drop':'A short transition tucks the thought token into the pocket and reveals the saved check.', 'language-bridge':'The crossing completes when the translation becomes ready. Hear it starts narration.', 'reminder-pin':'The knot settles once when setup completes; the later reminder is a notification.', 'step-path':'The active stone changes when a task step is completed.', 'spoken-mark':'The orange word marker advances with narration; pause holds its position.', 'calm-pulse':'The tide and phase arc change with the breathing phase; keep explicit In/Out text with reduced motion.'};
export const catalog=old.map(d=>({...d,title:titleMap[d.slug],idea:ideas[d.slug],rationale:rationales[d.slug],motion:motions[d.slug],strong:['orbit','thought-drop','language-bridge'].includes(d.slug)?['orbit','thought-drop','language-bridge'].indexOf(d.slug)+1:undefined,variants:d.variants.map(v=>({...v,context:d.slug==='reminder-pin'?'Call Mum':v.context,meta:focus(v)?(v.kind==='paused'?'Paused':'25 min'):v.meta}))}));
const actionLabel=v=>({stop:v.kind==='think'?'Cancel':'Stop',pause:'Pause',play:v.kind==='done'?'Hear it':'Resume',open:'Open'}[v.control]);
function icon(kind,x,y,c=C.cream){if(kind==='pause')return r(x-4,y-5,2.5,10,1,c)+r(x+1.5,y-5,2.5,10,1,c);if(kind==='play')return fill('M'+(x-3)+' '+(y-5)+'L'+(x+5)+' '+y+'L'+(x-3)+' '+(y+5)+'Z',c);if(kind==='stop')return r(x-4,y-4,8,8,1.5,c);return p('M'+(x-4)+' '+(y+4)+'L'+(x+4)+' '+(y-4)+'M'+(x-3)+' '+(y-4)+'H'+(x+4)+'V'+(y+3),c,1.6);}
function button(v,x=105,y=109){const done=v.kind==='done',c=done?C.ink:C.cream,w=v.control==='play'&&v.kind!=='done'?91:84;return '<g data-control="true">'+r(x,y-5,w,44,22,'transparent','data-hit-target="true"')+r(x,y,w,34,17,done?C.cream:'#27251F')+icon(v.control,x+19,y+17,c)+t(x+35,y+22,actionLabel(v),13,c,600)+'</g>';}
function radioControls(v){let b='';for(const [x,label] of [[105,'Back'],[174,v.control==='play'?'Play':'Pause'],[249,'Next']])b+=r(x,104,label==='Pause'?66:60,44,22,'transparent','data-hit-target="true"')+r(x,109,label==='Pause'?66:60,34,17,label==='Pause'||label==='Play'?'#27251F':'#171610')+t(x+(label==='Pause'?33:30),131,label,12.5,C.cream,600,'text-anchor="middle"');return b;}
function instrument(d,v){const key=d.slug,md=mood(v),q=focus(v)?1-v.fraction:v.fraction||.32;let b='';
 if(key==='orbit'||key==='focus'){
  b+=ellipse(49,84,34,28,'#534D40',1.2)+arc(49,84,34,28,q,C.orange,2.2);
  for(const a of [-Math.PI/2,Math.PI/6,Math.PI*5/6])b+=p('M'+(49+30*Math.cos(a))+' '+(84+24*Math.sin(a))+'L'+(49+35*Math.cos(a))+' '+(84+29*Math.sin(a)),C.cream,1.3);
  b+=face(49,84,36,md)+dot(49+34*Math.cos(2*Math.PI*q),84+28*Math.sin(2*Math.PI*q),2.6);
 }else if(key==='voice'){
  b+=face(45,81,36,md)+hand(72,84,17,'hold')+p('M74 59Q88 78 77 99',C.orange,2);
 }else if(key==='music'){
  b+=ellipse(48,84,33,33,C.cream,1.5)+ellipse(48,84,27,27,'#39362D',1.1)+ellipse(48,84,23,23,'#39362D',1.1)+arc(48,84,33,33,v.fraction,C.orange,2.5)+face(48,84,32,md)+p('M81 53L74 68',C.orange,2)+dot(81,53,2,C.cream);
 }else if(key==='companion'){
  b+=ellipse(48,83,31,26,'#4B463B',1.2)+face(48,78,34,md)+hand(22,105,15)+hand(77,103,15,'hold');
  b+=v.kind==='think'?dot(38,118,1.5,C.quiet)+dot(48,118,2)+dot(58,118,1.5,C.quiet):p('M39 115Q49 121 61 113',C.orange,2);
 }else if(key==='ink-ripple'){
  b+=fill('M19 81C12 64 24 57 39 59C49 43 74 51 76 69C92 82 74 94 70 106C66 123 51 119 45 108C30 109 22 97 19 81Z',C.cream)+face(48,78,36,md)+hand(27,98,17,'hold');
  b+=p(focus(v)?'M21 125Q49 113 81 125':'M22 120C35 120 34 102 43 114S60 133 66 120S78 112 86 116',C.orange,2);
 }else if(key==='negative-space'){
  b+=fill('M19 109Q8 81 30 61Q9 105 55 108Q79 107 84 83Q95 125 53 132Q31 134 19 109Z',C.cream)+face(48,80,36,md)+hand(77,103,17)+dot(focus(v)?24+56*q:32,119,3,C.orange);
 }else if(key==='kinetic-ribbon'){
  b+=p(focus(v)?'M21 112Q10 74 29 64Q76 49 84 91Q86 116 45 121':'M22 110C8 93 28 84 22 67C18 57 39 49 64 58C88 68 90 104 68 110C45 117 40 102 54 101C68 100 76 119 45 126',C.orange,3.1)+face(49,82,34,md);
  if(focus(v)){const segments=[[[21,112],[10,74],[29,64]],[[29,64],[76,49],[84,91]],[[84,91],[86,116],[45,121]]],at=Math.min(q*3,2.999),s=segments[Math.floor(at)],a=at-Math.floor(at),xy=[0,1].map(i=>(1-a)*(1-a)*s[0][i]+2*(1-a)*a*s[1][i]+a*a*s[2][i]);b+=dot(xy[0],xy[1],2.5,C.cream);}
 }else if(key==='abstract-landscape'){
  b+=face(48,71,34,md)+fill('M17 117Q39 83 69 112Q82 114 87 118L87 124H17Z',C.cream)+p('M18 129Q51 117 87 129','#8C8271',1.4)+dot(focus(v)?25+52*q:75,103,4,C.orange);
 }else if(key==='thought-drop'){
  b+=face(46,69,34,md)+p('M22 96Q49 107 77 94L73 119Q48 138 25 119Z',C.cream,1.8)+hand(28,94,16,'hold');
  b+=dot(v.kind==='done'?54:56,v.kind==='done'?108:88,7,C.orange)+hand(69,v.kind==='done'?103:83,16,'hold');
  if(v.kind==='done')b+=check(54,108,.55,C.ink);else b+=p('M70 61L74 56M80 65L86 63',C.orange,1.7);
 }else if(key==='language-bridge'){
  b+=face(49,67,32,md)+fill('M19 92Q19 86 26 86H43Q49 86 49 92V106H44L39 112V106H26Q19 106 19 100Z',C.cream)+fill('M56 92Q56 86 63 86H80Q87 86 87 92V100Q87 106 80 106H65L60 112V106H56Z',C.cream);
  b+=t(34,100,'EN',10,C.ink,700,'text-anchor="middle"')+t(71.5,100,'FR',10,C.ink,700,'text-anchor="middle"')+p('M26 119Q52 139 81 116','#4B463B',1.5)+p(v.kind==='done'?'M26 119Q52 139 81 116':'M26 119Q38 130 53 129',C.orange,2)+dot(v.kind==='done'?81:53,v.kind==='done'?116:129,2.2);
 }else if(key==='reminder-pin'){
  b+=r(27,55,43,71,12,C.cream)+p('M47 53C36 41 31 49 43 56C57 65 67 50 55 51C45 52 46 64 58 67',C.orange,2)+face(48,79,30,md)+p('M40 103H58',C.ink,1.1)+ellipse(48,114,5.5,5.5,C.ink,1)+p('M48 110V114L48 118',C.ink,1.1);
 }else if(key==='step-path'){
  b+=face(47,72,32,md)+p('M27 119L52 110L77 100','#5B5346',1.3)+r(20,116,17,7,3.5,C.orange)+r(44,107,17,7,3.5,C.cream)+r(69,97,17,7,3.5,C.cream);
  if(v.kind==='done')b+=p('M26 110V103M23 106L26 103L29 106',C.orange,1.5);
 }else if(key==='spoken-mark'){
  b+=face(49,69,34,md)+fill('M20 96Q33 89 48 98Q63 89 79 96V121Q62 115 49 123Q34 115 20 121Z',C.cream)+p('M49 100V118',C.ink,1.2)+p('M27 102H39M58 102H70M27 109H39M58 109H70',C.ink,.9)+r(24+50*v.fraction,95,3,19,1.5,C.orange);
 }else if(key==='calm-pulse'){
  b+=face(49,76,36,'calm')+p(v.kind==='breathe-in'?'M19 123Q48 107 82 123':'M19 115Q48 132 82 115',C.cream,1.7)+arc(49,76,29,27,v.kind==='breathe-in'?.68:.28,C.orange,2)+dot(v.kind==='breathe-in'?30:76,v.kind==='breathe-in'?55:89,2.5);
 }
 return b;
}
function compact(d,v){const key=d.slug;let b='';
 if(['orbit','focus','music'].includes(key))b+=ellipse(25,18.335,18,15,'#5A5143',1)+arc(25,18.335,18,15,focus(v)?1-v.fraction:.35,C.orange,1.7);
 if(key==='calm-pulse')b+=arc(25,18.335,18,15,v.kind==='breathe-in'?.68:.28,C.orange,1.7);
 if(key==='ink-ripple')b+=fill('M7 18Q3 9 14 8Q23 2 34 10Q46 13 40 23Q35 34 22 28Q10 31 7 18Z',C.cream);
 if(key==='negative-space')b+=p('M7 17Q3 29 21 32Q40 33 44 19',C.cream,2.5);
 if(key==='kinetic-ribbon')b+=p('M7 27Q2 11 16 8Q36 1 43 17Q45 30 26 32',C.orange,1.8);
 b+=face(25,18.335,22,mood(v));
 if(key==='thought-drop')b+=dot(41,26,3,C.orange)+hand(37,27,9,'hold');
 if(key==='voice')b+=hand(40,22,9,'hold');
 if(key==='language-bridge')b+=p('M7 29Q25 36 43 28',C.orange,1.5);
 if(key==='reminder-pin')b+=p('M37 8Q32 2 40 4Q47 8 37 8',C.orange,1.4);
 if(key==='abstract-landscape')b+=p('M8 31Q24 25 43 31',C.cream,1.2)+dot(42,10,2.2);
 if(key==='spoken-mark')b+=fill('M37 25Q41 23 45 25V31Q41 29 37 31Z',C.cream)+p('M41 25V30',C.ink,.7);
 const x=202;
 if(focus(v))b+=v.kind==='paused'?g(183,18.335,.6,icon('pause',0,0,C.orange))+t(207,23,'12:48',12.5,C.cream,700,'text-anchor="middle"'):t(x,23,'12:48',12.5,C.cream,700,'text-anchor="middle"');
 else if(key==='language-bridge')b+=t(x,23,v.kind==='done'?'FR':'→ FR',12.5,C.cream,600,'text-anchor="middle"');
 else if(key==='reminder-pin')b+=t(x,23,'18:00',12.5,C.cream,700,'text-anchor="middle"');
 else if(key==='step-path')b+=v.kind==='done'?t(x,23,'1/3',13,C.cream,700,'text-anchor="middle"'):dot(x-7,18,1.5,C.quiet)+dot(x,18,2)+dot(x+7,18,1.5,C.quiet);
 else if(v.kind.startsWith('breathe'))b+=t(x,23,v.kind==='breathe-in'?'In':'Out',12.5,C.cream,700,'text-anchor="middle"');
 else if(v.kind==='done')b+=check(x,18,1);
 else if(v.kind==='think')b+=dot(x-7,18,1.5,C.quiet)+dot(x,18,2)+dot(x+7,18,1.5,C.quiet);
 else if(v.kind.includes('paused'))b+=icon('pause',x,18);
 else if(v.kind==='session')b+=t(x,23,'03:12',12.5,C.cream,700,'text-anchor="middle"');
 else{const hs=[6,11,17,9,5];hs.forEach((h,i)=>b+=r(190+i*5,18.3-h/2,2.5,h,1.25,i===2?C.orange:C.cream));}
 return b;
}
function minimal(d,v){if(focus(v))return t(22.5,24,'12m',13,C.cream,700,'text-anchor="middle"')+(v.kind==='paused'?g(22.5,7,.55,icon('pause',0,0,C.orange)):arc(22.5,18.335,18,15,1-v.fraction,C.orange,1.1));
 let b=face(14.5,18.335,21,mood(v));const x=34;
 if(d.slug==='step-path')b+=v.kind==='done'?t(x,23,'1',12,C.orange,700,'text-anchor="middle"'):dot(x-4,18,1,C.quiet)+dot(x,18,1.5)+dot(x+4,18,1,C.quiet);
 else if(v.kind==='done'&&d.slug==='language-bridge')b+=t(x,22,'FR',9,C.orange,700,'text-anchor="middle"');
 else if(v.kind==='done')b+=check(x,19,.7);
 else if(d.slug==='language-bridge')b+=t(x,22,'FR',9,C.orange,700,'text-anchor="middle"');
 else if(v.kind.startsWith('breathe'))b+=t(x,22,v.kind==='breathe-in'?'In':'Out',9,C.orange,700,'text-anchor="middle"');
 else if(v.kind.includes('paused'))b+=icon('pause',x,18,C.orange);
 else if(d.slug==='reminder-pin')b+=p('M30 22Q28 17 32 14Q38 15 37 20Q33 24 30 22Z',C.orange,1.3);
 else if(d.slug==='step-path')b+=t(x,23,'1',12,C.orange,700,'text-anchor="middle"');
 else if(v.kind==='think')b+=dot(x-4,18,1,C.quiet)+dot(x,18,1.5)+dot(x+4,18,1,C.quiet);
 else b+=r(29,16,2,5,1,C.quiet)+r(33,12,2,13,1,C.orange)+r(37,15,2,7,1,C.quiet);
 return b;
}
export function render(d,v,state){const [w,h]=state==='expanded'?[371,156]:state==='compact'?[230,36.67]:[45,36.67];let b=r(0,0,w,h,state==='expanded'?44:18.335,C.ink,'data-surface="continuous"');
 if(state!=='minimal')b+=state==='expanded'?r(122.83,8,125.34,29,14.5,'#0C0C0C','data-hardware="true"')+dot(235,22.5,3.5,'#171717'):r(52.33,4,125.34,28.67,14.3,'#0C0C0C','data-hardware="true"')+dot(164.5,18.335,3.5,'#171717');
 if(state==='minimal')return {w,h,b:b+'<g data-content="true">'+minimal(d,v)+'</g>'};
 if(state==='compact')return {w,h,b:b+'<g data-content="true">'+compact(d,v)+'</g>'};
 b+='<g data-content="true">';
 const tags={voice:'VOICE',focus:'FOCUS',music:'PLAYBACK',companion:'COMPANION',orbit:focus(v)?'FOCUS':'VOICE','ink-ripple':focus(v)?'FOCUS':'CAPTURE','negative-space':focus(v)?'FOCUS':'TRANSLATE','kinetic-ribbon':focus(v)?'FOCUS':'READ ALOUD',editorial:focus(v)?'FOCUS':'DRAFT REPLY','abstract-landscape':focus(v)?'FOCUS':'PLAN A WALK','thought-drop':'THOUGHT','language-bridge':'TRANSLATE','reminder-pin':'REMINDER','step-path':'TASK PLAN','spoken-mark':'READ ALOUD','calm-pulse':'BREATHE'};
 b+=t(22,29,tags[d.slug],9.5,C.quiet,600,'letter-spacing="1.1"')+t(349,29,v.meta||'',11.5,C.quiet,600,'text-anchor="end"');
 if(d.slug==='editorial'){
  b+=face(330,74,25,mood(v))+t(22,focus(v)?91:77,v.status,focus(v)?48:29,C.cream,500,'letter-spacing="-1.2"')+t(22,focus(v)?114:102,v.context,12.5,C.quiet,500);
  if(focus(v))b+=p('M22 136H229','#50493D',1.1)+p('M22 136H'+(22+207*(1-v.fraction)),C.orange,1.8);else b+=p('M22 123V137',C.orange,1.7)+t(34,134,'Thinking with you',10.5,C.quiet,500);
  b+=button(v,265,109);
 }else{
  b+=instrument(d,v)+t(105,76,v.status,focus(v)?32:21,C.cream,500,'letter-spacing="-.5"')+t(105,98,v.context,12.5,C.quiet,500);
  b+=d.slug==='music'?radioControls(v):button(v);
  if(d.slug==='voice'){[4,7,11,18,10,6,3].forEach((h,i)=>b+=r(214+i*5,126-h/2,2.2,h,1.1,i===3?C.orange:C.quiet));}
 }
 return {w,h,b:b+'</g>'};
}
export function phone(d,v,state){let b=r(0,0,411,870,58,'#C7BCA8')+r(2,2,407,866,56,'#090909')+r(9,9,393,852,50,C.cream);
 // Quiet wallpaper is presentation context, not an app screen or working interface.
 b+=fill('M10 694Q132 569 262 665Q343 723 401 665V811Q211 752 10 819Z','#E6D9C2')+p('M10 791Q115 724 204 773T401 766','#BAAB91',1.4)+dot(344,699,22,'#E4A278');
 if(state!=='expanded'){
  b+=t(34,42,'9:41',13,C.ink,600)+r(364,29,19,9,2,'none','stroke="#080808" stroke-width="1"')+r(366,31,14,5,1,C.ink)+r(384,32,1.5,3,.5,C.ink);
  [3,5,7,9].forEach((h,i)=>b+=r(332+i*4,38-h,2.7,h,.5,C.ink));b+=p('M351 32Q356 28 361 32M353 35Q356 32 359 35',C.ink,1.1)+dot(356,37,.7,C.ink);
 }
 const z=render(d,v,state);if(state==='minimal')b+=r(143,20,125,36.67,18.335,C.ink)+dot(254,38.335,3.5,'#171717')+g(279,20,1,z.b);else b+=g(9+(393-z.w)/2,20,1,z.b);
 return b+r(141,843,129,4.5,2.25,C.ink);
}
function wrap(x,y,s,width,size=23,c=C.muted,line=34){const words=s.split(' '),lines=[];let a='';for(const w of words){if((a+' '+w).trim().length>width){lines.push(a);a=w;}else a=(a+' '+w).trim();}if(a)lines.push(a);return lines.map((v,i)=>t(x,y+i*line,v,size,c,400)).join('');}
const boards=[],components=[];
for(const [idx,d] of catalog.entries()){
 let b=r(0,0,2560,1440,0,C.cream)+t(88,75,'DODDY / LITTLE INSTRUMENTS',19,C.ink,600,'class="caps"')+t(2472,75,'DYNAMIC ISLAND / '+d.id,17,C.muted,500,'text-anchor="end" class="caps"');
 b+=t(88,180,d.title,82,C.ink,500,'letter-spacing="-3"')+t(88,235,d.idea,27,C.muted,400)+p('M88 274H2472',C.rule,1);
 b+=t(88,321,'ON YOUR PHONE',16,C.muted,600,'class="caps"')+g(88,351,.9,phone(d,d.variants[0],'expanded'));
 b+=t(88,1175,'393 × 852pt screen reference',18,C.muted,400)+t(88,1210,'Phone 0.90× / expanded 2.25×',16,C.muted,400)+t(88,1240,'Compact & minimal 1.80×',16,C.muted,400);
 for(const [vi,v] of d.variants.entries()){
  const x=vi===0?650:1590;
  b+=t(x,321,v.label,17,C.ink,600,'class="caps"')+g(x,352,2.25,render(d,v,'expanded').b);
  b+=t(x,769,'COMPACT',15,C.muted,600,'class="caps"')+g(x,796,1.8,render(d,v,'compact').b)+t(x+553,769,'MINIMAL',15,C.muted,600,'class="caps"')+g(x+553,796,1.8,render(d,v,'minimal').b);
  b+=p('M'+x+' 919H'+(x+834.75),C.rule,1)+t(x,966,'THE MOMENT',15,C.muted,600,'class="caps"')+t(x,1014,v.status,31,C.ink,500)+t(x,1054,v.context,23,C.muted,400)+t(x,1101,'NEXT / '+actionLabel(v),18,C.ink,600,'class="caps"');
 }
 b+=p('M650 1172H2472',C.rule,1)+t(650,1217,'WHY THIS FEELS DODDY',15,C.muted,600,'class="caps"')+wrap(650,1260,d.rationale,112,23,C.ink,32)+t(2472,1382,'Static design / motion proposed / native behaviour untested',15,C.muted,400,'text-anchor="end"');
 const name=String(idx+1).padStart(2,'0')+'-'+d.slug;boards.push({...await save('01-boards',name,2560,1440,b,d.title),id:d.id,slug:d.slug});
 for(const [vi,v] of d.variants.entries())for(const state of ['compact','expanded','minimal']){const z=render(d,v,state),name=d.slug+'-'+vi+'-'+state+'.svg',cp='02-states/'+name,pp='03-phone-reference/'+name;fs.writeFileSync(path.join(out,cp),svg(z.w,z.h,z.b,d.title+' / '+v.label));fs.writeFileSync(path.join(out,pp),svg(411,870,phone(d,v,state),d.title+' / phone'));components.push({direction:d.slug,activity:String(vi),state,label:v.label,path:cp,phone:pp,width:z.w,height:z.h});}
}
let comparison=r(0,0,3200,2320,0,C.cream)+t(90,90,'DODDY / LITTLE INSTRUMENTS',24,C.ink,600,'class="caps"')+t(90,170,'Sixteen ways to make a moment Doddy.',65,C.ink,500,'letter-spacing="-2"')+t(90,223,'Purposeful graphics. Familiar character. A completely new composition.',27,C.muted,400);
for(const [i,d] of catalog.entries()){const x=90+(i%4)*765,y=280+Math.floor(i/4)*448,v=d.variants[d.id==='G'||d.id==='H'||d.id==='I'||d.id==='J'?1:0];comparison+=t(x,y+34,d.id+' / '+d.title,25,C.ink,600)+g(x,y+66,1.75,render(d,v,'expanded').b)+wrap(x,y+379,d.idea,51,19,C.muted,25);if(d.strong)comparison+=t(x+650,y+34,'CHOICE '+d.strong,14,C.orange,600,'text-anchor="end"');}
comparison+=p('M90 2100H3110',C.rule,1)+t(90,2153,'STRONGEST / Orbit · Thought Pocket · Language Bridge',25,C.ink,600)+t(90,2200,'System precision / Doddy character / action recognition',22,C.muted,400)+t(3110,2260,'Static mockups; art-direction preview is separate.',16,C.muted,400,'text-anchor="end"');
const comparisonFile=await save('04-review','Comparison-sheet',3200,2320,comparison,'Sixteen new designs');
let overview=r(0,0,3200,2180,0,C.cream)+t(90,100,'DODDY / COMPLETE REDESIGN',45,C.ink,500);for(const [i,b] of boards.entries()){const x=90+(i%4)*765,y=170+Math.floor(i/4)*480;overview+='<image href="data:image/png;base64,'+fs.readFileSync(path.join(out,b.png)).toString('base64')+'" x="'+x+'" y="'+y+'" width="650" height="365.625"/>'+t(x,y+405,b.id+' / '+b.title,24,C.ink,600);}const overviewFile=await save('04-review','All-16-boards',3200,2180,overview,'All sixteen new boards');
const manifest={version:'4.0',boards,components,catalog,review:{comparison:comparisonFile,overview:overviewFile},system:{board:[2560,1440],expanded:[371,156,44],compact:[230,36.67],minimal:[45,36.67],phone:[393,852],phoneScale:.9,expandedDetailScale:2.25,smallDetailScale:1.8},method:'New vector compositions following an AI art-direction exploration; deterministic final PNGs and editable SVGs.'};
fs.writeFileSync(path.join(out,'manifest.json'),JSON.stringify(manifest,null,2));fs.writeFileSync(path.join(out,'catalog.json'),JSON.stringify(catalog,null,2));
console.log(JSON.stringify({out,boards:boards.length,states:components.length}));

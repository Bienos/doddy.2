// Scripted design conversation. No model, microphone, browser storage or network.
const introQuestions=[
 {key:'name',label:'What to call you',question:'First things first. What should I call you?',hint:'A name or nickname is enough. You can skip this.',placeholder:'Your name or nickname',max:60},
 {key:'goal',label:'Useful help',question:'What would make me useful in your day?',hint:'Pick a starting point, or tell me in your own words.',choices:['Keep useful details','Help me follow through','Explain things clearly','A bit of everything'],placeholder:'Something you would like help with',max:240},
 {key:'style',label:'Answer style',question:'And how do you like your answers?',hint:'We can change this whenever you want.',choices:['Short and clear','More detail','Talk it through'],placeholder:'How you like explanations',max:120},
 {key:'language',label:'Language',question:'Which language feels natural to you?',hint:'Following your language is an option too.',choices:['Follow my language','English','Polski'],placeholder:'Your preferred language',max:120},
 {key:'humor',label:'Humor',question:'A little dry humor, or straight to the useful bit?',hint:'No jokes when something matters. You can always turn humor off.',choices:['A little, when it fits','Just the useful bit'],placeholder:'What feels comfortable',max:120},
 {key:'context',label:'Current focus',question:'Anything you would like a hand with these days?',hint:'A project, hobby or routine. Share only what would help; skip the rest.',placeholder:'For example: learning Italian or planning a move',max:400}
];
const sampleProfile={values:{name:'Alex',goal:'Help me follow through',style:'Short and clear',language:'Follow my language',humor:'A little, when it fits',context:'Making time for a small creative project'},source:'explicit_user_review',revision:1};
function fieldPurpose(k){return ({name:'For your greeting',goal:'For relevant starting points',style:'For the length and shape of replies',language:'For the language of replies',humor:'For optional personality',context:'For suggestions you ask for'})[k];}
function beginIntro(){state.introStep=0;state.profileDraft={...(state.profile?.values||{})};state.introMessages=[];state.introRevision=state.profile?.revision||0;navigate('intro-chat');}
function onboardingScreen(screen,{dark,inter,t}){
 const pref=inter?state.profile:sampleProfile;
 const values=pref?.values||{};
 if(screen==='welcome')return `<div class="mini-label">YOUR MATE IN YOUR POCKET · AI ASSISTANT</div><h1 class="welcome-title">Hey.<br>Let’s <span>talk.</span></h1><p class="lead welcome-copy">Let’s get to know each other a little. I can show you how I help, and you decide what I remember.</p><div class="first-hero">${art('approaching',dark)}<span>We can<br>start small.</span></div>${btn('Let’s get to know each other','begin-intro')}<button class="text-link capabilities-link" data-action="capabilities">Show me what you can do</button><button class="skip-intro" data-action="skip-intro">Start without the chat ${icon('arrow')}</button><p class="input-hint">Every question is optional. You’ll review anything you want me to keep.</p>`;
 if(screen==='intro-chat'){
  const step=inter?state.introStep:2,q=introQuestions[Math.min(step,5)];
  const messages=inter?state.introMessages.slice(-2):[{role:'user',text:'Help me follow through'},{role:'doddy',text:'Useful. We can start with a clear next step.'}];
  return `<div class="intro-presence">${art('listening',dark)}<div><span class="speaker">Doddy</span><p>A little at a time.</p></div></div><p class="intro-draft-status">Getting to know you · nothing saved yet</p>${state.showCapabilities?`<div class="capability-note"><b>Here’s where I can help.</b><p>Keep and find useful details. Explore an idea together when AI is connected. Prepare a next step for your review.</p><small>This demo has local fictional notes and scripted replies; live AI and actions come later.</small></div>`:''}<div class="intro-history">${messages.map(m=>m.role==='user'?`<div class="intro-user">${esc(m.text)}</div>`:`<p class="intro-ack">${esc(m.text)}</p>`).join('')}</div><h1 class="intro-question">${esc(q.question)}</h1><p class="intro-hint">${esc(q.hint)}</p>${q.choices?`<div class="intro-choices">${q.choices.map(c=>`<button data-intro-choice="${esc(c)}">${esc(c)}</button>`).join('')}</div>`:''}<form data-form="intro-answer"><label class="input-label" for="intro-answer">${q.choices?'Or in your own words':'Your reply'}</label><div class="intro-composer"><input id="intro-answer" aria-label="Your answer" placeholder="${esc(q.placeholder)}" maxlength="${q.max}" value="${esc(inter?state.profileDraft[q.key]||'':'')}" autocomplete="off"><button aria-label="Continue">${icon('arrow')}</button></div></form><div class="intro-bottom"><button class="text-link" data-action="skip-question">Skip this one</button><button class="text-link" data-action="review-profile">Review & finish</button></div><p class="intro-progress">${step+1} of ${introQuestions.length} optional questions · your pace</p>`;
 }
 if(screen==='profile-review'||screen==='profile-preferences'){
  const reviewing=screen==='profile-review',draft=inter?(reviewing?state.profileDraft:values):sampleProfile.values;
  const rows=introQuestions.filter(q=>draft[q.key]?.trim());
  return `<div class="mini-label">${reviewing?'ONLY WHAT YOU CHOOSE':'YOUR PERSONALIZATION'}</div><h1 class="hand-title">${reviewing?'Here’s what<br>I picked <span>up.</span>':'What I know.<br><span>Your call.</span>'}</h1><p class="lead">${reviewing?'Keep what feels useful. Change or remove anything before saving.':'These are the preferences you chose to save. You can change or forget them.'}</p><div class="profile-list">${rows.length?rows.map(q=>`<div class="profile-field"><div><label for="pref-${q.key}">${q.label}</label><small>${fieldPurpose(q.key)}</small></div>${reviewing?`<input id="pref-${q.key}" data-pref-key="${q.key}" maxlength="${q.max}" value="${esc(draft[q.key])}" aria-label="${q.label}">`:`<p>${esc(draft[q.key])}</p>`}${reviewing?`<button class="round-button remove-pref" data-action="remove-pref" data-id="${q.key}" aria-label="Remove ${q.label}">${icon('close')}</button>`:''}</div>`).join(''):'<p class="lead">Nothing saved about you yet. You can still use Doddy.</p>'}</div>${reviewing?`<p class="profile-consent">These preferences guide replies and suggestions. The rest of this introductory chat won’t be kept.</p>${btn(rows.length?'Save these preferences':'Continue without preferences',rows.length?'approve-profile':'skip-intro')}<button class="text-link" data-action="begin-intro">Back to the chat</button><button class="skip-intro" data-action="skip-intro">Continue without saving ${icon('arrow')}</button>`:`${btn('Change my preferences','begin-intro','secondary','edit')}${rows.length?btn('Forget my personalization','forget-profile-confirm','secondary','close'):''}<p class="input-hint">${pref?'Saved after your review · not inferred from your phone':'No identity or private phone data has been read.'}</p>`}`;
 }
 if(screen==='personal-home'){
  const events=inter?state.activity:[{kind:'proposal',title:'A little room for your project',body:'Pick one small step to try this week.',status:'Ready for your review'}];
  const mems=inter?state.memories:[demo];
  const name=values.name?esc(values.name):'';
  return `<div class="personal-greeting"><div><div class="mini-label">YOUR CORNER</div><h1 class="personal-title">${name?'Hey, '+name+'.':'Hey again.'}</h1></div>${art('memory-card',dark)}</div><p class="lead personal-lead">${values.style==='Short and clear'?'Keep it simple. One useful thing at a time.':'A little help, with room for your day.'}</p><div class="presence-status"><span></span>Ready when you are. ${inter&&state.saving?'A demo write is pending.':'Nothing running in the background.'}</div><div class="home-section-title"><h2>${events.length?'On your side':'A place to begin'}</h2><span>${events.length?'UPDATES':'NO TASKS YET'}</span></div>${events.length?events.slice(0,2).map(a=>`<button class="activity-row" data-action="${a.kind==='memory'?'detail':'activity-detail'}" ${a.memoryID?`data-id="${esc(a.memoryID)}"`:''}><span class="activity-symbol">${icon(a.kind==='memory'?'memory':'edit')}</span><div><span class="activity-state">${esc(a.status)}</span><h3>${esc(a.title)}</h3><p>${esc(a.body)}</p></div><span class="activity-arrow">↗</span></button>`).join(''):`<div class="home-empty"><p>A little room for what matters.<br>Let’s pick something useful.</p>${btn(values.goal==='Keep useful details'?'Keep your first detail':'Prepare a small next step',values.goal==='Keep useful details'?'capture':'prepare-step','secondary','plus')}</div>`}${values.context?`<div class="focus-line"><span class="mini-label">YOUR CURRENT FOCUS</span><p>${esc(values.context)}</p><button class="text-link" data-action="prepare-step">Find a first step ↗</button></div>`:''}<div class="home-section-title"><h2>Useful details</h2><button class="text-link" data-action="recall">${mems.length?'View all':'Open memories'}</button></div>${mems.length?`<button class="home-memory" data-action="detail" data-id="${esc(mems[mems.length-1].id)}">${icon('memory')}<span>${esc(mems[mems.length-1].text)}</span><b>↗</b></button>`:`<p class="personal-empty-copy">Nothing kept yet. You choose the first detail.</p>`}`;
 }
 if(screen==='activity-detail'){
  const a=inter?state.activity.find(x=>x.kind==='proposal'):null;
  return `<div class="mini-label">A DRAFT, NOT A COMPLETED TASK</div><h1 class="hand-title">One small<br><span>next step.</span></h1><p class="lead">${a?esc(a.body):'Choose one action small enough to try today.'}</p><div class="proposal-detail"><span class="activity-state">Ready for your review</span><h2>${a?esc(a.title):'Your starting point'}</h2><p>Write down what “a useful first try” would look like. Keep it small enough to start.</p></div><div class="callout"><b>Nothing has been sent or scheduled.</b><p>This is a scripted demo draft. You decide whether to keep it as a detail.</p></div>${btn('Keep this as a detail','keep-step','primary','memory')}${btn('Leave it for now','home','secondary')}`;
 }
 return '';
}
function answerIntro(value,skip=false){
 const q=introQuestions[state.introStep];if(!q)return;
 const val=value.trim().slice(0,q.max);
 if(!skip&&!val)return;
 if(skip)delete state.profileDraft[q.key];else state.profileDraft[q.key]=val;
 const ack=skip?'No problem. We can leave that out.':q.key==='name'?'Nice to meet you, '+val+'.':q.key==='goal'?'Useful. We can start with a clear next step.':q.key==='style'?'That helps. You’ll be able to change it.':q.key==='language'?'Got it. You stay in control of the language.':q.key==='humor'?'Understood. Useful first, always.':'That gives us a starting point. Let’s check what you want to keep.';
 state.introMessages.push({role:'user',text:skip?'Skip this one':val},{role:'doddy',text:ack});state.introStep++;
 trace('Optional introduction answer '+(skip?'skipped.':'drafted. Not saved.'));
 navigate(state.introStep>=introQuestions.length?'profile-review':'intro-chat');
}
async function onboardingAction(action,id){
 if(action==='begin-intro'){state.showCapabilities=false;beginIntro();return true;}
 if(action==='capabilities'){beginIntro();state.showCapabilities=true;renderDevice();return true;}
 if(action==='skip-question'){answerIntro('',true);return true;}
 if(action==='review-profile'){navigate('profile-review');return true;}
 if(action==='remove-pref'){delete state.profileDraft[id];renderDevice();return true;}
 if(action==='approve-profile'){
  const values={};for(const q of introQuestions){const v=String(state.profileDraft[q.key]||'').trim().slice(0,q.max);if(v)values[q.key]=v;}
  state.profile=Object.keys(values).length?{values,source:'explicit_user_review',revision:state.introRevision+1,approvedAt:new Date().toISOString()}:null;
  state.onboardingDone=true;state.introMessages=[];state.profileDraft={};state.showCapabilities=false;
  if(values.humor)state.humor=values.humor!=='Just the useful bit';
  trace('User reviewed and approved '+Object.keys(values).length+' personalization fields. Raw introduction discarded.');navigate('home');return true;
 }
 if(action==='skip-intro'){state.onboardingDone=true;state.profileDraft={};state.introMessages=[];state.showCapabilities=false;trace(state.profile?'New draft discarded. Existing approved preferences retained.':'Introduction skipped. No personalization saved.');navigate('home');return true;}
 if(action==='profile-preferences'){navigate('profile-preferences');return true;}
 if(action==='forget-profile-confirm'){state.forgetProfilePending=true;navigate('profile-preferences');const body=$('#prototype-device .app-body');body.insertAdjacentHTML('beforeend',`<div class="callout"><b>Forget these preferences?</b><p>Your saved details remain. Only personalization will be removed.</p></div>${btn('Yes, forget personalization','forget-profile','primary','close')}`);body.scrollTop=body.scrollHeight;return true;}
 if(action==='forget-profile'){state.profile=null;state.humor=true;state.profileDraft={};state.introMessages=[];state.onboardingDone=true;state.activity=state.activity.filter(a=>a.kind!=='proposal');trace('Personalization forgotten. Saved details retained.');navigate('home');return true;}
 if(action==='prepare-step'){
  const context=state.profile?.values.context;
  state.activity=state.activity.filter(a=>a.kind!=='proposal');
  state.activity.unshift({kind:'proposal',title:context?'A first step for your current focus':'A small first step',body:context?'Start with one small, clear action for: '+context:'Choose one useful thing to try today.',status:'Ready for your review'});
  trace('Scripted draft prepared at user request. Nothing executed or scheduled.');navigate('activity-detail');return true;
 }
 if(action==='activity-detail'){navigate('activity-detail');return true;}
 if(action==='keep-step'){const a=state.activity.find(x=>x.kind==='proposal');state.writeMode='new';state.draft=a?a.title+'. '+a.body:'One small, useful next step.';navigate('capture');return true;}
 return false;
}
document.addEventListener('click',e=>{const b=e.target.closest('#prototype-device [data-intro-choice]');if(b){e.preventDefault();answerIntro(b.dataset.introChoice);}});
document.addEventListener('submit',e=>{if(e.target.matches('#prototype-device [data-form="intro-answer"]')){e.preventDefault();answerIntro(e.target.querySelector('input').value);}});
document.addEventListener('input',e=>{if(e.target.closest('#prototype-device')&&e.target.dataset.prefKey)state.profileDraft[e.target.dataset.prefKey]=e.target.value;});

/* Doddy v2 engine: constants, physics helpers, phone markup and CSS.
   Units: iPhone points on a 390 × 844 canvas. Time: ms of simulation time. */
(function (global) {
  'use strict';
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smoothstep = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };
  const hyp = (x, y) => Math.sqrt(x * x + y * y);
  const fmt = (v, d = 0) => (Math.abs(v) < 0.5 && d === 0 ? '0' : Number(v).toFixed(d));

  /* SwiftUI-style spring: response (s), dampingFraction. */
  class Spring {
    constructor(x = 0, response = 0.3, damping = 0.8) { this.x = x; this.v = 0; this.target = x; this.force = 0; this.set(response, damping); }
    set(response, damping) { this.response = response; this.damping = damping; const w = (2 * Math.PI) / response; this.k = w * w; this.c = 2 * damping * w; return this; }
    step(dt) {
      if (dt <= 0) return;
      const n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n;
      for (let i = 0; i < n; i++) { const a = -this.k * (this.x - this.target) - this.c * this.v + this.force; this.v += a * h; this.x += this.v * h; }
    }
    snap(x) { this.x = x; this.v = 0; this.target = x; }
    get resting() { return Math.abs(this.x - this.target) < 0.01 && Math.abs(this.v) < 0.05; }
  }
  /* Spring stepped ahead dt seconds with the same integrator (the engine drives these surfaces, so it can look ahead). */
  function springAhead(sp, dt) {
    if (dt <= 0) return sp.x;
    let x = sp.x, v = sp.v; const n = Math.max(1, Math.ceil(dt / 0.004)), h = dt / n;
    for (let i = 0; i < n; i++) { const a = -sp.k * (x - sp.target) - sp.c * v + sp.force; v += a * h; x += v * h; }
    return x;
  }
  function mulberry32(a) { return function () { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

  const L = {
    W: 390, H: 844,
    rail: 724,
    tabX: { home: 73, talk: 195, memories: 317 },
    stage: { y: 470, x0: 125, x1: 265, x: 195 },
    stripTop: 652, panelBottom: 708, panelOpenTop: 380, panelHiddenTop: 716,
    composerH: 44, composerBottomNoStrip: 704, composerBottomStrip: 640,
    kbH: 300,
    listTop: 208, listBottomBase: 724, listInset: 108,
    ruleX: 330,
    detailTop: 84, detailSourceY: 300, detailX: 330,
    draftX: 250,
    sendHit: { x0: 332, x1: 376 }, sendHitMic: { x0: 288, x1: 332 }, micHit: { x0: 332, x1: 376 },
    reviewHit: { x0: 298, x1: 354 },
    zoneW: 48, zoneH: 108,
  };
  const M = {
    anticipation: 80, anticipationFromLanding: 40, anticipationFromSit: 140,
    flight: (D, dy) => clamp(220 + 0.4 * D + 0.2 * Math.abs(dy), 260, 420),
    apex: (D, dy) => (dy > 40 ? clamp(6 + 0.04 * D, 10, 18) : clamp(12 + 0.08 * D, 16, 32)),
    retargetFlight: (D) => clamp(180 + 0.5 * D, 200, 360),
    maxAirborne: 520, contact: 60, settle: 280,
    calm: { changes: 3, window: 900, quiet: 350 },
    fadeOut: 120, fadeIn: 180, shuffleOut: 90, shuffleIn: 120,
    uiFade: 120,
    step: 110, stepSettle: 120,
    hold: 450, tapSlop: 10,
    lily: { slow: 300, settleSpeed: 150, settleFor: 200, gap: 1200, look: 150 },
  };
  function liftFor(p0, p1, A) {
    const c = p1.y - p0.y, m = Math.min(p0.y, p1.y), K = p0.y - m + A;
    return ((c + 2 * K) + 2 * Math.sqrt(Math.max(0, K * (K + c)))) / 4;
  }
  function flightPoint(f, s) {
    const s2 = s * s, s3 = s2 * s;
    const h00 = 2 * s3 - 3 * s2 + 1, h10 = s3 - 2 * s2 + s, h01 = -2 * s3 + 3 * s2, h11 = s3 - s2;
    return {
      x: h00 * f.p0.x + h10 * f.m0.x + h01 * f.p1.x + h11 * f.m1.x,
      y: h00 * f.p0.y + h10 * f.m0.y + h01 * f.p1.y + h11 * f.m1.y - 4 * f.h * s * (1 - s),
    };
  }
  function flightVelocity(f, s) {
    const s2 = s * s;
    const d00 = 6 * s2 - 6 * s, d10 = 3 * s2 - 4 * s + 1, d01 = -6 * s2 + 6 * s, d11 = 3 * s2 - 2 * s;
    const T = f.T / 1000;
    return {
      x: (d00 * f.p0.x + d10 * f.m0.x + d01 * f.p1.x + d11 * f.m1.x) / T,
      y: (d00 * f.p0.y + d10 * f.m0.y + d01 * f.p1.y + d11 * f.m1.y - 4 * f.h * (1 - 2 * s)) / T,
    };
  }

  /* Memories: every item keeps the user's exact words, with a detail page behind "View original note". */
  const ITEMS = [
    { title: 'Mateusz’s coffee', body: '“Flat white, oat milk.”', meta: 'From your note · 12 Oct', lines: 1, words: '“Flat white, oat milk. Extra hot when it’s cold out.”', source: 'Your note · 12 October' },
    { title: 'Ola’s birthday', body: '“24 November. She loves tulips.”', meta: 'From a chat · 3 Oct', lines: 1, words: '“Ola’s birthday is 24 November. She loves tulips, not roses.”', source: 'Chat with Doddy · 3 October' },
    { title: 'Gym days', body: '“Tuesday and Thursday, 7:30.”', meta: 'From a chat · 1 Oct', lines: 1, words: '“I go to the gym Tuesday and Thursday at 7:30.”', source: 'Chat with Doddy · 1 October' },
    { title: 'Car service', body: '“Book the service before the winter tyres go on.”', meta: 'From a voice note · 29 Sep', lines: 2, words: '“Book the service before the winter tyres go on. Ask about the brakes.”', source: 'Voice note · 29 September' },
    { title: 'Mum’s flight', body: '“Saturday 14:20, terminal A.”', meta: 'From a chat · 27 Sep', lines: 1, words: '“Mum lands Saturday at 14:20, terminal A. Pick her up.”', source: 'Chat with Doddy · 27 September' },
    { title: 'Landlord', body: '“Ask about the radiator in the bedroom.”', meta: 'From a voice note · 22 Sep', lines: 2, words: '“Ask the landlord about the radiator in the bedroom. It clicks.”', source: 'Voice note · 22 September' },
    { title: 'Book club', body: '“Finish chapter 9 by Wednesday.”', meta: 'From your note · 20 Sep', lines: 1, words: '“Finish chapter 9 by Wednesday. Bring the cake this time.”', source: 'Your note · 20 September' },
    { title: 'Dentist', body: '“Check-up is due in November.”', meta: 'From a chat · 18 Sep', lines: 1, words: '“My dentist check-up is due in November.”', source: 'Chat with Doddy · 18 September' },
    { title: 'Kasia’s address', body: '“Prosta 12/4, Wrocław.”', meta: 'From a message · 15 Sep', lines: 1, words: '“Kasia lives at Prosta 12/4, Wrocław. Third floor.”', source: 'Message · 15 September' },
    { title: 'Monstera', body: '“Water it every Sunday.”', meta: 'From your note · 10 Sep', lines: 1, words: '“Water the monstera every Sunday. Not more.”', source: 'Your note · 10 September' },
    { title: 'Office Wi-Fi', body: '“The password is on the fridge.”', meta: 'From a chat · 6 Sep', lines: 1, words: '“Office Wi-Fi: studio-5G. The password is on the fridge.”', source: 'Chat with Doddy · 6 September' },
    { title: 'Passport', body: '“Renew it before March.”', meta: 'From a chat · 2 Sep', lines: 1, words: '“Renew my passport before March.”', source: 'Chat with Doddy · 2 September' },
  ];
  const SAVED_ITEM = { title: 'Coffee with Mateusz', body: '“Fridays, after work.”', meta: 'From this chat · today', lines: 1, words: '“We have coffee on Fridays, after work.”', source: 'Chat with Doddy · today' };
  const itemHeight = (it) => 104 + 22 * it.lines;

  const CSS = `
.dp-phone, .dp-phone * { box-sizing: border-box; }
.dp-phone {
  --d-bg: #F3EDDF; --d-surface: #EDE4D7; --d-rule: #D6D0C2; --d-ink: #0B0B0B; --d-muted: #6B655B; --d-accent: #A64B19; --d-key: #D9D0C2;
  position: relative; width: 390px; height: 844px; border-radius: 52px; overflow: hidden; background: var(--d-bg); color: var(--d-ink);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", "Helvetica Neue", "Segoe UI", Arial, sans-serif;
  -webkit-font-smoothing: antialiased; isolation: isolate; color-scheme: light; line-height: 1.3; font-size: 16px; text-align: left;
  user-select: none; -webkit-user-select: none; touch-action: none;
}
.dp-phone p { margin: 0; }
.dp-phone button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; -webkit-tap-highlight-color: transparent; }
.dp-phone button:focus-visible, .dp-phone [tabindex]:focus-visible { outline: 2px solid var(--d-accent); outline-offset: 2px; border-radius: 8px; }
.dp-abs { position: absolute; }
.dp-sb { position: absolute; left: 0; right: 0; top: 0; height: 54px; z-index: 62; pointer-events: none; }
.dp-time { position: absolute; left: 0; width: 132px; top: 17px; text-align: center; font-weight: 600; font-size: 16.5px; letter-spacing: -0.01em; }
.dp-island { position: absolute; left: 132px; top: 11px; width: 126px; height: 37px; border-radius: 19px; background: #000; }
.dp-micdot { position: absolute; left: 266px; top: 23px; width: 7px; height: 7px; border-radius: 50%; background: #FF9F0A; opacity: 0; }
.dp-sbicons { position: absolute; right: 26px; top: 19px; width: 78px; height: 14px; }
.dp-appbar { position: absolute; left: 0; right: 0; top: 54px; height: 32px; z-index: 30; pointer-events: none; }
.dp-wordmark { position: absolute; left: 24px; top: 4px; font-weight: 700; font-size: 23px; letter-spacing: -0.045em; line-height: 1; }
.dp-dot { color: var(--d-accent); }
.dp-menu { position: absolute; right: 14px; top: -2px; width: 44px; height: 36px; display: flex; gap: 4px; align-items: center; justify-content: center; }
.dp-menu i { width: 5px; height: 5px; border-radius: 50%; background: var(--d-ink); display: block; }
.dp-screen { position: absolute; inset: 0; z-index: 10; }
.dp-stage { position: absolute; left: 125px; top: 470px; width: 140px; height: 1px; background: var(--d-rule); }
.dp-talkhit { position: absolute; border-radius: 24px !important; }
.dp-home-h { position: absolute; left: 0; right: 0; top: 504px; text-align: center; font-size: 28px; font-weight: 600; letter-spacing: -0.02em; }
.dp-home-sub { position: absolute; left: 0; right: 0; top: 546px; text-align: center; font-size: 15px; color: var(--d-muted); }
.dp-voice { position: absolute; left: 50%; top: 588px; transform: translateX(-50%); height: 44px; padding: 0 18px 0 14px !important; border-radius: 22px; background: var(--d-ink) !important; color: #fff !important; display: flex; align-items: center; gap: 10px; font-size: 15px; font-weight: 500; opacity: 0; }
.dp-voice i { display: block; width: 12px; height: 12px; border-radius: 3px; background: #fff; }
.dp-voice b { display: flex; gap: 3px; align-items: center; height: 18px; }
.dp-voice b span { display: block; width: 3px; border-radius: 2px; background: #fff; }
.dp-thread { position: absolute; left: 16px; right: 16px; top: 96px; bottom: 360px; margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; justify-content: flex-end; gap: 14px; overflow: hidden; -webkit-mask-image: linear-gradient(to bottom, transparent 0, #000 28px); mask-image: linear-gradient(to bottom, transparent 0, #000 28px); }
.dp-thread li { flex: none; font-size: 16px; line-height: 1.35; }
.dp-me { align-self: flex-end; max-width: 76%; background: var(--d-surface); border-radius: 18px; padding: 10px 14px; }
.dp-doddy { align-self: flex-start; max-width: 80%; padding: 2px 0; }
.dp-err { align-self: flex-start; max-width: 80%; padding: 2px 0; color: #8A2A1E; }
.dp-sys { align-self: center; font-size: 13px !important; color: var(--d-muted); }
.dp-composer { position: absolute; left: 16px; right: 16px; top: 660px; height: 44px; border-radius: 22px; background: var(--d-surface); }
.dp-composer.is-focused { box-shadow: inset 0 0 0 1px var(--d-rule); }
.dp-composer-text { position: absolute; left: 16px; right: 52px; top: 0; line-height: 44px; font-size: 16px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.dp-composer-text.is-placeholder { color: var(--d-muted); }
.dp-send { position: absolute; right: 6px; top: 6px; width: 32px; height: 32px; border-radius: 50% !important; background: var(--d-ink) !important; color: #fff !important; display: grid; place-items: center; }
.dp-send svg, .dp-mic svg { width: 16px; height: 16px; }
.dp-mic { position: absolute; right: 8px; top: 8px; width: 28px; height: 28px; border-radius: 50% !important; display: grid; place-items: center; color: var(--d-ink) !important; opacity: 0; }
.dp-mem-title { position: absolute; left: 24px; top: 100px; font-size: 32px; font-weight: 700; letter-spacing: -0.03em; }
.dp-search { position: absolute; left: 16px; right: 16px; top: 152px; height: 44px; border-radius: 12px; background: var(--d-surface); color: var(--d-muted); padding: 0 16px; line-height: 44px; font-size: 16px; }
.dp-list { position: absolute; left: 0; right: 0; top: 208px; height: 516px; overflow: hidden; }
.dp-list-c { position: absolute; left: 0; right: 0; top: 0; }
.dp-item { position: absolute; left: 0; right: 0; }
.dp-item .t { position: absolute; left: 24px; top: 14px; max-width: 264px; font-size: 19px; font-weight: 600; letter-spacing: -0.01em; white-space: nowrap; }
.dp-item .b { position: absolute; left: 24px; top: 42px; width: 264px; font-size: 16px; line-height: 22px; }
.dp-item .m { position: absolute; left: 24px; font-size: 13px; color: var(--d-muted); white-space: nowrap; }
.dp-item .l { position: absolute; left: 24px; height: 30px; line-height: 30px; font-size: 16px; color: var(--d-accent); white-space: nowrap; }
.dp-rule { position: absolute; left: 24px; right: 24px; height: 1px; background: var(--d-rule); }
.dp-detail { position: absolute; left: 0; top: 84px; width: 390px; height: 640px; z-index: 15; background: var(--d-bg); box-shadow: -10px 0 24px -14px rgba(40,30,20,.35); transform: translateX(390px); visibility: hidden; }
.dp-back { position: absolute; left: 12px; top: 4px; height: 36px; padding: 0 8px !important; color: var(--d-accent) !important; font-size: 17px; }
.dp-detail-k { position: absolute; left: 24px; top: 62px; font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--d-accent); }
.dp-detail-h { position: absolute; left: 24px; top: 84px; font-size: 26px; font-weight: 600; letter-spacing: -0.02em; white-space: nowrap; }
.dp-detail-b { position: absolute; left: 24px; top: 126px; width: 250px; font-size: 16px; line-height: 1.4; }
.dp-source { position: absolute; left: 16px; right: 16px; top: 216px; height: 84px; border-radius: 14px; background: var(--d-surface); padding: 16px; }
.dp-source-k { font-size: 11px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--d-muted); display: inline-block; }
.dp-source-b { font-size: 16px; margin-top: 6px !important; display: inline-block; }
.dp-scrim { position: absolute; inset: 0; z-index: 18; background: var(--d-bg); opacity: 0; visibility: hidden; pointer-events: none; }
.dp-panel { position: absolute; left: 16px; right: 16px; top: 652px; height: 56px; z-index: 20; background: var(--d-surface); border-radius: 16px; box-shadow: 0 -10px 30px -22px rgba(40,30,20,.45); overflow: hidden; display: none; }
.dp-panel-strip { position: absolute; left: 0; right: 0; top: 0; height: 56px; font-size: 15px; }
.dp-panel-strip span { position: absolute; left: 20px; top: 0; line-height: 56px; }
.dp-panel-strip b { position: absolute; right: 16px; top: 0; line-height: 56px; font-weight: 500; color: var(--d-accent); }
.dp-panel-open { position: absolute; left: 0; right: 0; top: 0; height: 328px; }
.dp-grab { position: absolute; left: 50%; top: 4px; width: 64px; height: 22px; margin-left: -32px; display: grid; place-items: center; }
.dp-grab i { display: block; width: 36px; height: 5px; border-radius: 3px; background: var(--d-rule); }
.dp-p-h { position: absolute; left: 20px; top: 34px; font-size: 20px; font-weight: 600; letter-spacing: -0.015em; }
.dp-p-meta { position: absolute; left: 20px; top: 64px; font-size: 13px; color: var(--d-muted); }
.dp-p-draft { position: absolute; left: 20px; right: 20px; top: 92px; font-size: 19px; line-height: 1.32; }
.dp-reviewsend { position: absolute; left: 16px; right: 16px; top: 168px; height: 50px; border-radius: 25px !important; background: var(--d-ink) !important; color: #fff !important; font-size: 16px; font-weight: 500; }
.dp-p-foot { position: absolute; left: 0; right: 0; top: 228px; text-align: center; font-size: 13px; color: var(--d-muted); }
.dp-later { position: absolute; left: 50%; top: 254px; width: 160px; height: 40px; margin-left: -80px; color: var(--d-accent) !important; font-size: 15px; }
.dp-overlay { position: absolute; left: 0; top: 0; width: 390px; height: 844px; pointer-events: none; z-index: 12; overflow: visible; }
.dp-tabbar { position: absolute; left: 0; right: 0; top: 724px; height: 120px; z-index: 40; background: var(--d-bg); display: grid; grid-template-columns: 1fr 1fr 1fr; align-items: start; padding: 0 16px; }
.dp-railline { position: absolute; left: 0; right: 0; top: 724px; height: 1px; background: var(--d-rule); z-index: 41; }
.dp-tab { height: 64px; font-size: 15px; position: relative; color: var(--d-muted) !important; }
.dp-tab span { position: relative; z-index: 1; }
.dp-tab::before { content: ""; position: absolute; left: 50%; top: 15px; width: 92px; height: 34px; margin-left: -46px; border-radius: 17px; background: var(--d-surface); opacity: 0; }
.dp-tab.is-on { color: var(--d-ink) !important; font-weight: 600; }
.dp-tab.is-on::before { opacity: 1; }
.dp-tab.is-on::after { content: ""; position: absolute; left: 50%; bottom: 4px; width: 4px; height: 4px; margin-left: -2px; border-radius: 50%; background: var(--d-accent); }
.dp-badge { position: absolute; top: 18px; right: 22px; width: 7px; height: 7px; border-radius: 50%; background: var(--d-accent); display: none; }
.dp-keyboard { position: absolute; left: 0; right: 0; top: 544px; height: 300px; z-index: 50; background: var(--d-key); padding: 10px 4px 0; display: grid; gap: 10px; align-content: start; transform: translateY(300px); }
.dp-kr { display: flex; justify-content: center; gap: 6px; }
.dp-kr span { width: 32px; height: 44px; border-radius: 6px; background: #FBF8F2; box-shadow: 0 1px 0 rgba(0,0,0,.18); font-size: 18px; display: grid; place-items: center; }
.dp-kr .dp-space { width: 200px; font-size: 15px; }
.dp-kr .dp-done { width: 88px; font-size: 15px; background: #BDB2A2; }
.dp-banner { position: absolute; left: 12px; right: 12px; top: 58px; height: 44px; z-index: 55; border-radius: 14px; background: #2A2622; color: #fff; font-size: 14px; display: flex; align-items: center; gap: 10px; padding: 0 16px; transform: translateY(-120px); }
.dp-banner i { width: 8px; height: 8px; border-radius: 50%; background: #E2A645; display: block; flex: none; }
.dp-toast { position: absolute; left: 0; top: 0; height: 30px; z-index: 56; border-radius: 15px; background: rgba(20,18,16,.92); color: #fff; font-size: 13.5px; line-height: 30px; padding: 0 14px; white-space: nowrap; opacity: 0; }
.dp-sheet { position: absolute; left: 0; right: 0; top: 54px; height: 790px; z-index: 70; background: #F2F2F7; border-radius: 12px 12px 0 0; transform: translateY(800px); font-family: -apple-system, "SF Pro Text", "Inter", sans-serif; }
.dp-sheet-dim { position: absolute; inset: 0; z-index: 69; background: #000; opacity: 0; pointer-events: none; }
.dp-sheet .h { position: absolute; left: 0; right: 0; top: 14px; text-align: center; font-weight: 600; font-size: 17px; }
.dp-sheet .c { position: absolute; left: 16px; top: 14px; color: #007AFF !important; font-size: 17px; line-height: 1.3; }
.dp-sheet .to { position: absolute; left: 0; right: 0; top: 52px; height: 44px; border-bottom: 0.5px solid #C6C6C8; padding: 0 16px; line-height: 44px; font-size: 16px; color: #8E8E93; background: #fff; }
.dp-sheet .to b { color: #007AFF; font-weight: 400; }
.dp-sheet .fld { position: absolute; left: 12px; right: 12px; bottom: 360px; min-height: 36px; border-radius: 18px; border: 1px solid #C6C6C8; background: #fff; padding: 7px 44px 7px 14px; font-size: 16px; line-height: 1.3; color: #000; }
.dp-sheet .snd { position: absolute; right: 5px; bottom: 4px; width: 28px; height: 28px; border-radius: 50% !important; background: #007AFF !important; display: grid; place-items: center; }
.dp-sheet .snd svg { width: 14px; height: 14px; }
.dp-sheet .note { position: absolute; left: 0; right: 0; top: 116px; text-align: center; font-size: 12px; color: #8E8E93; }
.dp-touch { position: absolute; left: 0; top: 0; width: 44px; height: 44px; margin: -22px 0 0 -22px; border-radius: 50%; background: rgba(11,11,11,.16); box-shadow: 0 0 0 1.5px rgba(255,255,255,.75), 0 1px 6px rgba(0,0,0,.18); z-index: 90; opacity: 0; pointer-events: none; }
.dp-sim { position: absolute; left: 20px; right: 20px; top: 802px; height: 14px; z-index: 89; font: 500 9.5px/14px "IBM Plex Mono", "DejaVu Sans Mono", ui-monospace, monospace; letter-spacing: 0.06em; color: rgba(11,11,11,.42); text-transform: uppercase; pointer-events: none; white-space: nowrap; display: flex; justify-content: space-between; }
.dp-anno { position: absolute; left: 0; top: 0; width: 390px; height: 844px; z-index: 95; pointer-events: none; display: none; overflow: visible; }
.dp-homeind { position: absolute; left: 128px; bottom: 9px; width: 134px; height: 5px; border-radius: 3px; background: rgba(11,11,11,.85); z-index: 96; pointer-events: none; }
`;

  function phoneHTML() {
    const kr = (keys, extra = '') => `<div class="dp-kr">${keys.map((k) => `<span>${k}</span>`).join('')}${extra}</div>`;
    return `
<div class="dp-phone" role="application" aria-label="Doddy prototype phone">
  <div class="dp-sb" aria-hidden="true">
    <span class="dp-time">9:41</span><div class="dp-island"></div><span class="dp-micdot"></span>
    <svg class="dp-sbicons" viewBox="0 0 78 14"><g fill="#0B0B0B"><rect x="0" y="9" width="3" height="4" rx="1"/><rect x="5" y="7" width="3" height="6" rx="1"/><rect x="10" y="4.5" width="3" height="8.5" rx="1"/><rect x="15" y="2" width="3" height="11" rx="1"/></g>
    <g fill="none" stroke="#0B0B0B" stroke-width="1.8" stroke-linecap="round"><path d="M27 6.2a9 9 0 0 1 12.4 0"/><path d="M29.4 8.8a5.4 5.4 0 0 1 7.6 0"/></g><circle cx="33.2" cy="11.6" r="1.5" fill="#0B0B0B"/>
    <rect x="49" y="1.5" width="24" height="11" rx="3.4" fill="none" stroke="#0B0B0B" stroke-opacity=".45"/><rect x="51" y="3.5" width="17" height="7" rx="1.8" fill="#0B0B0B"/><path d="M74.6 5.2v3.6" stroke="#0B0B0B" stroke-opacity=".45" stroke-width="1.4" stroke-linecap="round"/></svg>
  </div>
  <header class="dp-appbar">
    <span class="dp-wordmark" data-zone="text">doddy<span class="dp-dot">.</span></span>
    <button type="button" class="dp-menu" aria-label="More options" data-zone="button"><i></i><i></i><i></i></button>
  </header>

  <section class="dp-screen" data-screen="home" aria-label="Home">
    <div class="dp-stage" aria-hidden="true"></div>
    <button type="button" class="dp-talkhit" aria-label="Talk to Doddy"></button>
    <p class="dp-home-h" data-zone="text">I’m here.</p>
    <p class="dp-home-sub" data-zone="text">Tap Doddy to talk</p>
    <button type="button" class="dp-voice" data-zone="button" aria-label="Stop listening"><i></i><span>Stop</span><b aria-hidden="true"><span></span><span></span><span></span><span></span><span></span></b></button>
  </section>

  <section class="dp-screen" data-screen="talk" aria-label="Talk">
    <ul class="dp-thread" aria-live="polite"></ul>
    <div class="dp-composer" role="button" tabindex="0" aria-label="Message field">
      <span class="dp-composer-text"></span>
      <button type="button" class="dp-mic" aria-label="Voice" data-zone="button"><svg viewBox="0 0 16 16" aria-hidden="true"><rect x="5.5" y="1.5" width="5" height="8.5" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M3 7.6a5 5 0 0 0 10 0M8 12.6v2" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg></button>
      <button type="button" class="dp-send" aria-label="Send to Doddy" data-zone="send"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 13V3M3.5 7.5 8 3l4.5 4.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
    </div>
  </section>

  <section class="dp-screen" data-screen="memories" aria-label="Memories">
    <p class="dp-mem-title" data-zone="text">Memories</p>
    <div class="dp-search" data-zone="button">Find something you saved</div>
    <div class="dp-list"><div class="dp-list-c"></div></div>
  </section>

  <div class="dp-detail" aria-hidden="true">
    <button type="button" class="dp-back" data-zone="button">‹ Memories</button>
    <p class="dp-detail-k" data-zone="text">Original note</p>
    <p class="dp-detail-h" data-zone="text"></p>
    <p class="dp-detail-b" data-zone="text"></p>
    <div class="dp-source"><p class="dp-source-k" data-zone="text">Source</p><br><p class="dp-source-b" data-zone="text"></p></div>
  </div>

  <div class="dp-scrim" aria-hidden="true"></div>
  <div class="dp-panel" aria-expanded="false">
    <div class="dp-panel-strip" role="button" tabindex="0" aria-label="Message to Mateusz. Review.">
      <span data-zone="text">Message to Mateusz</span><b data-zone="review">Review ›</b>
    </div>
    <div class="dp-panel-open">
      <button type="button" class="dp-grab" aria-label="Collapse review"><i></i></button>
      <p class="dp-p-h">Message to Mateusz</p>
      <p class="dp-p-meta">Messages · mobile ending 0142</p>
      <p class="dp-p-draft" role="button" tabindex="0">I’m running ten minutes late. See you soon.</p>
      <button type="button" class="dp-reviewsend">Review &amp; send</button>
      <p class="dp-p-foot">You’ll send it in Apple’s composer.</p>
      <button type="button" class="dp-later">Keep for later</button>
    </div>
  </div>

  <svg class="dp-overlay" viewBox="0 0 390 844" aria-hidden="true"></svg>

  <nav class="dp-tabbar" role="tablist" aria-label="Sections">
    <button type="button" class="dp-tab is-on" role="tab" aria-selected="true" data-tab="home" data-zone="button"><span>Home</span></button>
    <button type="button" class="dp-tab" role="tab" aria-selected="false" data-tab="talk" data-zone="button"><span>Talk</span></button>
    <button type="button" class="dp-tab" role="tab" aria-selected="false" data-tab="memories" data-zone="button"><span>Memories</span><i class="dp-badge"></i></button>
  </nav>
  <div class="dp-railline" aria-hidden="true"></div>

  <div class="dp-keyboard" aria-hidden="true">
    ${kr(['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'])}
    ${kr(['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'])}
    ${kr(['Z', 'X', 'C', 'V', 'B', 'N', 'M', '⌫'])}
    <div class="dp-kr"><span class="dp-space">space</span><span class="dp-done">done</span></div>
  </div>

  <div class="dp-banner" role="status"><i></i><span>You’re offline. Doddy will wait.</span></div>
  <div class="dp-toast" role="status">Saved to Memories</div>
  <div class="dp-sheet-dim" aria-hidden="true"></div>
  <div class="dp-sheet" aria-hidden="true">
    <button type="button" class="c" data-act="sheet-cancel">Cancel</button><span class="h">New Message</span>
    <div class="to">To: <b>Mateusz</b></div>
    <p class="note">Apple’s Messages composer (simulated)</p>
    <div class="fld"><span class="fld-t">I’m running ten minutes late. See you soon.</span><button type="button" class="snd" data-act="sheet-send" aria-label="Send"><svg viewBox="0 0 16 16"><path d="M8 13V3M3.5 7.5 8 3l4.5 4.5" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></button></div>
  </div>
  <div class="dp-sim" aria-hidden="true"><span class="dp-sim-l">Simulation · stand-in rig</span><span class="dp-sim-r"></span></div>
  <div class="dp-touch" aria-hidden="true"></div>
  <svg class="dp-anno" viewBox="0 0 390 844" aria-hidden="true"></svg>
  <div class="dp-homeind" aria-hidden="true"></div>
</div>`;
  }

  global.DoddyCore = { clamp, lerp, smoothstep, hyp, fmt, Spring, springAhead, mulberry32, L, M, liftFor, flightPoint, flightVelocity, ITEMS, SAVED_ITEM, itemHeight, CSS, phoneHTML };
})(typeof window !== 'undefined' ? window : globalThis);

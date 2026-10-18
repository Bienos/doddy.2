/* Doddy v2 engine: one persistent character over Home, Talk, Memories and the draft panel.
   Implements the 13 rules of the v2 brief. Shared by the prototype and the video renderer. */
(function (global) {
  'use strict';
  const C = global.DoddyCore;
  const { clamp, lerp, smoothstep, hyp, fmt, Spring, springAhead, mulberry32, L, M, liftFor, flightPoint, flightVelocity, ITEMS, SAVED_ITEM, itemHeight } = C;
  const NS = 'http://www.w3.org/2000/svg';
  const el = (tag, attrs, parent) => { const e = document.createElementNS(NS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); if (parent) parent.appendChild(e); return e; };
  let cssInjected = false;
  function injectCSS() { if (cssInjected) return; cssInjected = true; const s = document.createElement('style'); s.textContent = C.CSS; document.head.appendChild(s); }

  function createApp(root, opts = {}) {
    injectCSS();
    root.innerHTML = C.phoneHTML();
    const $ = (s) => root.querySelector(s);
    const phone = $('.dp-phone');
    const E = {
      screens: { home: $('[data-screen="home"]'), talk: $('[data-screen="talk"]'), memories: $('[data-screen="memories"]') },
      tabs: Array.from(root.querySelectorAll('.dp-tab')), badge: $('.dp-badge'), railLine: $('.dp-railline'),
      stage: $('.dp-stage'), talkHit: $('.dp-talkhit'), homeH: $('.dp-home-h'), homeSub: $('.dp-home-sub'), voice: $('.dp-voice'), voiceBars: Array.from(root.querySelectorAll('.dp-voice b span')),
      thread: $('.dp-thread'), composer: $('.dp-composer'), composerText: $('.dp-composer-text'), mic: $('.dp-mic'), send: $('.dp-send'),
      list: $('.dp-list'), listC: $('.dp-list-c'),
      detail: $('.dp-detail'), detailH: $('.dp-detail-h'), detailB: $('.dp-detail-b'), sourceB: $('.dp-source-b'), source: $('.dp-source'),
      scrim: $('.dp-scrim'), panel: $('.dp-panel'), panelOpenC: $('.dp-panel-open'), panelStripC: $('.dp-panel-strip'),
      keyboard: $('.dp-keyboard'), banner: $('.dp-banner'), toast: $('.dp-toast'), sheet: $('.dp-sheet'), sheetDim: $('.dp-sheet-dim'), sheetText: $('.dp-sheet .fld-t'),
      time: $('.dp-time'), micdot: $('.dp-micdot'), simRow: $('.dp-sim'), touch: $('.dp-touch'), sim: $('.dp-sim-l'), simR: $('.dp-sim-r'), anno: $('.dp-anno'),
      svg: $('.dp-overlay'),
    };
    const debugG = el('g', {}, E.svg);
    const trailEl = el('polyline', { fill: 'none', stroke: '#C0582A', 'stroke-width': 1.2, 'stroke-dasharray': '2 3', opacity: 0.85 }, debugG);
    const anchorsG = el('g', {}, debugG);
    const rig = global.DoddyRig.createRig(E.svg, 'doddy-hero');

    const settings = Object.assign({
      timeScale: 1, reduceMotion: false, lowPower: false, showPath: false, showAnchors: false, annotate: false,
      homeScale: 1.4, replyDelay: 2000, replyFails: false, voiceFromHome: true, composerResult: 'sent',
      clock: '9:41', welcomeKind: 'default', braceOn: 24000, braceOff: 8000, focusOnTalkTap: false, label: '', seed: 7, autoWelcome: true,
    }, opts.settings || {});
    let rand = mulberry32(settings.seed);

    /* ------------------------------------------------------------------ state */
    let simT = 0;
    const timers = [];
    const after = (ms, fn) => timers.push({ at: simT + ms, fn });
    const log = [];
    const metrics = { hops: [], tabTaps: [], violations: [], events: [], braces: [], ridePeaks: [], zoneChecks: 0, frames: 0, maxContactGap: 0, maxComposerGap: 0, listenFrames: 0, listenViolations: 0, playful: [], scaleChanges: [] };
    function note(msg, kind) {
      log.unshift({ t: simT, msg });
      if (log.length > 12) log.length = 12;
      metrics.events.push({ t: Math.round(simT), msg, kind: kind || '' });
      if (opts.onLog) opts.onLog(log);
    }
    function violation(kind, detail) { metrics.violations.push({ t: Math.round(simT), kind, detail }); }

    const ui = {
      tab: 'home', fade: { home: 1, talk: 0, memories: 0 },
      draft: 'none', draftText: 'I’m running ten minutes late. See you soon.', panelMode: 'hidden',
      panelTop: new Spring(L.panelHiddenTop, 0.42, 0.88), panelPrevTop: L.panelHiddenTop, panelDrag: null,
      keyboard: false, kbTop: new Spring(L.H, 0.28, 1.0), composerBase: new Spring(L.composerBottomNoStrip, 0.42, 0.88),
      detail: { open: false, item: 0 }, detailX: new Spring(L.W, 0.36, 1.0),
      threadOcc: new Spring(L.composerBottomNoStrip - L.composerH, 0.2, 1.0),
      typed: '', typingTarget: '', typingTimer: 0, lastInput: -99999, lastTyping: -99999, lastTap: -99999,
      messages: [], msgVersion: 0, renderedVersion: -1, awaiting: null, nextReply: null,
      items: ITEMS.map((it) => Object.assign({ h: itemHeight(it), hs: null }, it)), layout: [], contentH: 0,
      scroll: { y: 0, v: 0, vel: 0, mode: 'idle', spring: new Spring(0, 0.4, 1.0), prevY: 0, slowSince: 0, d0: 0, f0: 0 },
      mic: false, micFade: 0,
      banner: { show: false, y: new Spring(-120, 0.36, 0.86) },
      toast: { active: false, phase: '', x: new Spring(-200, 0.5, 0.9), lane: 300, w: 150, prevX: -200, t: 0, restX: 0, exitX: -200, hold: 1400, text: 'Saved to Memories' },
      sheet: { open: false, y: new Spring(800, 0.42, 1.0), dim: 0 },
      voice: { phase: 'idle', t: 0, live: false },
      badge: false, savedSinceVisit: false,
      dips: {},
      clockText: settings.clock,
    };
    const dip = (id) => { if (!ui.dips[id]) ui.dips[id] = new Spring(0, 0.22, 0.5); return ui.dips[id]; };
    const scrollState = ui.scroll;

    const D = {
      mode: 'attached', anchor: { surface: 'stage', x: L.stage.x }, target: null,
      pos: { x: L.stage.x, y: L.stage.y }, vel: { x: 0, y: 0 }, scale: settings.homeScale,
      flight: null, phaseT: 0, airborne: 0, airStart: 0, antDur: 80, retargets: 0, noInherit: false, recheckOnLand: false, surfaceVel: { x: 0, y: 0 },
      opacity: 1, fadeMoved: false, fadeKind: 'hop',
      lastLand: -99999, idleSince: 0, lastMove: 0,
      crouch: new Spring(0, 0.30, 0.60), duck: new Spring(0, 0.14, 1.0), dip: new Spring(0, 0.06, 1.0), dragC: new Spring(0, 0.12, 1.0),
      sit: new Spring(0, 0.45, 0.92), edge: new Spring(0, 0.40, 0.95),
      lean: new Spring(0, 0.20, 0.85), roll: new Spring(0, 0.24, 0.80), facing: new Spring(0, 0.20, 0.90),
      gx: new Spring(0, 0.15, 0.85), gy: new Spring(0, 0.15, 0.85),
      armL1: new Spring(30, 0.35, 0.75), armL2: new Spring(20, 0.35, 0.75), armR1: new Spring(30, 0.35, 0.75), armR2: new Spring(20, 0.35, 0.75),
      tuck: new Spring(0, 0.12, 0.9), squash: new Spring(0, 0.10, 0.8), stretchUp: new Spring(0, 0.12, 1.0), xOff: new Spring(0, 0.28, 0.70),
      toe: new Spring(0, 0.42, 1.0), squint: new Spring(0, 0.05, 1.0), shut: new Spring(0, 0.06, 1.0),
      footL: { dx: 0, up: 0 }, footR: { dx: 0, up: 0 }, swing: 0,
      blink: 0, blinkT: -1, blinkDur: 210,
      gaze: { kind: 'user', label: 'you' }, reaction: null, userGazeAt: 0,
      activity: 'resting', mood: 'calm', moodUntil: 0,
      pendingTransfer: null, pendingPickup: false, pendingStepOff: null,
      hiddenBehind: false, memory: { home: { surface: 'stage', x: L.stage.x } },
      budgets: { playful: 1, welcome: 1 }, session: { playfulUsed: 0 },
      breathT: -1, breath: 0, breathSince: 0,
      gesture: null, micro: null, typingArmed: true, lastSendReact: -99999, pauseArmed: true,
      calm: false, changes: [], lastChange: -99999,
      z: 1.2, trail: [], curHop: null, shuf: null,
      visit: { start: 0, hadWelcome: false, glances: 0, lookAround: false, nextGlanceAt: 0, arrivalGlance: false },
      satThisIdle: false, edgeThisIdle: false,
      thinking: null, listenOn: false, ducking: false, brace: { on: false, done: false, peak: 0 }, supAcc: 0, prevVy: 0, accHist: [],
      homeTouch: null, rub: { active: false, starts: [], lastEnd: -99999, lastStart: -99999, smileOnly: false }, lastFlick: -99999,
      scrollWait: false, lastLily: -99999,
      lastScale: settings.homeScale,
    };

    /* ------------------------------------------------------------------ layout helpers */
    const homeScale = () => settings.homeScale;
    /* The composer animates with the keyboard's own curve between its two resting places (UIKit keyboard layout guide). */
    const kbProg = (kx) => clamp((L.H - kx) / L.kbH, 0, 1);
    const composerBottomAt = (base, kx) => lerp(base, Math.min(base, L.H - L.kbH - 8), kbProg(kx));
    const composerTop = () => composerBottomAt(ui.composerBase.x, ui.kbTop.x) - L.composerH;
    const composerMaxX = () => (ui.mic ? L.sendHitMic.x0 : L.sendHit.x0) - 48;
    const listBottom = () => (ui.draft === 'pending' ? L.stripTop - L.listInset : L.listBottomBase);
    const listVH = () => listBottom() - L.listTop;
    function relayout() {
      let y = 0; ui.layout = [];
      for (const it of ui.items) { const h = it.hs ? it.hs.x : it.h; ui.layout.push({ top: y, h, bottom: y + h }); y += h; }
      ui.contentH = y;
    }
    relayout();
    const maxScroll = () => Math.max(0, ui.contentH + L.listInset - (L.listBottomBase - L.listTop));
    const ruleY = (i) => L.listTop + (ui.layout[i] ? ui.layout[i].bottom : 0) - scrollState.y;
    const zoneOf = (s) => ({ w: L.zoneW * s, h: L.zoneH * s });

    /* ------------------------------------------------------------------ surfaces */
    const surfCache = new Map();
    function S(id) {
      let s = surfCache.get(id);
      if (s) return s;
      if (id === 'stage') s = { id, layer: 1, get scale() { return homeScale(); }, screen: 'home', top: () => L.stage.y, xr: () => [150, 240], seg: () => [L.stage.x0, L.stage.x1], vis: () => ui.tab === 'home' };
      else if (id === 'composer') s = { id, layer: 1, scale: 1, screen: 'talk', top: composerTop, xr: () => [44, composerMaxX()], seg: () => [16, 374], vis: () => ui.tab === 'talk' };
      else if (id === 'panel') s = { id, layer: 2, scale: 1, screen: '*', top: () => ui.panelTop.x, xr: () => (ui.panelMode === 'open' ? [40, 330] : [40, L.reviewHit.x0 - 48]), seg: () => { const e = panelOpenness(); const inset = lerp(16, 8, e); return [inset, L.W - inset]; }, vis: () => ui.draft === 'pending' };
      else if (id === 'rail') s = { id, layer: 2.5, scale: 1, screen: '*', top: () => L.rail, xr: () => [40, 350], seg: () => [0, L.W], vis: () => true };
      else if (id === 'detail') s = { id, layer: 1.5, scale: 1, screen: 'memories', top: () => L.detailSourceY, dx: () => ui.detailX.x, xr: () => [40, 350], seg: () => [16 + ui.detailX.x, 374 + ui.detailX.x], vis: () => ui.tab === 'memories' && ui.detail.open };
      else if (id.startsWith('rule:')) { const i = +id.slice(5); s = { id, layer: 1, scale: 1, screen: 'memories', rule: i, top: () => ruleY(i), xr: () => [306, 340], seg: () => [24, 366], vis: () => ui.tab === 'memories' && i < ui.layout.length }; }
      surfCache.set(id, s);
      return s;
    }
    function anchorPoint(a) { const s = S(a.surface); return { x: a.x + (s.dx ? s.dx() : 0), y: s.top() + dip(a.surface).x }; }
    function scrollAhead(dt) {
      const sc = scrollState;
      if (dt <= 0) return sc.y;
      if (sc.mode === 'momentum') { const k = -Math.log(0.998) * 1000; return sc.y + (sc.v / k) * (1 - Math.exp(-k * dt)); }
      if (sc.mode === 'drag') return sc.y + sc.vel * dt;
      if (sc.mode === 'bounce' || sc.mode === 'toTop') return springAhead(sc.spring, dt);
      return sc.y;
    }
    function pointAt(a, dt) {
      if (a.surface === 'panel') return { x: a.x, y: ui.panelDrag ? ui.panelTop.x + ui.panelTop.v * dt : springAhead(ui.panelTop, dt) };
      if (a.surface === 'composer') return { x: a.x, y: composerBottomAt(springAhead(ui.composerBase, dt), springAhead(ui.kbTop, dt)) - L.composerH };
      if (a.surface === 'detail') return { x: a.x + springAhead(ui.detailX, dt), y: L.detailSourceY };
      if (a.surface.startsWith('rule:')) { const i = +a.surface.slice(5); return { x: a.x, y: L.listTop + (ui.layout[i] ? ui.layout[i].bottom : 0) - scrollAhead(dt) }; }
      return anchorPoint(a);
    }
    function predictedPoint(a) {
      if (a.surface === 'panel') return { x: a.x, y: ui.panelTop.target };
      if (a.surface === 'composer') return { x: a.x, y: composerBottomAt(ui.composerBase.target, ui.kbTop.target) - L.composerH };
      if (a.surface === 'detail') return { x: a.x + ui.detailX.target, y: L.detailSourceY };
      if (a.surface.startsWith('rule:')) return pointAt(a, 0.4);
      return anchorPoint(a);
    }
    function aimFlight(p0, target, timeFor) {
      let p1 = predictedPoint(target), T = 0;
      for (let i = 0; i < 3; i++) { T = timeFor(hyp(p1.x - p0.x, p1.y - p0.y), p1.y - p0.y); p1 = pointAt(target, T / 1000); }
      return { p1, T };
    }
    function supportMovingNow() {
      const a = D.anchor; if (!a) return false;
      if (a.surface === 'panel') return !!ui.panelDrag || Math.abs(ui.panelTop.target - ui.panelTop.x) > 0.5 || Math.abs(ui.panelTop.v) > 5;
      if (a.surface === 'composer') return Math.abs(ui.kbTop.target - ui.kbTop.x) > 0.5 || Math.abs(ui.composerBase.target - ui.composerBase.x) > 0.5;
      if (a.surface.startsWith('rule:')) return Math.abs(scrollState.vel) > 2;
      if (a.surface === 'detail') return Math.abs(ui.detailX.target - ui.detailX.x) > 0.5;
      return false;
    }
    function supportSettleY() {
      if (!D.anchor) return null;
      if (D.anchor.surface === 'composer') return composerBottomAt(ui.composerBase.target, ui.kbTop.target) - L.composerH;
      if (D.anchor.surface === 'panel') return ui.panelTop.target;
      return S(D.anchor.surface).top();
    }
    function surfaceVisible(id) { return S(id).vis(); }
    const sameAnchor = (a, b) => a && b && a.surface === b.surface && Math.abs(a.x - b.x) < 6;
    const panelOpenness = () => (ui.draft === 'pending' ? clamp((L.stripTop - ui.panelTop.x) / (L.stripTop - L.panelOpenTop), 0, 1) : 0);

    /* ------------------------------------------------------------------ gaze & reactions */
    function gazeAt(kind, data, label) { D.gaze = Object.assign({ kind, label: label || kind }, data || {}); }
    function headPos() { return { x: D.pos.x + D.xOff.x, y: D.pos.y - 77.5 * D.scale }; }
    function gazeVector() {
      const g = D.gaze;
      if (g.kind === 'user') return { x: 0, y: 0 };
      if (g.kind === 'dir') return { x: g.x, y: g.y };
      const head = headPos();
      let tx = g.x, ty = g.y;
      if (g.kind === 'anchor' && g.anchor) { const p = anchorPoint(g.anchor); tx = p.x; ty = p.y; }
      if (g.kind === 'finger') { tx = finger.x; ty = finger.y; }
      const dx = tx - head.x, dy = ty - head.y, d = Math.max(1, hyp(dx, dy));
      return { x: dx / d, y: dy / d };
    }
    function setMood(m, ms) { D.mood = m; D.moodUntil = ms ? simT + ms : 0; }
    function screenFocusPoint() {
      const k = screenKey();
      if (k === 'home') return null;
      if (k === 'talk') return { x: 120, y: composerTop() + 22, label: 'composer' };
      if (k === 'review') return { x: 60, y: L.panelOpenTop + 112, label: 'draft' };
      if (k === 'memories') { if (ui.detail.open) return { x: 60, y: 200, label: 'note' }; return { x: 80, y: ruleY(0) - 100, label: 'top item' }; }
      return null;
    }
    function attendContent() {
      const f = screenFocusPoint();
      if (!f) gazeAt('user'); else gazeAt('point', { x: f.x, y: f.y }, f.label);
      D.userGazeAt = simT + 1200;
    }
    /* One gaze-only reaction at a time; the latest event wins. Each lasts at most 600 ms. */
    function notice(kind, pt, dur, o = {}) {
      if (D.mode === 'flight' || D.mode === 'anticipate') return; // he is already attending to a hop
      if (D.gesture && D.gesture.kind !== 'welcome') return;
      D.reaction = { kind, until: simT + Math.min(600, dur), keepUntil: o.keep ? Infinity : 0 };
      gazeAt('point', pt, kind);
      if (o.mood) setMood(o.mood, o.moodMs || 0);
      note(`notices: ${kind} (eyes, ${Math.min(600, dur)} ms)`);
    }

    /* ------------------------------------------------------------------ hops */
    function scaleFor(a) { return S(a.surface).scale; }
    function stopIdlePoses() {
      D.breathT = -1; D.gesture = null; D.micro = null; resetArms();
      D.edge.target = 0; D.sit.target = 0;
    }
    function startHop(target, reason, o = {}) {
      if (settings.reduceMotion) return startFade(target, reason);
      if (D.mode === 'shuffle') endShuffle(false);
      const fromSit = D.sit.x > 0.3 || D.edge.x > 0.3;
      const fromLanding = simT - D.lastLand < 340;
      const goY = predictedPoint(target).y - D.pos.y;
      let away = 0, toward = false;
      if (D.anchor && D.mode === 'attached') {
        const ys = [];
        for (let k = 1; k <= 10; k++) ys.push(pointAt(D.anchor, k * 0.016).y);
        const settleY = supportSettleY(); if (settleY != null) ys.push(settleY);
        for (const y of ys) { const dy = y - D.pos.y; if (Math.abs(dy) > 0.5) { if (Math.sign(dy) !== Math.sign(goY)) away = Math.max(away, Math.abs(dy)); else toward = true; } }
      }
      const leaving = away > 4;
      D.noInherit = leaving && !(Math.sign(D.vel.y) === Math.sign(goY) && Math.abs(D.vel.y) > 30);
      D.antDur = o.immediate || leaving ? 0 : fromSit ? M.anticipationFromSit : (fromLanding || toward) ? M.anticipationFromLanding : M.anticipation;
      if (leaving) note('his surface is about to move away, so he steps off at once (0 ms crouch)');
      D.curHop = { tReq: simT, tap: reason && reason.tapT != null ? reason.tapT : simT, why: (reason && reason.why) || 'navigation', from: D.anchor ? D.anchor.surface : '?', to: target.surface, ant: D.antDur, s0: D.scale, s1: scaleFor(target), tabTap: !!(reason && reason.tab) };
      D.mode = 'anticipate'; D.phaseT = 0; D.target = target; D.retargets = 0; D.activity = 'anticipating';
      stopIdlePoses();
      const p1 = predictedPoint(target), dir = Math.sign(p1.x - D.pos.x) || 0;
      // eyes at 0 ms; head and body follow one frame later
      if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`);
      else gazeAt('anchor', { anchor: target }, 'landing spot');
      const depth = 5; // rig units: 5 pt at 1.0×, 7 pt at 1.4×
      const body = () => {
        if (D.mode !== 'anticipate') return;
        D.crouch.set(fromSit ? 0.16 : 0.12, 1.0); D.crouch.target = depth;
        D.sit.set(0.16, 1.0); D.edge.set(0.16, 1.0);
        D.lean.set(0.20, 0.85); D.lean.target = -3 * dir; D.facing.target = 0.8 * dir; D.roll.target = 0;
      };
      if (D.antDur > 0) after(16, body); else body();
      note(`hop requested → ${target.surface} (${D.curHop.why})`);
      if (D.antDur === 0) { D.surfaceVel = { x: D.vel.x, y: D.vel.y }; takeOff(); }
    }
    function takeOff() {
      const target = D.target;
      const cap = D.curHop && D.curHop.tabTap ? Math.max(260, 480 - (simT - D.curHop.tap)) : 420;
      if (D.curHop) D.curHop.capped = false;
      const timeFor = (Dd, dy) => { const T0 = M.flight(Dd, dy); if (T0 > cap && D.curHop) D.curHop.capped = Math.round(T0); return Math.min(T0, cap); };
      const p0 = { x: D.pos.x + D.xOff.x, y: D.pos.y }, aim = aimFlight(p0, target, timeFor), p1 = aim.p1;
      D.xOff.snap(0);
      const dx = p1.x - p0.x, dy = p1.y - p0.y, Dd = hyp(dx, dy);
      const T = aim.T, A = M.apex(Dd, dy), h = liftFor(p0, p1, A);
      const vS0 = (!D.noInherit && D.surfaceVel) || { x: 0, y: 0 }, vS = { x: vS0.x * 0.5, y: vS0.y * 0.5 };
      D.flight = { p0, p1, t0: simT, m0: { x: dx + vS.x * T / 1000, y: dy + vS.y * T / 1000 }, m1: { x: dx, y: dy }, h, T, t: 0, s0: D.scale, s1: scaleFor(target), kind: 'hop' };
      D.mode = 'flight'; D.phaseT = 0; D.airborne = 0; D.airStart = simT; D.activity = 'flying'; D.trail = [];
      D.z = Math.max(D.anchor ? S(D.anchor.surface).layer : 1, S(target.surface).layer) + 0.2;
      D.crouch.set(0.10, 0.9); D.crouch.target = 0; D.squash.x = 1; D.squash.target = 0;
      D.sit.snap(0); D.edge.snap(0); D.toe.snap(0);
      D.lean.target = 6 * (Math.sign(dx) || 0);
      // arms rise during the first 40 % of the flight; legs tuck toward the apex
      const armR = clamp(T / 1000 * 0.9, 0.12, 0.34);
      for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(armR, 0.9);
      D.armL1.target = 105; D.armL2.target = 135; D.armR1.target = 105; D.armR2.target = 135;
      D.tuck.set(clamp(T / 1000, 0.18, 0.4), 0.9); D.tuck.target = 0.85;
      gazeAt('anchor', { anchor: target }, 'landing spot');
      if (D.curHop) Object.assign(D.curHop, { takeoff: simT, crouch: simT - D.curHop.tReq, T, D: Dd, A, p0, p1 });
      D.lastHop = { label: `${D.anchor ? D.anchor.surface : '?'} → ${target.surface}`, D: Dd, A, T, ant: D.antDur, s0: D.flight.s0, s1: D.flight.s1 };
      D.anchor = null;
      if (opts.onHop) opts.onHop(D.lastHop);
    }
    function retarget(target, reason, o = {}) {
      if (settings.reduceMotion) return startFade(target, reason);
      if (D.mode === 'anticipate') {
        if (D.anchor && sameAnchor(target, D.anchor)) {
          D.mode = 'attached'; D.target = null; D.activity = 'resting';
          D.crouch.set(0.30, 0.60); D.crouch.target = 0; D.lean.target = 0; D.facing.target = 0; gazeAt('user');
          if (D.curHop) { D.curHop.cancelled = simT; metrics.hops.push(D.curHop); D.curHop = null; }
          note('reversed during the crouch, so the hop is cancelled and he never leaves the ground');
          return;
        }
        D.target = target; const dir = Math.sign(anchorPoint(target).x - D.pos.x) || 0;
        D.lean.target = -3 * dir; D.facing.target = 0.8 * dir;
        if (D.curHop) { D.curHop.to = target.surface; D.curHop.s1 = scaleFor(target); D.curHop.reaimed = true; }
        if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`);
        note(`re-aimed during the crouch → ${target.surface}`);
        return;
      }
      if (D.mode === 'flight') {
        const left = M.maxAirborne - D.airborne;
        if (!o.force && left < 160 && D.target && surfaceVisible(D.target.surface)) { D.recheckOnLand = true; note('less than 160 ms of air left, so he lands first and hops on'); return; }
        const timeFor = (Dd_) => Math.max(Math.min(M.retargetFlight(Dd_), Math.max(160, left)), Dd_ / 1.2);
        const p = { x: D.pos.x, y: D.pos.y }, v = D.vel;
        const aim = aimFlight(p, target, timeFor), p1 = aim.p1;
        const dx = p1.x - p.x, dy = p1.y - p.y, Dd = hyp(dx, dy);
        const T = aim.T;
        const h = Math.min(liftFor(p, p1, 8), 40);
        D.flight = { p0: p, p1, t0: simT, m0: { x: v.x * T / 1000, y: v.y * T / 1000 + 4 * h }, m1: { x: dx, y: dy }, h, T, t: 0, s0: D.scale, s1: scaleFor(target), kind: 'retarget' };
        D.target = target; D.phaseT = 0; D.retargets++;
        D.z = Math.max(D.z, S(target.surface).layer + 0.2);
        D.lean.target = 6 * (Math.sign(dx) || 0); D.facing.target = 0.8 * (Math.sign(dx) || 0);
        gazeAt('anchor', { anchor: target }, 'new landing spot');
        if (D.curHop) { D.curHop.to = target.surface; D.curHop.s1 = scaleFor(target); D.curHop.retargets = D.retargets; D.curHop.retargetAt = simT; D.curHop.T2 = T; }
        D.lastHop = { label: `mid-air re-target → ${target.surface}`, D: Dd, A: 8, T, ant: 0, s0: D.flight.s0, s1: D.flight.s1 };
        if (opts.onHop) opts.onHop(D.lastHop);
        note(`re-targeted mid-air → ${target.surface} (keeps ${fmt(hyp(v.x, v.y))} pt/s, new flight ${fmt(T)} ms)`);
      }
    }
    function land() {
      const f = D.flight, target = D.target;
      const v = flightVelocity(f, 1);
      D.mode = 'attached'; D.anchor = target; D.target = null; D.flight = null; D.lastLand = simT; D.activity = 'landing'; resetSupportVel(target);
      D.scale = f.s1;
      D.z = S(target.surface).layer + 0.2;
      const p = anchorPoint(target); D.pos.x = p.x; D.pos.y = p.y;
      const impact = clamp(Math.max(0, v.y) / 1800, 0, 1);
      const sq = 2.2 + 2.2 * impact; // rig units: 2.2–4.4 pt at 1.0×
      D.crouch.set(0.30, 0.60); D.crouch.v += sq * 41.9; D.crouch.target = 0; D.satThisIdle = false; D.edgeThisIdle = false;
      D.tuck.target = 0; D.tuck.x = 0; D.squash.target = 0;
      const peak = clamp(Math.abs(v.x) / 50, 0, 4) * Math.sign(v.x) * D.scale;
      D.xOff.set(0.28, 0.70); D.xOff.x = 0; D.xOff.v = peak * (2 * Math.PI / 0.28) * 2.18;
      D.lean.target = 0; resetArms();
      dip(target.surface).v += 38 + 38 * impact;
      after(200, () => { if (D.mode === 'attached') D.facing.target = 0; });
      after(150, () => { if (D.mode === 'attached' && !D.gesture && !D.micro && !D.thinking) attendContent(); });
      D.memory[screenKey()] = { surface: target.surface, x: target.x };
      D.breathT = simT + 2000; D.idleSince = simT;
      if (f.kind === 'flick') { setMood('pleased', 700); note('flick hop lands on the same spot, pleased'); }
      if (D.curHop) { Object.assign(D.curHop, { contact: simT, contactAfterTap: simT - D.curHop.tap, impact: Math.round(v.y), squashPt: +(sq * D.scale).toFixed(2), landScale: D.scale }); metrics.hops.push(D.curHop); D.curHop = null; }
      if (target.surface === 'stage') startVisit();
      if (target.surface.startsWith('rule:')) D.scrollWait = false;
      if (D.recheckOnLand) { D.recheckOnLand = false; after(0, () => updateDestination({ why: 'landed; on to the newest destination' })); }
      note(`contact on ${target.surface} at ${fmt(hyp(v.x, v.y))} pt/s; squash ${fmt(sq * D.scale, 1)} pt, settle`);
    }
    /* After he changes support, his velocity is that support's velocity (no false acceleration spike). */
    function resetSupportVel(a) {
      const pA = pointAt(a, 0), pB = pointAt(a, 0.008);
      D.vel = { x: (pB.x - pA.x) / 0.008, y: (pB.y - pA.y) / 0.008 }; D.accHist = []; D.justLanded = true;
    }
    function startFade(target, reason, kind = 'hop') {
      if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`); else gazeAt('anchor', { anchor: target }, 'destination');
      const out = kind === 'shuffle' ? M.shuffleOut : M.fadeOut;
      if (D.mode === 'fade') {
        if (D.phaseT >= D.fadeOutMs && !sameAnchor(target, D.anchor)) { D.phaseT = (1 - D.opacity) * D.fadeOutMs; D.fadeMoved = false; }
        D.target = target; note(`fade re-aimed → ${target.surface}`); return;
      }
      if (D.mode === 'shuffle') endShuffle(false);
      stopIdlePoses();
      D.mode = 'fade'; D.target = target; D.phaseT = 0; D.activity = 'fading'; D.fadeKind = kind;
      D.fadeOutMs = out; D.fadeInMs = kind === 'shuffle' ? M.shuffleIn : M.fadeIn;
      D.curHop = null;
      note(`Reduce Motion: fade to ${target.surface} (${out} ms out, ${D.fadeInMs} ms in)`);
    }
    function resetArms(r = 0.35) {
      D.armL1.target = 30; D.armL2.target = 20; D.armR1.target = 30; D.armR2.target = 20;
      for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(r, 0.75);
    }
    function screenKey() { return ui.draft === 'pending' && ui.panelMode === 'open' ? 'review' : ui.tab; }

    /* ------------------------------------------------------------------ shuffle (same surface, ≤ 40 pt) */
    function startShuffle(x1, why) {
      const x0 = D.anchor.x, dlt = x1 - x0;
      if (Math.abs(dlt) < 0.5) { D.anchor.x = x1; return; }
      if (settings.reduceMotion) return startFade({ surface: D.anchor.surface, x: x1 }, { why }, 'shuffle');
      if (Math.abs(dlt) > 40) return startHop({ surface: D.anchor.surface, x: x1 }, { why });
      const dir = Math.sign(dlt), s = D.scale;
      stopIdlePoses();
      D.mode = 'shuffle';
      D.shuf = { x0, x1, dlt, dir, t: 0, single: Math.abs(dlt) < 8, fL: x0 - 7.5 * s, fR: x0 + 7.5 * s, lead: dir > 0 ? 'R' : 'L' };
      gazeAt('point', { x: x1, y: S(D.anchor.surface).top() }, 'new spot');
      after(16, () => { if (D.mode === 'shuffle') { D.facing.target = 0.4 * dir; D.lean.target = 1.5 * dir; } });
      D.activity = 'shuffling';
      note(`shuffle ${fmt(Math.abs(dlt))} pt along ${D.anchor.surface} (${D.shuf.single ? 'one side-step' : 'two steps'}, ${why})`);
    }
    function endShuffle(complete) {
      const sh = D.shuf; if (!sh) return;
      if (complete) { D.anchor.x = sh.x1; D.memory[screenKey()] = { surface: D.anchor.surface, x: sh.x1 }; }
      D.footL = { dx: 0, up: 0 }; D.footR = { dx: 0, up: 0 }; D.shuf = null;
      if (D.mode === 'shuffle') { D.mode = 'attached'; D.activity = 'resting'; }
    }
    function stepShuffle(dtMs) {
      const sh = D.shuf; if (!sh) return;
      sh.t += dtMs;
      const s = D.scale, t = sh.t, ease = (u) => smoothstep(0, 1, u);
      let bodyX, uLead, uTrail;
      if (sh.single) { const u = clamp(t / M.step, 0, 1); bodyX = sh.x0 + sh.dlt * ease(u); uLead = clamp(t / 70, 0, 1); uTrail = clamp((t - 40) / 70, 0, 1); }
      else if (t < M.step) { const u = t / M.step; bodyX = sh.x0 + sh.dlt / 2 * ease(u); uLead = u; uTrail = 0; }
      else { const u = clamp((t - M.step) / M.step, 0, 1); bodyX = sh.x0 + sh.dlt / 2 + sh.dlt / 2 * ease(u); uLead = 1; uTrail = u; }
      const feet = { L: sh.fL, R: sh.fR }, lift = { L: 0, R: 0 };
      const lead = sh.lead, trail = lead === 'R' ? 'L' : 'R';
      feet[lead] += sh.dlt * ease(uLead); lift[lead] = 3 * Math.sin(Math.PI * uLead);
      feet[trail] += sh.dlt * ease(uTrail); lift[trail] = 3 * Math.sin(Math.PI * uTrail);
      D.footL = { dx: (feet.L - bodyX) / s + 7.5, up: lift.L };
      D.footR = { dx: (feet.R - bodyX) / s - 7.5, up: lift.R };
      D.anchor.x = bodyX;
      const stepsDone = sh.single ? M.step : 2 * M.step;
      if (t >= stepsDone && !sh.settling) { sh.settling = true; D.facing.target = 0; D.lean.set(0.25, 0.55); D.lean.target = 0; D.footL = { dx: 0, up: 0 }; D.footR = { dx: 0, up: 0 }; }
      if (sh.settling) { D.footL = { dx: 0, up: 0 }; D.footR = { dx: 0, up: 0 }; D.anchor.x = sh.x1; }
      if (t >= stepsDone + M.stepSettle) { endShuffle(true); after(0, () => attendContent()); }
    }

    /* ------------------------------------------------------------------ where he should be */
    function bestRuleAnchor(prefer) {
      const lb = listBottom(), hz = L.zoneH * 1;
      const fits = (i) => { const y = ruleY(i); return y - hz >= L.listTop - 0.5 && y <= lb - 2 && !ruleUnderFinger(i); };
      if (prefer != null && fits(prefer)) return { surface: `rule:${prefer}`, x: L.ruleX };
      for (let i = 0; i < ui.layout.length; i++) if (fits(i)) return { surface: `rule:${i}`, x: L.ruleX };
      return { surface: 'rail', x: L.tabX.memories };
    }
    /* Rule i is the bottom edge of row i: standing on it puts him in that row. A touched row is never landed on. */
    function ruleUnderFinger(i) {
      if (!finger.down || ui.tab !== 'memories') return false;
      const fy = finger.y; if (fy < L.listTop || fy > listBottom()) return false;
      const top = i === 0 ? L.listTop - scrollState.y : ruleY(i - 1), bot = ruleY(i);
      return fy >= top && fy <= bot;
    }
    function preferredAnchor() {
      if (ui.draft === 'pending' && ui.panelMode === 'open') return { surface: 'panel', x: L.draftX };
      if (ui.tab === 'home') return { surface: 'stage', x: L.stage.x };
      if (ui.tab === 'talk') { const m = D.memory.talk; return { surface: 'composer', x: clamp(m && m.surface === 'composer' ? m.x : L.draftX, 44, composerMaxX()) }; }
      if (ui.tab === 'memories') {
        if (ui.detail.open) return D.hiddenBehind && D.anchor ? D.anchor : { surface: 'detail', x: L.detailX };
        if (ui.draft === 'pending') return { surface: 'panel', x: L.draftX };
        const m = D.memory.memories;
        return bestRuleAnchor(m && m.surface.startsWith('rule:') ? +m.surface.slice(5) : null);
      }
      return null;
    }
    function waitAnchor() {
      if (ui.draft === 'pending' && ui.panelMode !== 'open') return { surface: 'panel', x: clamp(L.tabX[ui.tab], 40, L.reviewHit.x0 - 48) };
      // on Talk the rail spot would stand him in front of the composer field, so he waits on the composer edge
      if (ui.tab === 'talk') return { surface: 'composer', x: clamp(L.draftX, 44, composerMaxX()) };
      return { surface: 'rail', x: clamp(L.tabX[ui.tab], 40, 350) };
    }
    function updateDestination(reason) {
      if (ui.sheet.open) return;
      const pref = preferredAnchor();
      if (!pref) return;
      D.pendingTransfer = null; D.pendingPickup = false; D.pendingStepOff = null;
      if (reason && reason.tab && !settings.reduceMotion) {
        D.changes = D.changes.filter((t) => simT - t < M.calm.window); D.changes.push(simT); D.lastChange = simT;
        if (D.changes.length >= M.calm.changes && !D.calm) { D.calm = true; note('rapid switching: wait on the rail'); }
      }
      if (D.calm && !settings.reduceMotion) {
        const wait = waitAnchor();
        const isWait = (a) => a && (a.surface === 'rail' || a.surface === 'panel' || (ui.tab === 'talk' && a.surface === 'composer'));
        if (D.mode === 'attached' && isWait(D.anchor) && sameAnchor(D.anchor, wait)) { if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`); return; }
        if (D.mode === 'attached' || D.mode === 'shuffle') return startHop(wait, { why: 'calm mode', tab: reason && reason.tab, tapT: reason && reason.tapT });
        if (D.target && isWait(D.target) && sameAnchor(D.target, wait)) { if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`); return; }
        return retarget(wait, { why: 'calm mode' });
      }
      if (D.mode === 'fade') { if (!sameAnchor(D.target, pref)) startFade(pref, reason); return; }
      if (D.mode === 'shuffle') endShuffle(false);
      if (D.mode === 'attached') {
        if (sameAnchor(D.anchor, pref)) { if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`); after(260, () => { if (D.mode === 'attached') attendContent(); }); return; }
        if (D.hiddenBehind && pref === D.anchor) return;
        const sameSize = Math.abs(scaleFor(pref) - D.scale) < 0.001;
        if (sameSize && D.anchor.surface === 'panel' && ui.panelTop.target > ui.panelTop.x && pref.surface !== 'panel') {
          const s = S(pref.surface), top = s.top(), xr = s.xr();
          if (top > ui.panelTop.x && top <= ui.panelTop.target + 1 && D.pos.x >= xr[0] && D.pos.x <= xr[1]) {
            D.pendingTransfer = { surface: pref.surface, x: D.pos.x }; D.activity = 'riding'; note(`riding the panel down; will step onto ${pref.surface}`); return;
          }
        }
        if (sameSize && pref.surface === 'panel' && ui.panelTop.target < ui.panelTop.x) {
          const top = D.pos.y, settleY = supportSettleY(), staying = settleY == null || settleY - top <= 4;
          if (staying && top < ui.panelTop.x && top >= ui.panelTop.target - 1) { D.pendingPickup = true; D.activity = 'waiting for pickup'; gazeAt('point', { x: D.pos.x, y: ui.panelTop.x }, 'rising panel'); note('the rising panel will pick him up'); return; }
        }
        const goY = predictedPoint(pref).y - D.pos.y;
        if (Math.sign(D.vel.y) !== Math.sign(goY) && Math.abs(D.vel.y) >= 150) {
          D.pendingStepOff = { target: pref, reason }; D.activity = 'riding';
          if (reason && reason.tab) gazeAt('point', { x: L.tabX[reason.tab], y: 757 }, `${reason.tab} tab`);
          note('his surface is already speeding away: ride until it slows, then step off'); return;
        }
        return startHop(pref, reason);
      }
      if (D.mode === 'anticipate' || D.mode === 'flight') {
        if (D.target && sameAnchor(D.target, pref)) return;
        return retarget(pref, reason);
      }
    }

    /* ------------------------------------------------------------------ Home visits, welcomes, glances */
    function startVisit() {
      D.visit = { start: simT, hadWelcome: false, glances: 0, lookAround: false, nextGlanceAt: simT + 25000 + rand() * 20000, arrivalGlance: false };
      ui.savedSinceVisit = ui.badge;
      if (ui.draft === 'pending' && ui.panelMode !== 'open' && !settings.lowPower) {
        D.visit.arrivalGlance = true;
        after(750, () => glance({ x: 120, y: L.stripTop + 28 }, 'draft strip', 520));
      }
    }
    function glance(pt, label, ms) {
      if (D.mode !== 'attached' || !D.anchor || D.anchor.surface !== 'stage' || D.gesture || D.homeTouch) return false;
      if (D.visit.glances >= 3) return false;
      D.visit.glances++;
      D.reaction = { kind: 'glance', until: simT + ms };
      gazeAt('point', pt, `glance: ${label}`);
      if (!settings.reduceMotion) { const dir = Math.sign(pt.x - D.pos.x); D.facing.target = 0.25 * dir; D.roll.target = clamp((pt.y > D.pos.y ? 1 : -1) * 0 + dir * 3, -5, 5); after(ms, () => { if (D.mode === 'attached') { D.facing.target = 0; D.roll.target = 0; } }); }
      note(`glance at the ${label} (${ms} ms, ${D.visit.glances}/3 this visit)`);
      return true;
    }
    function lookAround() {
      if (D.visit.lookAround) return;
      D.visit.lookAround = true; D.visit.glances++;
      D.gesture = { kind: 'look', t: 0 };
      note('look-around: eyes left, right, back to you (1.4 s)');
    }
    function welcome(kind) {
      if (D.budgets.welcome <= 0) return;
      D.budgets.welcome--; D.visit.hadWelcome = true;
      kind = kind || settings.welcomeKind;
      if (kind === 'back' && !settings.reduceMotion) {
        flickHopInPlace(10 * 1.4, 'welcome back');
        D.welcomeAfterHop = true;
        note('welcome back (3+ days away): one hop in place, pleased, then the default welcome');
        return;
      }
      D.gesture = { kind: kind === 'evening' ? 'welcomeEvening' : 'welcome', t: 0 }; gazeAt('user'); D.activity = 'welcoming';
      note(kind === 'evening' ? 'welcome after 21:00: one slow 280 ms blink and a 3° roll' : 'daily welcome: eyes to you, 5° head roll');
    }

    /* ------------------------------------------------------------------ playful moments */
    function playfulAllowed(where) {
      if (settings.reduceMotion) return 'Playful moments are off with Reduce Motion.';
      if (D.session.playfulUsed >= 1) return 'One playful moment per session; this session has had it.';
      if (ui.panelMode === 'open' || ui.keyboard || ui.voice.live) return 'Not during a task.';
      if (simT - ui.lastTap < 2000) return 'Not within 2 s of a tap.';
      if (D.mode !== 'attached') return 'Not while he is moving.';
      if (where === 'home' && (ui.tab !== 'home' || D.anchor.surface !== 'stage')) return 'This one only happens on Home.';
      if (where === 'home' && D.visit.hadWelcome) return 'Not on a visit that already had the daily welcome.';
      if (where === 'home' && simT - Math.max(D.idleSince, ui.lastInput) < 8000) return 'Needs at least 8 s of idle first.';
      return null;
    }
    function playful(kind, force) {
      const why = force ? null : playfulAllowed(kind === 'trace' ? 'detail' : 'home');
      if (why) { showToastMsg(why); note(`${kind} refused: ${why}`); return false; }
      D.session.playfulUsed++;
      metrics.playful.push({ t: simT, kind, duringTask: ui.panelMode === 'open' || ui.keyboard || ui.voice.live });
      if (kind === 'wave') { D.gesture = { kind: 'wave', t: 0 }; gazeAt('user'); D.activity = 'waving'; note('wave (fixed): arm in front of the head, glove ≥ 5 pt outside it'); }
      if (kind === 'stretch') { D.gesture = { kind: 'stretch', t: 0, fromSit: D.sit.x > 0.3 }; D.breathT = -1; D.activity = 'stretching'; note('stretch: arms up, onto his toes, eyes closed 200 ms, back down'); }
      if (kind === 'trace') { D.gesture = { kind: 'trace', t: 0 }; D.activity = 'tracing the source'; gazeAt('point', { x: 40 + ui.detailX.x, y: L.detailSourceY + 18 }, 'SOURCE'); note('trace the source: eyes to SOURCE, then the arm'); }
      return true;
    }

    /* ------------------------------------------------------------------ UI actions */
    function setTab(tab, src, tapT) {
      if (ui.sheet.open) return;
      if (tab === ui.tab && ui.panelMode !== 'open') { note(`${tab} tapped again`); return; }
      const was = ui.tab;
      if (ui.keyboard) setKeyboard(false);
      if (ui.panelMode === 'open') setPanel('strip', { silent: true });
      if (ui.voice.live || ui.voice.phase === 'starting') endVoice('tab change');
      ui.tab = tab;
      metrics.tabTaps.push({ t: simT, tab, from: was, done: null });
      E.tabs.forEach((b) => { const on = b.dataset.tab === tab; b.setAttribute('aria-selected', on ? 'true' : 'false'); b.classList.toggle('is-on', on); });
      if (tab === 'memories') { ui.badge = false; }
      note(`tap ${tab}: tab content commits this frame`);
      if (D.hiddenBehind && tab !== 'memories') D.hiddenBehind = false;
      updateDestination({ tab, why: `${was} → ${tab}`, tapT: tapT != null ? tapT : simT });
    }
    function setPanel(mode, o = {}) {
      if (ui.draft !== 'pending') return;
      ui.panelMode = mode;
      const target = mode === 'open' ? L.panelOpenTop : mode === 'hidden' ? L.panelHiddenTop : L.stripTop;
      if (settings.reduceMotion) {
        ui.panelTop.snap(target); ui.panelFade = 0;
      } else {
        ui.panelTop.set(mode === 'open' ? 0.42 : 0.34, mode === 'open' ? 0.88 : 0.95); ui.panelTop.target = target;
        if (o.v != null) ui.panelTop.v = o.v;
      }
      E.panel.setAttribute('aria-expanded', mode === 'open' ? 'true' : 'false');
      if (mode === 'open') { ui.lastInput = simT; D.pauseArmed = true; if (ui.keyboard) setKeyboard(false); }
      if (!o.silent) note(mode === 'open' ? 'review opens (panel rises)' : mode === 'hidden' ? 'draft done: the panel clears away' : 'review collapses to the strip');
      if (!o.silent) updateDestination({ why: mode === 'open' ? 'review opened' : 'review collapsed' });
      if (mode === 'open' && !o.noIntro) { ui.introUntil = simT + 2500; after(settings.reduceMotion ? 200 : 520, tryIntro); }
    }
    function setKeyboard(on) {
      if (ui.keyboard === on) return;
      ui.keyboard = on;
      ui.kbTop.target = on ? L.H - L.kbH : L.H;
      E.keyboard.classList.toggle('is-up', on);
      E.composer.classList.toggle('is-focused', on);
      if (on) { D.pauseArmed = true; ui.lastInput = simT; note('message field focused: keyboard rises; he rides the composer'); }
    }
    function typeText(text, msPerChar) { ui.typingTarget = text; ui.typingTimer = 0; ui.typeMs = msPerChar || 42; }
    function onTypeChar() {
      ui.lastInput = simT; D.pauseArmed = true;
      if (D.typingArmed && D.mode === 'attached' && !D.gesture && !D.thinking) { D.typingArmed = false; microReact('typing'); }
      ui.lastTyping = simT;
    }
    function addMessage(who, text) { ui.messages.push({ id: ui.messages.length, who, text, t: simT }); ui.msgVersion++; }
    function send(o = {}) {
      const text = ui.typed.trim() || o.text || 'Tell Mateusz I’m running ten minutes late.';
      addMessage('me', text);
      ui.typed = ''; ui.typingTarget = ''; renderComposer();
      const r = Object.assign({ delay: settings.replyDelay, text: 'Here’s a message for Mateusz. Have a look before it goes.', draft: true, saved: false, fail: settings.replyFails }, ui.nextReply || {}, o.reply || {});
      ui.nextReply = null;
      ui.awaiting = { sentAt: simT, replyAt: simT + r.delay, r, thinkingAt: simT + 600 };
      if (simT - D.lastSendReact > 5000 && D.mode === 'attached') { D.lastSendReact = simT; microReact('send'); }
      note('message sent to Doddy');
    }
    function deliverReply() {
      const a = ui.awaiting; ui.awaiting = null;
      if (!a) return;
      if (a.r.fail) {
        addMessage('err', 'I couldn’t reach my brain just now. Tap to try again.');
        endThinking('failed');
        setMood('concerned', 2400);
        after(30, () => { const p = lastBubblePoint(); notice('error', p, 600, { mood: 'concerned', moodMs: 2400 }); });
        note('reply failed: concerned brow, eyes to the error');
        return;
      }
      addMessage('doddy', a.r.text);
      endThinking('reply');
      after(20, () => { const p = lastBubblePoint(); D.reaction = null; notice('reply lands', p, 300); });
      note('Doddy’s reply lands');
      if (a.r.saved) after(a.r.savedAfter || 420, () => memorySaved());
      if (a.r.draft) after(a.r.draftAfter || 700, () => createDraft());
    }
    function lastBubblePoint() {
      const li = E.thread.lastElementChild;
      if (!li) return { x: 60, y: 400 };
      return { x: E.thread.offsetLeft + li.offsetLeft + 30, y: E.thread.offsetTop + li.offsetTop + 12 };
    }
    function memorySaved() {
      const it = Object.assign({ h: itemHeight(SAVED_ITEM), hs: new Spring(0, 0.34, 1.0) }, SAVED_ITEM);
      it.hs.target = it.h;
      ui.items.unshift(it);
      if (D.anchor && D.anchor.surface.startsWith('rule:')) D.anchor = { surface: `rule:${+D.anchor.surface.slice(5) + 1}`, x: D.anchor.x };
      if (D.target && D.target.surface.startsWith('rule:')) D.target = { surface: `rule:${+D.target.surface.slice(5) + 1}`, x: D.target.x };
      if (D.memory.memories && D.memory.memories.surface.startsWith('rule:')) D.memory.memories = { surface: `rule:${+D.memory.memories.surface.slice(5) + 1}`, x: L.ruleX };
      surfCache.clear();
      buildList();
      if (ui.tab !== 'memories') ui.badge = true;
      notice('saved to Memories', { x: L.tabX.memories, y: 757 }, 400);
      note('saved to Memories (Memories tab gets a dot)');
    }
    function createDraft() {
      ui.draft = 'pending'; ui.introduced = false;
      E.panel.style.display = 'block';
      ui.panelTop.snap(L.panelHiddenTop);
      ui.composerBase.target = L.composerBottomStrip;
      note('draft is reviewable');
      if (D.mode === 'attached' && D.anchor.surface !== 'panel' && ui.tab !== 'talk') notice('draft appears', { x: 120, y: L.stripTop + 20 }, 300);
      setPanel('open');
    }
    function clearDraft() {
      if (ui.draft !== 'pending') return;
      setPanel('hidden');
      ui.composerBase.target = L.composerBottomNoStrip;
      after(600, () => { if (ui.panelMode === 'hidden') { ui.draft = 'none'; E.panel.style.display = 'none'; if (D.anchor && D.anchor.surface === 'panel' && D.mode === 'attached') updateDestination({ why: 'panel gone' }); } });
    }
    function reviewAndSend() {
      if (ui.sheet.open) return;
      ui.sheet.open = true; ui.sheet.y.target = 0; ui.sheet.y.set(0.42, 1.0);
      E.sheetText.textContent = ui.draftText;
      gazeAt('point', { x: 195, y: 560 }, 'Review & send');
      note('Review & send: Apple’s composer opens and covers the app (no “sent” cue yet)');
    }
    function composerResult(result) {
      if (!ui.sheet.open) return;
      ui.sheet.open = false; ui.sheet.y.target = 800; ui.sheet.y.set(0.36, 1.0);
      note(`Apple’s composer returns: ${result}`);
      after(320, () => {
        if (result === 'sent') { setMood('pleased', 900); D.reaction = null; gazeAt('user'); note('sent: pleased mouth only'); after(520, () => { clearDraft(); addMessage('sys', 'Sent to Mateusz in Messages'); }); }
        else if (result === 'cancelled') { gazeAt('point', { x: 60, y: L.panelOpenTop + 112 }, 'draft'); note('cancelled: eyes back to the draft'); }
        else { setMood('concerned', 2200); gazeAt('point', { x: 60, y: L.panelOpenTop + 112 }, 'draft'); note('failed: concerned brow, eyes back to the draft'); }
      });
    }
    function openDetail(i) {
      if (ui.detail.open) return;
      const it = ui.items[i]; if (!it) return;
      ui.detail.open = true; ui.detail.item = i; ui.detailX.set(0.36, 1.0); ui.detailX.target = 0;
      E.detailH.textContent = it.title; E.detailB.textContent = it.words; E.sourceB.textContent = it.source;
      E.detail.setAttribute('aria-hidden', 'false');
      if (D.mode === 'attached' && D.anchor.surface.startsWith('rule:')) {
        D.hiddenBehind = true; D.activity = 'behind the page';
        D.reaction = { kind: 'incoming page', until: simT + 100 }; gazeAt('point', { x: 390, y: 300 }, 'incoming page');
        note('detail page pushed over him: he stays where he is and is covered');
      } else updateDestination({ why: 'detail opened' });
    }
    function closeDetail() {
      if (!ui.detail.open) return;
      ui.detail.open = false; ui.detailX.target = L.W;
      E.detail.setAttribute('aria-hidden', 'true');
      if (D.hiddenBehind) { D.hiddenBehind = false; D.activity = 'resting'; after(120, () => attendContent()); note('page pops: the left edge uncovers first; he is revealed where he stood'); }
      else if (D.mode === 'attached' && D.anchor && D.anchor.surface === 'detail') startHop(preferredAnchor(), { why: 'page leaving' }, { immediate: true });
      else updateDestination({ why: 'detail closed' });
    }
    function setBanner(on) {
      if (ui.banner.show === on) return;
      ui.banner.show = on; ui.banner.y.target = on ? 0 : -120;
      if (on) { notice('offline banner', { x: 195, y: 80 }, 600, { mood: 'concerned' }); D.bannerConcern = true; note('offline banner: eyes to it, concerned brow while it is up'); }
      else { D.bannerConcern = false; if (D.mood === 'concerned') setMood('calm'); if (D.mode === 'attached' && !D.thinking && !D.gesture && (!D.reaction || D.reaction.kind === 'offline banner')) { D.reaction = null; attendContent(); } note('banner gone: calm'); }
    }
    function showToastMsg(text) {
      if (!opts.onToast) return;
      opts.onToast(text);
    }
    /* A toast that slides across just above his head (within 12 pt), then rests where it is told to. */
    function passToast(o = {}) {
      if (typeof o === 'string') o = { text: o };
      const sc = D.scale, headTop = D.pos.y - 96 * sc;
      const t = ui.toast;
      t.text = o.text || 'Saved to Memories'; E.toast.textContent = t.text;
      t.w = o.w || 150; t.lane = o.lane != null ? o.lane : headTop - 8 - 30;
      const fromRight = o.from !== 'left';
      t.restX = o.restX != null ? o.restX : (fromRight ? 24 : L.W - 24 - t.w);
      t.exitX = fromRight ? -t.w - 30 : L.W + 30;
      t.active = true; t.phase = 'in'; t.t = 0; t.x.snap(fromRight ? L.W + 20 : -t.w - 20); t.x.set(o.response || 0.9, 1.0); t.x.target = t.restX; t.prevX = t.x.x;
      t.hold = o.hold || 1400;
      note(`a toast slides ${fromRight ? 'in from the right' : 'in from the left'} just above his head`);
    }
    function setMic(on) {
      ui.mic = on;
      note(on ? 'a microphone button appears in the composer' : 'the microphone button goes away');
    }
    function startVoice() {
      if (!settings.voiceFromHome) return false;
      ui.voice.phase = 'starting'; ui.voice.t = simT;
      D.squint.target = 0; D.dip.target = 0;
      setMood('curious', 0);
      note('press and hold: voice is starting (no listening pose until capture is live)');
      return true;
    }
    function endVoice(why) {
      const wasLive = ui.voice.live || ui.voice.phase === 'starting';
      ui.voice.phase = 'idle'; ui.voice.live = false;
      if (D.listenOn) exitListen();
      setMood('calm');
      if (!wasLive) return;
      note(`capture ends (${why})`);
      if (why === 'tab change') return;
      // follow the conversation to Talk
      addMessage('me', 'Tell Mateusz I’m running ten minutes late.');
      ui.awaiting = { sentAt: simT, replyAt: simT + 1400, r: { text: 'On it. Here’s a message for Mateusz.', draft: false }, thinkingAt: simT + 600 };
      setTab('talk', 'voice');
    }
    function exitListen() {
      D.listenOn = false;
      // the arm leaves the ear in the same frame the microphone turns off
      D.armR1.x = Math.min(D.armR1.x, 75); D.armR2.x = Math.min(D.armR2.x, 55);
      D.armR1.set(0.22, 0.9); D.armR2.set(0.22, 0.9); D.armR1.target = 30; D.armR2.target = 20;
      D.roll.target = 0;
    }
    function tryIntro() {
      if (ui.introduced || ui.panelMode !== 'open' || simT > ui.introUntil) return;
      const onPanel = D.mode === 'attached' && D.anchor && D.anchor.surface === 'panel';
      if (onPanel && simT - D.lastLand >= 600 && !supportMovingNow()) return introduceDraft();
      after(30, tryIntro);
    }
    function introduceDraft() {
      if (ui.introduced || ui.panelMode !== 'open' || D.mode !== 'attached' || !D.anchor || D.anchor.surface !== 'panel') return;
      ui.introduced = true;
      D.gesture = { kind: 'introduce', t: 0 };
      D.activity = 'introducing the draft';
      D.reaction = null;
      gazeAt('point', { x: 40, y: L.panelOpenTop + 112 }, 'draft, first line');
      note('introduce the draft: eyes 0 ms → head 60 ms → arm 200 ms → hold → rest');
    }
    function editDraft() {
      if (D.gesture && D.gesture.kind === 'introduce') {
        D.gesture = null; D.armL1.set(0.12, 1); D.armL2.set(0.12, 1); D.armL1.target = 30; D.armL2.target = 20; D.roll.target = 0;
        gazeAt('point', { x: 120, y: L.panelOpenTop + 112 }, 'your edit');
        note('editing wins: the gesture ends within 180 ms');
      }
    }
    function microReact(kind) {
      if (kind === 'typing') { D.micro = { kind, t: 0, dur: 240 }; gazeAt('point', { x: 120, y: composerTop() + 22 }, 'your text'); if (!settings.reduceMotion) D.roll.target = -3; note('typing starts: eyes to your text, 3° dip (240 ms)'); }
      if (kind === 'send') { D.micro = { kind, t: 0, dur: 280 }; gazeAt('point', { x: 320, y: composerTop() - 160 }, 'sent bubble'); if (!settings.reduceMotion) D.roll.target = 4; note('send: eyes follow the bubble up, 4° nod (280 ms)'); }
      if (kind === 'pause') {
        const inReview = ui.draft === 'pending' && ui.panelMode === 'open';
        D.micro = { kind, t: 0, dur: 280 }; startBlink(280);
        gazeAt('point', inReview ? { x: 60, y: L.panelOpenTop + 112 } : { x: 120, y: composerTop() + 22 }, inReview ? 'draft' : 'composer');
        note('long pause: one slow blink (280 ms), not repeated');
      }
    }
    function startBlink(dur) { D.blinkT = 0; D.blinkDur = dur || 210; }
    function endThinking(why) {
      if (!D.thinking) return;
      D.thinking = null;
      D.roll.set(0.32, 1.0); D.roll.target = 0;
      D.activity = 'resting';
      note(why === 'failed' ? 'thinking ends: the request failed' : 'thinking ends: eyes snap to the reply (88 ms), head straightens (240 ms)');
    }
    function openTalkFromHome(tapT) {
      setTab('talk', 'tap', tapT);
      if (settings.focusOnTalkTap) setKeyboard(true);
    }

    /* ------------------------------------------------------------------ list (Memories) */
    let listEls = [];
    function buildList() {
      relayout();
      E.listC.innerHTML = '';
      listEls = ui.items.map((it, i) => {
        const d = document.createElement('div'); d.className = 'dp-item';
        const mt = 46 + 22 * it.lines, lt = 66 + 22 * it.lines;
        d.innerHTML = `<p class="t" data-zone="text">${it.title}</p><p class="b" data-zone="text">${it.body}</p><p class="m" data-zone="text" style="top:${mt}px">${it.meta}</p><p class="l" data-zone="link" data-item="${i}" style="top:${lt}px" role="button" tabindex="0">View original note</p>`;
        E.listC.appendChild(d);
        const r = document.createElement('div'); r.className = 'dp-rule'; E.listC.appendChild(r);
        return { item: d, rule: r, link: d.querySelector('.l'), lt };
      });
    }
    buildList();

    /* ------------------------------------------------------------------ input: one finger, deterministic */
    const finger = { down: false, x: 0, y: 0, x0: 0, y0: 0, t0: 0, moved: false, target: null, samples: [], vis: 0, vx: 0, vy: 0, source: 'script' };
    function fingerVelocity() {
      const s = finger.samples; if (s.length < 2) return { x: 0, y: 0 };
      const last = s[s.length - 1]; let first = s[0];
      for (let i = s.length - 1; i >= 0; i--) { if (last.t - s[i].t >= 50) { first = s[i]; break; } first = s[i]; }
      const dt = (last.t - first.t) / 1000; if (dt <= 0) return { x: 0, y: 0 };
      return { x: (last.x - first.x) / dt, y: (last.y - first.y) / dt };
    }
    function inRect(x, y, r) { return x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3]; }
    function talkHitRect() { const s = homeScale(), z = zoneOf(s); return [L.stage.x - z.w / 2 - 12, L.stage.y - z.h - 12, L.stage.x + z.w / 2 + 12, L.stage.y + 12]; }
    function hitTest(x, y) {
      if (ui.sheet.open) {
        if (inRect(x, y, [6, 58, 100, 100])) return { kind: 'sheetCancel', tap: () => composerResult('cancelled') };
        const fy = 844 - 360; if (inRect(x, y, [330, fy - 44, 390, fy + 8])) return { kind: 'sheetSend', tap: () => composerResult(settings.composerResult === 'failed' ? 'failed' : 'sent') };
        return { kind: 'none' };
      }
      if (ui.keyboard && y >= ui.kbTop.x) return keyHit(x, y);
      if (y >= L.rail && y < 800) { const tab = x < 130 ? 'home' : x < 260 ? 'talk' : 'memories'; return { kind: 'tab', tab, tap: (t) => setTab(tab, 'tap', t) }; }
      if (ui.draft === 'pending') {
        const top = ui.panelTop.x;
        if (ui.panelMode === 'open' && y >= top && y <= L.panelBottom) {
          const r = y - top;
          if (r < 30) return { kind: 'grab', drag: true, tap: () => setPanel('strip') };
          if (r >= 168 && r <= 218) return { kind: 'reviewSend', tap: () => reviewAndSend() };
          if (r >= 254 && r <= 294 && Math.abs(x - 195) < 80) return { kind: 'later', tap: () => setPanel('strip') };
          if (r >= 88 && r <= 160) return { kind: 'draftText', tap: () => editDraft(), down: () => editDraft() };
          return { kind: 'panel' };
        }
        if (ui.panelMode === 'strip' && y >= top && y <= top + 56 && x >= 16 && x <= 374) return { kind: 'strip', drag: true, tap: () => setPanel('open') };
      }
      if (ui.tab === 'memories' && ui.detail.open && ui.detailX.x < 40) {
        if (inRect(x, y, [12, 88, 130, 124])) return { kind: 'back', tap: () => closeDetail() };
        if (inRect(x, y, [16, L.detailSourceY, 374, L.detailSourceY + 84])) return { kind: 'source', tap: () => playful('trace', false) };
        if (y > 84 && y < 724) return { kind: 'detail' };
      }
      if (ui.tab === 'home') {
        if (ui.voice.live && inRect(x, y, [130, 588, 260, 632])) return { kind: 'stop', tap: () => endVoice('stop tapped') };
        if (inRect(x, y, talkHitRect())) return { kind: 'doddy' };
        return { kind: 'eyes' };
      }
      if (ui.tab === 'talk') {
        const ct = composerTop();
        if (y >= ct && y <= ct + 44 && x >= 16 && x <= 374) {
          if (ui.mic && x >= L.micHit.x0) return { kind: 'mic', tap: () => showToastMsg('Voice in Talk is not part of this prototype.') };
          if (x >= (ui.mic ? L.sendHitMic.x0 : L.sendHit.x0)) return { kind: 'send', tap: () => send() };
          return { kind: 'field', tap: () => { setKeyboard(true); if (!ui.typed && !ui.typingTarget && !opts.scripted) typeText('Tell Mateusz I’m running ten minutes late.'); } };
        }
        return { kind: 'none' };
      }
      if (ui.tab === 'memories') {
        if (y >= L.listTop && y <= listBottom()) return { kind: 'list' };
        return { kind: 'none' };
      }
      return { kind: 'none' };
    }
    function keyHit(x, y) {
      const top = ui.kbTop.x + 10, row = Math.floor((y - top) / 54);
      const rows = [['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'], ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'], ['z', 'x', 'c', 'v', 'b', 'n', 'm', '⌫']];
      if (row >= 0 && row < 3) {
        const keys = rows[row], w = keys.length * 32 + (keys.length - 1) * 6, x0 = (390 - w) / 2, i = Math.floor((x - x0) / 38);
        if (i >= 0 && i < keys.length) return { kind: 'key', tap: () => { const k = keys[i]; if (k === '⌫') ui.typed = ui.typed.slice(0, -1); else ui.typed += k; renderComposer(); onTypeChar(); } };
      }
      if (row === 3) { if (x >= 48 && x <= 248) return { kind: 'key', tap: () => { ui.typed += ' '; renderComposer(); onTypeChar(); } }; if (x > 254) return { kind: 'key', tap: () => setKeyboard(false) }; }
      return { kind: 'none' };
    }
    function fingerDown(x, y, source) {
      finger.down = true; finger.x = x; finger.y = y; finger.x0 = x; finger.y0 = y; finger.t0 = simT; finger.moved = false; finger.samples = [{ t: simT, x, y }]; finger.source = source || 'script';
      ui.lastInput = simT;
      const t = hitTest(x, y); finger.target = t;
      if (t.down) t.down();
      if (ui.tab === 'home' && t.kind !== 'doddy' && t.kind !== 'stop' && D.mode === 'attached' && !ui.sheet.open) { D.reaction = null; gazeAt('finger', {}, 'your finger'); D.followFinger = true; }
      if (t.kind === 'doddy') homeTouchDown(x, y);
      if (t.kind === 'list') listDown(x, y);
      if (t.kind === 'strip' || t.kind === 'grab') { t.panel0 = ui.panelTop.x; }
    }
    function fingerMove(x, y) {
      if (!finger.down) return;
      finger.x = x; finger.y = y; finger.samples.push({ t: simT, x, y }); if (finger.samples.length > 30) finger.samples.shift();
      const v = fingerVelocity(); finger.vx = v.x; finger.vy = v.y;
      if (!finger.moved && hyp(x - finger.x0, y - finger.y0) > M.tapSlop) finger.moved = true;
      const t = finger.target; if (!t) return;
      if (t.kind === 'doddy') homeTouchMove(x, y);
      if (t.kind === 'list') listMove(x, y);
      if ((t.kind === 'strip' || t.kind === 'grab') && finger.moved) panelDragMove(t, y);
    }
    function fingerUp() {
      if (!finger.down) return;
      const v = fingerVelocity(); finger.vx = v.x; finger.vy = v.y;
      finger.down = false;
      const t = finger.target; finger.target = null;
      ui.lastInput = simT;
      if (D.followFinger) { D.followFinger = false; after(300, () => { if (D.gaze.kind === 'finger' && !finger.down) gazeAt('user'); }); }
      if (!t) return;
      if (t.kind === 'doddy') return homeTouchUp();
      if (t.kind === 'list') return listUp();
      if ((t.kind === 'strip' || t.kind === 'grab') && ui.panelDrag) return panelDragEnd();
      if (!finger.moved && t.tap) { ui.lastTap = simT; t.tap(simT); }
    }

    /* Home: touching Doddy */
    function homeTouchDown(x, y) {
      const hp = headPos(), s = D.scale;
      D.homeTouch = { t0: simT, x0: x, y0: y, kind: null, onHead: hyp(x - hp.x, y - hp.y) <= (17.5 + 10) * s, holdFired: false, lastX: x };
      if (D.mode !== 'attached' || !D.anchor || D.anchor.surface !== 'stage') return;
      D.reaction = null; D.gesture = null; D.breathT = -1;
      D.squint.set(0.05, 1.0); D.squint.target = 1;
      if (!settings.reduceMotion) { D.dip.set(0.06, 1.0); D.dip.target = 3 / s; }
      note('touch down on him: squints and dips 3 pt within 60 ms');
    }
    function homeTouchMove(x, y) {
      const ht = D.homeTouch; if (!ht) return;
      if (!ht.kind && finger.moved) {
        ht.kind = ht.onHead ? 'stroke' : 'drag';
        D.squint.target = 0; D.dip.target = 0;
        if (ui.voice.phase === 'starting') { ui.voice.phase = 'idle'; setMood('calm'); }
        note(ht.kind === 'stroke' ? 'stroke across his head' : 'drag on his body');
      }
      if (ht.kind === 'drag') {
        const dx = x - ht.x0, dy = y - ht.y0, s = D.scale;
        D.lean.set(0.12, 1.0); D.lean.target = 12 * Math.tanh(dx / 60);
        D.dragC.set(0.10, 1.0); D.dragC.target = dy > 0 ? 6 * Math.tanh(dy / 50) / s : 0;
        D.stretchUp.set(0.10, 1.0); D.stretchUp.target = dy < 0 ? 0.06 * Math.tanh(-dy / 60) : 0;
        gazeAt('finger', {}, 'your finger');
      }
      if (ht.kind === 'stroke') {
        const hp = headPos(), s = D.scale;
        const speed = hyp(finger.vx, finger.vy);
        const over = hyp(x - hp.x, y - hp.y) <= (17.5 + 14) * s;
        const dxm = x - ht.lastX; ht.lastX = x;
        if (over && speed < 600) {
          if (!D.rub.active) startRub();
          if (D.rub.active && !D.rub.smileOnly && !settings.reduceMotion && Math.abs(dxm) > 0.2) { D.roll.set(0.16, 0.9); D.roll.target = 6 * Math.sign(dxm); }
        } else if (D.rub.active) endRub();
      }
    }
    function startRub() {
      D.rub.starts = D.rub.starts.filter((t) => simT - t < 60000);
      if (simT - D.rub.lastStart < 1500) return; // one per 1.5 s
      D.rub.active = true; D.rub.lastStart = simT; D.rub.starts.push(simT);
      D.rub.smileOnly = D.rub.starts.length > 5;
      setMood('pleased', 0);
      if (!D.rub.smileOnly) { D.shut.target = 1; gazeAt('user'); }
      D.activity = 'head rub';
      note(D.rub.smileOnly ? 'head rub (6th in a minute): only a smile' : 'head rub: eyes close, pleased, head tips with the stroke');
    }
    function endRub() {
      if (!D.rub.active) return;
      D.rub.active = false; D.rub.lastEnd = simT;
      D.roll.set(0.24, 0.8); D.roll.target = 0;
      after(300, () => { if (!D.rub.active) { D.shut.target = 0; gazeAt('user'); after(400, () => { if (!D.rub.active && D.mood === 'pleased') setMood('calm'); }); } });
      D.activity = 'resting';
    }
    function homeTouchUp() {
      const ht = D.homeTouch; D.homeTouch = null;
      D.squint.target = 0; D.dip.target = 0;
      if (!ht) return;
      const vy = finger.vy, now = simT;
      if (ui.voice.phase === 'starting' || ui.voice.live) { endVoice('released'); return; }
      if (D.rub.active) endRub();
      if (ht.kind === 'drag' || ht.kind === 'stroke') {
        const rm = settings.reduceMotion;
        for (const sp of [D.lean, D.dragC, D.stretchUp]) sp.set(0.30, rm ? 1.0 : 0.55);
        D.lean.target = 0; D.dragC.target = 0; D.stretchUp.target = 0;
        if (vy < -900 && now - D.lastFlick >= 3000 && !rm && D.mode === 'attached' && D.anchor.surface === 'stage') {
          D.lastFlick = now; D.lean.snap(0); D.dragC.snap(0);
          flickHopInPlace(clamp(-vy / 80, 8, 24) * 1.4, 'upward flick');
        } else note('released: springs back with one overshoot (0.30/0.55)');
        return;
      }
      if (ht.kind === 'holdTap' || (!ht.kind && now - ht.t0 < M.hold) || (!ht.kind && !settings.voiceFromHome)) {
        ui.lastTap = now;
        note('tap on him: Talk opens');
        openTalkFromHome(now);
      }
    }
    function flickHopInPlace(A, why) {
      if (D.mode !== 'attached') return;
      stopIdlePoses();
      const p = anchorPoint(D.anchor);
      D.target = D.anchor; D.curHop = { tReq: simT, tap: simT, why, from: D.anchor.surface, to: D.anchor.surface, ant: 0, s0: D.scale, s1: D.scale, inPlace: true };
      D.flight = { p0: p, p1: p, t0: simT, m0: { x: 0, y: 0 }, m1: { x: 0, y: 0 }, h: A, T: M.flight(0, 0), t: 0, s0: D.scale, s1: D.scale, kind: 'flick' };
      Object.assign(D.curHop, { takeoff: simT, crouch: 0, T: D.flight.T, D: 0, A });
      D.mode = 'flight'; D.airStart = simT; D.airborne = 0; D.activity = 'hop in place'; D.trail = [];
      D.stretchUp.target = 0; D.squash.x = 1; D.squash.target = 0;
      D.armL1.target = 105; D.armL2.target = 135; D.armR1.target = 105; D.armR2.target = 135;
      for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(0.14, 0.9);
      D.tuck.set(0.18, 0.9); D.tuck.target = 0.7;
      D.anchor = null;
      setMood('pleased', 1200);
      note(`${why}: hop in place, apex ${fmt(A, 1)} pt`);
    }

    /* Memories: scrolling */
    const rubber = (d, dim) => (1 - 1 / ((d * 0.55) / dim + 1)) * dim;
    function listDown(x, y) {
      const sc = scrollState; sc.dragging = false;
      if (sc.mode === 'momentum' || sc.mode === 'bounce' || sc.mode === 'toTop') { sc.mode = 'idle'; sc.v = 0; }
      sc.d0 = sc.y; sc.f0 = y;
    }
    function listMove(x, y) {
      const sc = scrollState;
      if (!finger.moved) return;
      // the pan starts where it is recognised: content never jumps by the touch slop
      if (!sc.dragging) { sc.dragging = true; sc.d0 = sc.y; sc.f0 = y; }
      sc.mode = 'drag';
      const raw = sc.d0 - (y - sc.f0), max = maxScroll(), dim = L.listBottomBase - L.listTop;
      sc.y = raw < 0 ? -rubber(-raw, dim) : raw > max ? max + rubber(raw - max, dim) : raw;
    }
    function listUp() {
      const sc = scrollState; sc.dragging = false;
      if (!finger.moved) { // tap
        const yC = finger.y - L.listTop + sc.y;
        for (let i = 0; i < ui.layout.length; i++) {
          const lay = ui.layout[i], le = listEls[i]; if (!le) continue;
          const lt = lay.top + le.lt;
          if (yC >= lt && yC <= lt + 30 && finger.x >= 20 && finger.x <= 180) { ui.lastTap = simT; openDetail(i); return; }
        }
        return;
      }
      const v = -finger.vy, max = maxScroll();
      if (sc.y < 0 || sc.y > max) { sc.mode = 'bounce'; sc.spring.x = sc.y; sc.spring.v = v; sc.spring.target = sc.y < 0 ? 0 : max; sc.spring.set(0.4, 1.0); }
      else if (Math.abs(v) > 30) { sc.mode = 'momentum'; sc.v = v; }
      else { sc.mode = 'idle'; sc.v = 0; }
      note(`scroll released at ${fmt(Math.abs(v))} pt/s`);
    }
    function scrollToTop() { const sc = scrollState; sc.mode = 'toTop'; sc.spring.x = sc.y; sc.spring.v = sc.vel; sc.spring.target = 0; sc.spring.set(0.5, 1.0); note('scroll to top'); }
    function stepScroll(dt) {
      const sc = scrollState, max = maxScroll();
      sc.prevY = sc.lastY != null ? sc.lastY : sc.y; // includes this step's finger drag
      if (sc.mode === 'momentum') {
        sc.v *= Math.pow(0.998, dt * 1000); sc.y += sc.v * dt;
        if (sc.y < 0 || sc.y > max) { sc.mode = 'bounce'; sc.spring.x = sc.y; sc.spring.v = sc.v; sc.spring.target = sc.y < 0 ? 0 : max; sc.spring.set(0.4, 1.0); }
        else if (Math.abs(sc.v) < 8) { sc.mode = 'idle'; sc.v = 0; }
      } else if (sc.mode === 'bounce' || sc.mode === 'toTop') {
        sc.spring.step(dt); sc.y = sc.spring.x; sc.v = sc.spring.v;
        if (Math.abs(sc.spring.x - sc.spring.target) < 0.05 && Math.abs(sc.spring.v) < 2) { sc.y = sc.spring.target; sc.v = 0; sc.mode = 'idle'; }
      }
      sc.vel = dt > 0 ? (sc.y - sc.prevY) / dt : 0; sc.lastY = sc.y;
      if (Math.abs(sc.vel) < M.lily.settleSpeed) { if (!sc.slowSince) sc.slowSince = simT; } else sc.slowSince = 0;
      if (sc.mode === 'idle' && sc.wasMoving) { sc.wasMoving = false; sc.endedAt = simT; }
      if (sc.mode !== 'idle') sc.wasMoving = true;
    }
    /* Doddy in a scrolling list: ride, lily-pad hop, or wait on the rail. */
    function stepScrollRiding() {
      if (ui.tab !== 'memories' || ui.detail.open || ui.draft === 'pending' || D.calm || ui.sheet.open) return;
      const sc = scrollState, speed = Math.abs(sc.vel);
      if (D.mode === 'attached' && D.anchor && D.anchor.surface.startsWith('rule:')) {
        const i = +D.anchor.surface.slice(5);
        const fast = speed > M.lily.slow || sc.mode === 'toTop' || (sc.mode === 'momentum' && Math.abs(sc.v) > M.lily.slow);
        if (fast) { D.scrollWait = true; startHop({ surface: 'rail', x: L.tabX.memories }, { why: sc.mode === 'toTop' ? 'scroll to top' : 'fast scroll' }); return; }
        const yNow = ruleY(i), yp = yNow - sc.vel * (M.lily.look / 1000);
        const leaving = yp - 96 < L.listTop || yp > listBottom();
        if (leaving && speed > 1) {
          const vRule = -sc.vel, incomingBelow = vRule < 0;
          if (simT - D.lastLily >= M.lily.gap && speed < M.lily.slow) {
            const vh = listVH(), b0 = L.listTop + 0.2 * vh, b1 = L.listTop + 0.8 * vh;
            const cands = [];
            for (let j = 0; j < ui.layout.length; j++) {
              if (j === i || ruleUnderFinger(j)) continue;
              const y = L.listTop + ui.layout[j].bottom - scrollAhead(0.45);
              if (y >= b0 && y <= b1 && (incomingBelow ? j > i : j < i)) cands.push({ j, d: Math.abs(j - i) });
            }
            cands.sort((a, b) => a.d - b.d);
            if (cands.length) { D.lastLily = simT; startHop({ surface: `rule:${cands[0].j}`, x: L.ruleX }, { why: 'lily-pad hop (rule leaving the safe band)' }); return; }
          }
          D.scrollWait = true; startHop({ surface: 'rail', x: L.tabX.memories }, { why: 'rule leaving and no lily pad allowed: wait on the rail' });
        }
        return;
      }
      if (D.mode === 'attached' && D.anchor && D.anchor.surface === 'rail' && D.scrollWait && !finger.down) {
        if (sc.slowSince && simT - sc.slowSince >= M.lily.settleFor) {
          const vh = listVH(), b0 = L.listTop + 0.2 * vh, b1 = L.listTop + 0.8 * vh;
          let pick = null;
          for (let j = 0; j < ui.layout.length; j++) { const y = L.listTop + ui.layout[j].bottom - scrollAhead(0.45); if (y >= b0 && y <= b1) { pick = j; break; } }
          D.scrollWait = false;
          if (pick != null) startHop({ surface: `rule:${pick}`, x: L.ruleX }, { why: 'list settled: one hop to the best rule' });
          else note('list settled but no rule fits: he stays on the rail');
        }
      }
    }

    /* Draft panel dragged by the finger (flick to open) */
    function panelDragMove(t, y) {
      if (!ui.panelDrag) { ui.panelDrag = { y0: ui.panelTop.x, f0: y }; D.reaction = null; gazeAt('anchor', { anchor: { surface: 'panel', x: 195 } }, 'grabber'); note('panel dragged: eyes on the grabber for the whole drag'); }
      const raw = ui.panelDrag.y0 + (y - ui.panelDrag.f0);
      const top = raw < L.panelOpenTop ? L.panelOpenTop - rubber(L.panelOpenTop - raw, 300) : Math.min(raw, L.panelHiddenTop);
      ui.panelTop.v = finger.vy; ui.panelTop.x = top;
    }
    function panelDragEnd() {
      const vy = finger.vy; ui.panelDrag = null;
      const open = vy < -700 || (ui.panelTop.x < (L.stripTop + L.panelOpenTop) / 2 && vy < 700);
      gazeAt('anchor', { anchor: { surface: 'panel', x: D.anchor ? D.anchor.x : L.draftX } }, 'panel edge');
      if (open) { setPanel('open', { v: clamp(vy, -4000, 4000) }); note(`flicked open at ${fmt(Math.abs(vy))} pt/s`); }
      else setPanel('strip', { v: clamp(vy, -4000, 4000) });
    }

    /* ------------------------------------------------------------------ script runner */
    let script = null;
    function runScript(sc) {
      script = { def: sc, start: simT, tl: (sc.timeline || []).slice().sort((a, b) => a[0] - b[0]), fk: (sc.finger || []).slice().sort((a, b) => a.t - b.t), fi: 0, last: null };
      opts.scripted = true;
    }
    function stopScript() { script = null; opts.scripted = false; if (finger.down && finger.source === 'script') fingerUp(); }
    function scriptStep() {
      if (!script) return;
      const t = simT - script.start;
      while (script.tl.length && script.tl[0][0] <= t) { const [, fn] = script.tl.shift(); fn(api); }
      const fk = script.fk;
      while (script.fi < fk.length && fk[script.fi].t <= t) {
        const k = fk[script.fi++];
        if (k.type === 'down') { fingerDown(k.x, k.y, 'script'); script.last = k; }
        else if (k.type === 'move') { fingerMove(k.x, k.y); script.last = k; }
        else if (k.type === 'up') { fingerUp(); script.last = k; }
      }
      const nx = fk[script.fi];
      if (nx && nx.type === 'move' && finger.down && script.last) {
        const a = script.last, u = clamp((t - a.t) / Math.max(1, nx.t - a.t), 0, 1), e = nx.ease === 'linear' ? u : nx.ease === 'out' ? 1 - (1 - u) * (1 - u) : nx.ease === 'in' ? u * u : smoothstep(0, 1, u);
        fingerMove(lerp(a.x, nx.x, e), lerp(a.y, nx.y, e));
      }
      if (script.def.duration && t >= script.def.duration && !script.done) { script.done = true; if (opts.onScriptEnd) opts.onScriptEnd(script.def); }
    }

    /* ------------------------------------------------------------------ step */
    function step(dtMs) {
      const dt = dtMs / 1000;
      simT += dtMs;
      for (let i = timers.length - 1; i >= 0; i--) if (timers[i].at <= simT) { const tm = timers.splice(i, 1)[0]; tm.fn(); }
      scriptStep();
      // press and hold on Doddy
      const ht = D.homeTouch;
      if (ht && finger.down && !ht.kind && !finger.moved && simT - ht.t0 >= M.hold && !ht.holdFired) {
        ht.holdFired = true;
        if (startVoice()) ht.kind = 'voice'; else { ht.kind = 'holdTap'; note('hold: voice can’t start from Home here, so it acts as a tap on release'); }
      }
      // UI springs
      ui.panelPrevTop = ui.panelTop.x;
      if (!ui.panelDrag) ui.panelTop.step(dt);
      ui.kbTop.step(dt); ui.composerBase.step(dt); ui.detailX.step(dt); ui.sheet.y.step(dt); ui.banner.y.step(dt);
      if (!ui.keyboard && ui.kbTop.x > L.H - 4 && ui.kbTop.x !== L.H) ui.kbTop.snap(L.H);
      let lay = false; for (const it of ui.items) if (it.hs) { it.hs.step(dt); lay = true; if (it.hs.resting) { it.hs = null; } }
      if (lay) relayout();
      stepScroll(dt);
      {
        const ctLive = composerTop(), ctRest = composerBottomAt(ui.composerBase.target, ui.kbTop.target) - L.composerH;
        const occLive = ui.draft === 'pending' && ui.panelTop.x < ctLive ? ui.panelTop.x : ctLive;
        const occRest = ui.draft === 'pending' && ui.panelTop.target < ctRest ? ui.panelTop.target : ctRest;
        ui.threadOcc.target = Math.min(occLive, occRest); ui.threadOcc.step(dt);
      }
      for (const k in ui.dips) { ui.dips[k].target = 0; ui.dips[k].step(dt); }
      for (const k in ui.fade) {
        const tgt = k === ui.tab ? 1 : 0, d = dtMs / M.uiFade;
        ui.fade[k] = tgt > ui.fade[k] ? Math.min(tgt, ui.fade[k] + d) : Math.max(tgt, ui.fade[k] - d);
      }
      for (const tt of metrics.tabTaps) if (tt.done == null && ui.fade[tt.tab] >= 1) tt.done = simT - tt.t;
      if (ui.panelFade != null && ui.panelFade < 1) ui.panelFade = Math.min(1, ui.panelFade + dtMs / 150);
      ui.micFade = clamp(ui.micFade + (ui.mic ? 1 : -1) * dtMs / 150, 0, 1);
      // typing
      if (ui.typingTarget && ui.typed.length < ui.typingTarget.length) {
        ui.typingTimer += dtMs;
        while (ui.typingTimer > (ui.typeMs || 42) && ui.typed.length < ui.typingTarget.length) { ui.typingTimer -= (ui.typeMs || 42); ui.typed = ui.typingTarget.slice(0, ui.typed.length + 1); onTypeChar(); }
        renderComposer();
        if (ui.typed.length >= ui.typingTarget.length) ui.typingTarget = '';
      }
      if (simT - ui.lastTyping > 3000) D.typingArmed = true;
      // reply timing & thinking
      const aw = ui.awaiting;
      if (aw) {
        if (!D.thinking && simT >= aw.thinkingAt && simT < aw.replyAt && D.mode === 'attached' && D.anchor && D.anchor.surface === 'composer') {
          D.thinking = { t0: simT, blinked: false }; D.micro = null;
          gazeAt('dir', { x: 0.78, y: -0.68 }, 'thinking (up and right)');
          if (!settings.reduceMotion) { D.roll.set(0.28, 0.9); D.roll.target = 4; }
          D.activity = 'thinking';
          note('no reply after 600 ms: thinking pose (eyes up right, head 4°), held still');
        }
        if (D.thinking && !D.thinking.blinked && simT >= aw.sentAt + 4000) {
          D.thinking.blinked = true; startBlink(280);
          after(140, () => { if (D.thinking) gazeAt('dir', { x: -0.78, y: -0.66 }, 'thinking (up and left)'); });
          note('still waiting at 4 s: one slow blink, eyes to the upper left once');
        }
        if (simT >= aw.replyAt) deliverReply();
      }
      // voice capture
      const vo = ui.voice;
      if (vo.phase === 'starting' && simT - vo.t >= 150) { vo.phase = 'live'; vo.live = true; note('capture is live: microphone indicator on, listening pose'); }
      // toast
      const to = ui.toast;
      if (to.active) {
        to.prevX = to.x.x; to.x.step(dt); to.t += dtMs;
        if (to.phase === 'in' && Math.abs(to.x.x - to.restX) < 0.5 && to.t > 300) { to.phase = 'rest'; to.restT = simT; }
        if (to.phase === 'rest' && simT - to.restT > to.hold) { to.phase = 'out'; to.x.set(0.5, 1.0); to.x.target = to.exitX; }
        if (to.phase === 'out' && Math.abs(to.x.x - to.exitX) < 4) { to.active = false; }
      }
      // calm mode release
      if (D.calm && simT - D.lastChange > M.calm.quiet && D.mode === 'attached') { D.calm = false; D.changes = []; note('input settled for 350 ms: one hop to the final spot'); updateDestination({ why: 'calm mode over' }); }
      stepScrollRiding();
      stepDoddy(dtMs, dt);
    }

    function stepDoddy(dtMs, dt) {
      const prevPos = { x: D.pos.x, y: D.pos.y };
      D.surfaceVel = { x: 0, y: 0 };
      if (D.mode === 'attached' || D.mode === 'anticipate' || D.mode === 'shuffle') {
        if (D.anchor) {
          if (D.pendingPickup && ui.draft === 'pending') {
            const top = ui.panelTop.x, footNow = anchorPoint(D.anchor).y;
            if (ui.panelPrevTop - D.pos.y > -0.5 && top - footNow <= 0.5) {
              D.pendingPickup = false; D.anchor = { surface: 'panel', x: clamp(D.pos.x, 40, 330) }; D.z = 2.2; D.activity = 'riding'; resetSupportVel(D.anchor);
              D.crouch.set(0.25, 0.55); D.crouch.v += clamp(Math.abs((ui.panelPrevTop - top) / dt) * 0.012, 0, 30);
              gazeAt('anchor', { anchor: D.anchor }, 'panel edge');
              note('picked up by the panel edge');
            }
          }
          if (D.pendingTransfer && D.anchor.surface === 'panel') {
            const s = S(D.pendingTransfer.surface), top = s.top();
            if (ui.panelTop.x >= top - 0.5) {
              D.anchor = D.pendingTransfer; D.pendingTransfer = null; D.z = S(D.anchor.surface).layer + 0.2; D.activity = 'resting'; resetSupportVel(D.anchor);
              D.crouch.set(0.25, 0.55); D.crouch.v += 18; dip(D.anchor.surface).v += 25;
              D.memory[screenKey()] = { surface: D.anchor.surface, x: D.anchor.x };
              after(150, () => attendContent());
              note(`stepped across onto ${D.anchor.surface} as the panel passed`);
            }
          }
          if (D.mode === 'shuffle') stepShuffle(dtMs);
          const p = anchorPoint(D.anchor);
          D.pos.x = p.x; D.pos.y = p.y;
        }
      }
      if (D.mode === 'anticipate') {
        D.phaseT += dtMs;
        if (D.phaseT >= D.antDur) { D.surfaceVel = { x: (D.pos.x - prevPos.x) / Math.max(dt, 1e-4), y: (D.pos.y - prevPos.y) / Math.max(dt, 1e-4) }; takeOff(); }
      }
      if (D.mode === 'flight') {
        D.flight.t = simT - D.flight.t0; D.airborne = simT - D.airStart; D.phaseT = D.flight.t;
        if (D.flight.kind !== 'flick') {
          const touch = pointAt(D.target, Math.max(0, (D.flight.T - D.flight.t) / 1000));
          if (hyp(touch.x - D.flight.p1.x, touch.y - D.flight.p1.y) > 2) retarget(D.target, { why: 'its surface changed course' }, { force: true });
        }
        const f = D.flight; f.t = simT - f.t0;
        const s = clamp(f.t / f.T, 0, 1);
        if (f.kind !== 'flick') { const p1 = pointAt(D.target, Math.max(0, (f.T - f.t) / 1000)); f.p1 = p1; f.m1 = { x: p1.x - f.p0.x, y: p1.y - f.p0.y }; }
        const p = flightPoint(f, s);
        D.pos.x = p.x; D.pos.y = p.y;
        D.vel = flightVelocity(f, s);
        D.scale = f.s0 + (f.s1 - f.s0) * smoothstep(0.15, 0.9, s);
        D.trail.push(`${p.x.toFixed(1)},${p.y.toFixed(1)}`); if (D.trail.length > 160) D.trail.shift();
        if (s > 0.55) { D.armL1.set(0.2, 0.9); D.armL2.set(0.2, 0.9); D.armR1.set(0.2, 0.9); D.armR2.set(0.2, 0.9); D.armL1.target = 32; D.armL2.target = 30; D.armR1.target = 32; D.armR2.target = 30; D.tuck.target = 0.2; }
        if (s >= 1) { land(); if (D.welcomeAfterHop) { D.welcomeAfterHop = false; after(420, () => { D.gesture = { kind: 'welcome', t: 0 }; gazeAt('user'); }); } }
      }
      if (D.mode === 'fade') {
        D.phaseT += dtMs;
        if (D.phaseT < D.fadeOutMs) D.opacity = Math.min(D.opacity, 1 - D.phaseT / D.fadeOutMs);
        else {
          if (!D.fadeMoved) {
            D.fadeMoved = true; D.anchor = D.target; D.scale = scaleFor(D.anchor);
            const p = anchorPoint(D.anchor); D.pos.x = p.x; D.pos.y = p.y; D.z = S(D.anchor.surface).layer + 0.2;
            D.memory[screenKey()] = { surface: D.anchor.surface, x: D.anchor.x };
            if (D.anchor.surface === 'stage') startVisit();
          }
          if (D.target && D.target !== D.anchor) { D.anchor = D.target; D.scale = scaleFor(D.anchor); }
          const p = anchorPoint(D.anchor); D.pos.x = p.x; D.pos.y = p.y;
          // placement: one fully invisible frame (20 ms) between the fade out and the fade in, so size and place change unseen
          D.opacity = clamp((D.phaseT - D.fadeOutMs - 20) / D.fadeInMs, 0, 1);
          if (D.phaseT >= D.fadeOutMs + 20 + D.fadeInMs) { D.mode = 'attached'; D.target = null; D.fadeMoved = false; D.vel = { x: 0, y: 0 }; D.accHist = []; D.justLanded = true; D.opacity = 1; D.activity = 'resting'; D.lastLand = simT; D.idleSince = simT; D.breathT = simT + 2000; attendContent(); }
        }
      }
      if (D.mode === 'attached' || D.mode === 'shuffle') {
        if (D.justLanded) { D.justLanded = false; prevPos.x = D.pos.x - D.vel.x * dt; prevPos.y = D.pos.y - D.vel.y * dt; }
        if (D.opacity < 1 && D.mode === 'attached') D.opacity = Math.min(1, D.opacity + dtMs / 150);
        const vy = (D.pos.y - prevPos.y) / Math.max(dt, 1e-4);
        const ay = (vy - D.vel.y) / Math.max(dt, 1e-4);
        D.vel = { x: (D.pos.x - prevPos.x) / Math.max(dt, 1e-4), y: vy };
        // weight response (rig units; up to 3 pt at 1.0×)
        if (!settings.reduceMotion && Math.abs(vy) > 1) { D.crouch.set(0.25, 0.55); const kw = (2 * Math.PI / 0.25) ** 2; D.crouch.force = clamp(-ay * 0.026 / D.scale, -3 * kw, 3 * kw); }
        else D.crouch.force = 0;
        // brace: mean acceleration of his support over the last 100 ms (rules excluded: overscroll gets the weight response only)
        D.accHist.push({ t: simT, vx: D.vel.x, vy: D.vel.y });
        while (D.accHist.length > 1 && simT - D.accHist[0].t > 100) D.accHist.shift();
        const h0 = D.accHist[0], span = (simT - h0.t) / 1000;
        D.supAcc = span >= 0.05 ? hyp(D.vel.x - h0.vx, D.vel.y - h0.vy) / span : 0;
        const moving = supportMovingNow();
        if (settings.traceAcc) metrics.accTrace = (metrics.accTrace || []).concat([[Math.round(simT), Math.round(D.supAcc), Math.round(D.vel.y)]]);
        const braceable = D.anchor && !D.anchor.surface.startsWith('rule:');
        if (moving) D.brace.peak = Math.max(D.brace.peak, D.supAcc);
        if (!settings.reduceMotion && braceable && moving && !D.brace.done && !D.brace.on && D.supAcc > settings.braceOn) {
          D.brace.on = true; D.brace.done = true;
          for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(0.12, 0.8);
          D.armL1.target = 55; D.armL2.target = 45; D.armR1.target = 55; D.armR2.target = 45;
          metrics.braces.push({ t: simT, acc: Math.round(D.supAcc) });
          note(`brace: support accelerating at ${fmt(D.supAcc / 1000, 1)}k pt/s², arms out 25°`);
        }
        if (D.brace.on) {
          if (D.supAcc < settings.braceOff) { if (!D.brace.lowSince) D.brace.lowSince = simT; } else D.brace.lowSince = 0;
          if ((D.brace.lowSince && simT - D.brace.lowSince >= 120) || !moving) { D.brace.on = false; D.brace.lowSince = 0; resetArms(0.3); note('brace released: the push has passed'); }
        }
        if (!moving && D.activity !== 'riding' && (D.brace.done || D.brace.peak)) { if (D.brace.peak > 1000) metrics.ridePeaks.push({ t: simT, surface: D.anchor ? D.anchor.surface : '?', peak: Math.round(D.brace.peak) }); D.brace.done = false; D.brace.peak = 0; }
        if (moving && (D.activity === 'resting' || D.activity === 'landing')) D.activity = 'riding';
        if (!moving && D.activity === 'riding' && !D.pendingTransfer && !D.pendingPickup) { D.activity = 'resting'; D.brace.done = false; if (D.brace.peak > 1000) metrics.ridePeaks.push({ t: simT, surface: D.anchor ? D.anchor.surface : '?', peak: Math.round(D.brace.peak) }); D.brace.peak = 0; }
        if (D.activity === 'landing' && simT - D.lastLand > 340) D.activity = 'resting';
        if (D.pendingStepOff && Math.abs(D.vel.y) < 150) { const ps = D.pendingStepOff; D.pendingStepOff = null; startHop(ps.target, ps.reason); }
        // shuffle trigger: his spot is no longer valid on this surface
        if (D.mode === 'attached' && D.anchor && !D.hiddenBehind) {
          const xr = S(D.anchor.surface).xr();
          if (D.anchor.x < xr[0] - 0.5 || D.anchor.x > xr[1] + 0.5) {
            if (!moving) startShuffle(clamp(D.anchor.x, xr[0], xr[1]), 'clear zone');
          }
        }
      } else D.crouch.force = 0;
      stepGesture(dtMs);
      if (D.micro) { D.micro.t += dtMs; if (D.micro.t > D.micro.dur * 0.5) D.roll.target = D.thinking ? 4 : 0; if (D.micro.t > D.micro.dur) { D.micro = null; after(700, () => { if (D.mode === 'attached' && !D.gesture && !D.thinking && !D.micro) attendContent(); }); } }
      if (D.reaction && simT >= D.reaction.until) { const k = D.reaction.kind; D.reaction = null; if (!D.thinking && !D.gesture && D.mode === 'attached') { if (k === 'offline banner' && ui.banner.show) gazeAt('point', { x: 195, y: 80 }, 'banner'); else attendContent(); } }
      if (D.userGazeAt && simT >= D.userGazeAt && D.mode === 'attached' && !D.reaction && !D.gesture && !D.thinking && !D.micro && D.gaze.kind === 'point' && !D.followFinger && !(ui.banner.show)) { D.userGazeAt = 0; if (ui.tab === 'home' || screenKey() === 'review' || ui.tab === 'talk' || ui.tab === 'memories') gazeAt('user'); }
      if (D.bannerConcern && ui.banner.show && D.mood !== 'concerned' && !D.thinking) setMood('concerned');
      if (D.moodUntil && simT >= D.moodUntil) { D.moodUntil = 0; D.mood = D.bannerConcern ? 'concerned' : 'calm'; }
      // listening: only while capture is live
      const live = ui.voice.live;
      if (live && !D.listenOn && D.mode === 'attached') {
        D.listenOn = true; setMood('calm');
        D.armR1.set(0.2, 0.85); D.armR2.set(0.2, 0.85); D.armR1.target = 130; D.armR2.target = 137;
        if (!settings.reduceMotion) { D.roll.set(0.24, 0.85); D.roll.target = 6; }
        gazeAt('user'); D.activity = 'listening';
      }
      if (!live && D.listenOn) exitListen();
      if (D.listenOn) metrics.listenFrames += dtMs / (1000 / 60);
      // duck under something moving just above his head
      stepDuck(dtMs);
      if (D.blinkT >= 0) { D.blinkT += dtMs; const t = D.blinkT, d = D.blinkDur, a = d * 0.43; D.blink = t < a ? t / a : t < d ? 1 - (t - a) / (d - a) : 0; if (t > d) { D.blinkT = -1; D.blink = 0; } }
      stepIdle(dtMs);
      const gv = gazeVector();
      D.gx.target = gv.x; D.gy.target = gv.y;
      if (D.mode === 'flight' && D.flight.kind !== 'flick') D.facing.target = clamp(0.8 * Math.sign(D.vel.x) * Math.min(1, Math.abs(D.vel.x) / 60), -0.8, 0.8);
      const rm = settings.reduceMotion;
      if (rm) { D.crouch.snap(0); D.lean.target = D.homeTouch ? D.lean.target : 0; D.roll.snap(0); D.xOff.snap(0); D.squash.snap(0); D.tuck.snap(0); D.duck.snap(0); D.toe.snap(0); }
      for (const s of [D.crouch, D.duck, D.dip, D.dragC, D.sit, D.edge, D.lean, D.roll, D.facing, D.gx, D.gy, D.armL1, D.armL2, D.armR1, D.armR2, D.tuck, D.squash, D.stretchUp, D.xOff, D.toe, D.squint, D.shut]) { s.step(dt); if (!s.force && Math.abs(s.x - s.target) < 0.003 && Math.abs(s.v) < 0.02) { s.x = s.target; s.v = 0; } }
      if (D.sit.target === 0 && D.sit.x < 0.02) D.sit.set(0.45, 0.92);
      let breath = 0;
      const idle = D.mode === 'attached' && !D.gesture && !D.micro && (D.activity === 'resting' || D.activity === 'sitting') && !D.homeTouch && !D.thinking && !D.listenOn;
      if (!rm && !settings.lowPower && !settings.noBreath && idle && D.breathT > 0 && simT > D.breathT) {
        const ph = (simT - D.breathT) / 4200;
        if (ph < 3) breath = 0.6 * Math.sin(ph * 2 * Math.PI) * (ph > 2.5 ? (3 - ph) * 2 : 1);
      }
      if (!idle && D.breathT > 0 && D.mode !== 'attached') D.breathT = -1;
      D.breath = breath;
    }

    function stepDuck(dtMs) {
      const movers = [];
      const to = ui.toast;
      if (to.active) movers.push({ x0: to.x.x, x1: to.x.x + to.w, y0: to.lane, y1: to.lane + 30, v: Math.abs((to.x.x - to.prevX) / (dtMs / 1000)) });
      if (ui.banner.show || ui.banner.y.x > -110) movers.push({ x0: 12, x1: 378, y0: 58 + ui.banner.y.x, y1: 102 + ui.banner.y.x, v: Math.abs(ui.banner.y.v) });
      if (D.mode !== 'attached' || settings.reduceMotion) { if (D.ducking) { D.ducking = false; D.duck.set(0.22, 1.0); D.duck.target = 0; } return; }
      const s = D.scale, hx = D.pos.x, headTop = D.pos.y - 96 * s, r = 17.5 * s;
      let hit = null;
      for (const m of movers) {
        const hOver = m.x1 > hx - r - 4 && m.x0 < hx + r + 4;
        const vNear = m.y1 >= headTop - 12 && m.y0 < headTop + r;
        if (hOver && vNear) { hit = m; break; }
      }
      if (hit && !D.ducking && hit.v > 30) {
        D.ducking = true; D.duck.set(0.14, 1.0); D.duck.target = 1;
        D.reaction = { kind: 'duck', until: simT + 100000 };
        gazeAt('dir', { x: 0, y: -1 }, 'up (ducking)');
        note('something passes within 12 pt above his head: ducks 6 pt and looks up (140 ms)');
      }
      if (!hit && D.ducking) {
        D.ducking = false; D.duck.set(0.22, 1.0); D.duck.target = 0; D.reaction = null;
        after(220, () => { if (!D.ducking) attendContent(); });
        note('it has passed: rises in 220 ms');
      }
    }

    function stepIdle(dtMs) {
      if (D.mode !== 'attached' || !D.anchor) return;
      const resting = !D.gesture && !D.micro && !D.homeTouch && !D.thinking && !D.listenOn && !D.reaction && (D.activity === 'resting' || D.activity === 'sitting');
      const idleFor = simT - Math.max(D.idleSince, ui.lastInput, D.lastLand);
      if (D.anchor.surface === 'stage' && ui.tab === 'home') {
        if (settings.autoWelcome && D.budgets.welcome > 0 && simT > 500 && resting) { welcome(); if (D.mode !== 'attached' || !D.anchor) return; }
        if (resting && !settings.reduceMotion && idleFor > 15000 && !D.satThisIdle) {
          D.satThisIdle = true; D.sit.set(0.45, 0.92); D.sit.target = 1; D.breathT = -1; D.activity = 'sitting';
          note('15 s idle: sits once, cross-legged, then still');
        }
        if (resting && !settings.lowPower && simT >= D.visit.nextGlanceAt && D.visit.glances < 3) {
          D.visit.nextGlanceAt = simT + 25000 + rand() * 20000;
          if (ui.draft === 'pending' && ui.panelMode !== 'open') glance({ x: 120, y: L.stripTop + 28 }, 'draft strip', 520);
          else if (ui.badge) glance({ x: L.tabX.memories, y: 757 }, 'Memories tab', 520);
          else if (!D.visit.lookAround) lookAround();
        }
      }
      if (D.anchor.surface === 'panel' && ui.panelMode === 'strip' && ui.tab === 'memories' && resting && idleFor > 10000 && !D.edgeThisIdle && !settings.reduceMotion) {
        D.edgeThisIdle = true; D.gesture = { kind: 'edgeSit', t: 0 }; D.breathT = -1; D.activity = 'sitting on the strip';
        note('10 s idle on the strip: sits on its edge, legs hanging, swings twice');
      }
      if (resting && !D.satThisIdle && !D.edgeThisIdle) D.activity = D.sit.x > 0.5 ? 'sitting' : D.activity;
    }

    function stepGesture(dtMs) {
      const g = D.gesture; if (!g) return;
      g.t += dtMs; const t = g.t, rm = settings.reduceMotion;
      if (g.kind === 'introduce') {
        if (!rm && t > 60) { D.roll.set(0.24, 0.8); D.roll.target = -8; }
        if (!rm && t > 200 && t < 1040) { D.armL1.set(0.41, 0.85); D.armL2.set(0.41, 0.85); D.armL1.target = 50; D.armL2.target = 54; }
        if (t > 1040) { D.armL1.target = 30; D.armL2.target = 20; D.armL1.set(0.41, 0.9); D.armL2.set(0.41, 0.9); D.roll.target = 0; }
        if (t > 1300 && D.activity === 'introducing the draft') D.activity = 'resting';
        if (t > 1700) { D.gesture = null; D.activity = 'resting'; gazeAt('user'); }
        if (ui.panelMode !== 'open' || D.mode !== 'attached') { D.gesture = null; resetArms(); D.roll.target = 0; }
      } else if (g.kind === 'wave') {
        if (t < 260) { D.armR1.set(0.22, 0.85); D.armR2.set(0.22, 0.85); D.armR1.target = 100; D.armR2.target = 116; }
        else if (t < 710) { const ph = (t - 260) / 450; D.armR2.set(0.08, 0.9); D.armR2.target = 116 + 12 * Math.sin(ph * 3 * Math.PI); }
        else if (t < 1100) { D.armR1.set(0.28, 0.9); D.armR2.set(0.28, 0.9); D.armR1.target = 30; D.armR2.target = 20; }
        else { D.gesture = null; D.activity = 'resting'; resetArms(); }
      } else if (g.kind === 'stretch') {
        const o = g.fromSit ? 140 : 0;
        if (g.fromSit && t < o) { D.sit.set(0.14, 1.0); D.sit.target = 0; }
        if (t >= o && t < o + 500 && !g.up) { g.up = true; for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(0.36, 0.95); D.armL1.target = 110; D.armL2.target = 138; D.armR1.target = 110; D.armR2.target = 138; D.toe.set(0.36, 1.0); D.toe.target = 1; D.breathT = -1; }
        if (t >= o + 470 && t < o + 700) D.shut.target = 1;
        if (t >= o + 700 && !g.down) { g.down = true; D.shut.target = 0; for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(0.30, 0.95); resetArms(0.30); for (const s of [D.armL1, D.armL2, D.armR1, D.armR2]) s.set(0.30, 0.95); D.toe.set(0.30, 1.0); D.toe.target = 0; }
        if (t >= o + 960 && t < o + 1100) { D.lean.set(0.14, 0.35); D.lean.target = t < o + 1030 ? 2.2 : 0; } // small wobble: clumsy offline
        if (t >= o + 1160) { D.gesture = null; D.lean.set(0.2, 0.85); D.lean.target = 0; D.activity = 'resting'; }
      } else if (g.kind === 'trace') {
        if (t > 80) { D.roll.set(0.24, 0.8); D.roll.target = -6; }
        if (t > 220 && t < 900) { D.armL1.set(0.41, 0.85); D.armL2.set(0.41, 0.85); D.armL1.target = 55; D.armL2.target = 55; }
        if (t >= 900) { D.armL1.target = 30; D.armL2.target = 20; D.roll.target = 0; }
        if (t > 1300) { D.gesture = null; D.activity = 'resting'; gazeAt('user'); }
      } else if (g.kind === 'welcome') {
        if (!rm && t > 200 && t < 700) { D.roll.set(0.2, 0.9); D.roll.target = 5; }
        if (t >= 700) { D.roll.set(0.24, 0.95); D.roll.target = 0; }
        if (t > 940) { D.gesture = null; D.activity = 'resting'; }
      } else if (g.kind === 'welcomeEvening') {
        if (t > 60 && !g.blinked) { g.blinked = true; startBlink(280); }
        if (!rm && t > 200 && t < 700) { D.roll.set(0.24, 0.9); D.roll.target = 3; }
        if (t >= 700) { D.roll.set(0.26, 0.95); D.roll.target = 0; }
        if (t > 960) { D.gesture = null; D.activity = 'resting'; }
      } else if (g.kind === 'look') {
        if (t < 450) gazeAt('dir', { x: -0.95, y: 0.05 }, 'look around (left)');
        else if (t < 950) gazeAt('dir', { x: 0.95, y: 0.05 }, 'look around (right)');
        else gazeAt('user');
        if (t > 1400) { D.gesture = null; }
      } else if (g.kind === 'edgeSit') {
        if (t < 400) { D.edge.set(0.32, 0.95); D.edge.target = 1; }
        if (t >= 450 && t < 1050) D.swing = Math.sin(((t - 450) / 600) * 4 * Math.PI) * (1 - (t - 450) / 600 * 0.3);
        if (t >= 1050) D.swing = D.swing * 0.8;
        if (t > 1200) { D.swing = 0; D.gesture = null; D.activity = 'sitting'; }
      }
    }

    /* ------------------------------------------------------------------ render */
    function renderComposer() {
      E.composerText.textContent = ui.typed || 'Type a message…';
      E.composerText.classList.toggle('is-placeholder', !ui.typed);
    }
    function renderThread() {
      if (ui.renderedVersion === ui.msgVersion) return;
      ui.renderedVersion = ui.msgVersion;
      E.thread.innerHTML = ui.messages.map((m) => `<li class="${m.who === 'me' ? 'dp-me' : m.who === 'err' ? 'dp-err' : m.who === 'sys' ? 'dp-sys' : 'dp-doddy'}" data-mid="${m.id}" data-zone="text">${m.text}</li>`).join('');
    }
    const drawn = {};
    function render() {
      E.time.textContent = ui.clockText;
      for (const k in E.screens) { const f = ui.fade[k]; E.screens[k].style.opacity = f.toFixed(3); E.screens[k].style.visibility = f > 0.001 ? 'visible' : 'hidden'; }
      // Home
      const hs = homeScale(), tr = talkHitRect();
      Object.assign(E.talkHit.style, { left: tr[0] + 'px', top: tr[1] + 'px', width: (tr[2] - tr[0]) + 'px', height: (tr[3] - tr[1]) + 'px' });
      const dStage = dip('stage').x; E.stage.style.transform = `translateY(${dStage.toFixed(2)}px)`; drawn.stage = L.stage.y + dStage;
      const vlive = ui.voice.live;
      E.voice.style.opacity = vlive ? 1 : 0; E.voice.style.visibility = vlive ? 'visible' : 'hidden';
      if (vlive) E.voiceBars.forEach((b, i) => { b.style.height = (5 + 11 * Math.abs(Math.sin(simT / 140 + i * 1.3))).toFixed(1) + 'px'; });
      E.micdot.style.opacity = vlive ? 1 : 0;
      // panel
      if (ui.draft === 'pending') {
        const top = ui.panelTop.x, e = panelOpenness(), inset = lerp(16, 8, e), radius = lerp(16, 28, e), dP = dip('panel').x;
        E.panel.style.display = 'block';
        E.panel.style.top = `${(top + dP).toFixed(2)}px`; drawn.panel = top + dP;
        E.panel.style.left = `${inset}px`; E.panel.style.right = `${inset}px`;
        E.panel.style.height = `${Math.max(0, L.panelBottom - top)}px`;
        E.panel.style.borderRadius = `${radius}px`;
        E.panelOpenC.style.opacity = smoothstep(0.45, 0.95, e).toFixed(3); E.panelOpenC.style.visibility = e > 0.4 ? 'visible' : 'hidden';
        E.panelStripC.style.opacity = (1 - smoothstep(0.02, 0.3, e)).toFixed(3); E.panelStripC.style.visibility = e < 0.35 ? 'visible' : 'hidden';
        E.panel.style.opacity = (ui.panelFade == null ? 1 : ui.panelFade).toFixed(3);
      } else E.panel.style.display = 'none';
      // keyboard + composer + thread
      E.keyboard.style.transform = `translateY(${(ui.kbTop.x - (L.H - L.kbH)).toFixed(2)}px)`;
      const ct = composerTop(), dC = dip('composer').x;
      E.composer.style.top = `${(ct + dC).toFixed(2)}px`; drawn.composer = ct + dC;
      { const mf = smoothstep(0, 1, ui.micFade);
        E.mic.style.opacity = mf.toFixed(3); E.mic.style.transform = `scale(${(0.6 + 0.4 * mf).toFixed(3)})`; E.mic.style.visibility = ui.micFade > 0.01 ? 'visible' : 'hidden';
        E.send.style.transform = `translateX(${(-44 * mf).toFixed(2)}px)`; E.composerText.style.right = `${(52 + 44 * mf).toFixed(1)}px`; }
      renderThread();
      const occ = ui.draft === 'pending' && ui.panelTop.x < ct ? ui.panelTop.x : ct;
      E.thread.style.bottom = `${(L.H - Math.min(occ, ui.threadOcc.x) + L.listInset).toFixed(1)}px`;
      for (const li of E.thread.children) { const m = ui.messages[+li.dataset.mid]; if (m) li.style.opacity = clamp((simT - m.t) / 180, 0, 1).toFixed(3); }
      const eOpen = panelOpenness();
      E.scrim.style.opacity = (0.62 * eOpen).toFixed(3); E.scrim.style.visibility = eOpen > 0.01 ? 'visible' : 'hidden';
      // list
      const lb = listBottom();
      E.list.style.height = `${lb - L.listTop}px`;
      const fadeMask = ui.draft === 'pending' ? 'linear-gradient(to bottom, #000 calc(100% - 28px), transparent 100%)' : 'none';
      E.list.style.webkitMaskImage = fadeMask; E.list.style.maskImage = fadeMask;
      for (let i = 0; i < listEls.length; i++) {
        const lay = ui.layout[i], le = listEls[i]; if (!lay) continue;
        const it = ui.items[i], op = it.hs ? clamp(it.hs.x / it.h, 0, 1) : 1;
        le.item.style.top = `${(lay.top - scrollState.y).toFixed(2)}px`; le.item.style.opacity = op.toFixed(3); le.item.style.height = `${lay.h}px`; le.item.style.overflow = it.hs ? 'hidden' : 'visible';
        const dR = ui.dips[`rule:${i}`] ? ui.dips[`rule:${i}`].x : 0;
        le.rule.style.top = `${(lay.bottom - scrollState.y + dR).toFixed(2)}px`;
        drawn[`rule:${i}`] = L.listTop + lay.bottom - scrollState.y + dR;
      }
      // detail
      E.detail.style.transform = `translateX(${ui.detailX.x.toFixed(2)}px)`;
      E.detail.style.visibility = ui.detailX.x < L.W - 0.5 || ui.detail.open ? 'visible' : 'hidden';
      const dD = dip('detail').x; E.source.style.transform = `translateY(${dD.toFixed(2)}px)`; drawn.detail = L.detailSourceY + dD;
      // rail
      const dRail = dip('rail').x; E.railLine.style.transform = `translateY(${dRail.toFixed(2)}px)`; drawn.rail = L.rail + dRail;
      E.badge.style.display = ui.badge ? 'block' : 'none';
      // banner, toast, sheet
      E.banner.style.transform = `translateY(${ui.banner.y.x.toFixed(2)}px)`;
      const to = ui.toast;
      E.toast.style.opacity = to.active ? 1 : 0;
      E.toast.style.transform = `translate(${to.x.x.toFixed(2)}px, ${to.lane.toFixed(2)}px)`;
      E.toast.style.width = to.w + 'px';
      E.sheet.style.transform = `translateY(${ui.sheet.y.x.toFixed(2)}px)`;
      E.sheetDim.style.opacity = (0.25 * clamp(1 - ui.sheet.y.x / 800, 0, 1)).toFixed(3);
      // touch indicator
      finger.vis = finger.down ? Math.min(1, finger.vis + 0.34) : Math.max(0, finger.vis - 0.12);
      if (finger.down) { finger.dx = finger.x; finger.dy = finger.y; }
      E.touch.style.opacity = finger.vis.toFixed(3);
      E.touch.style.transform = `translate(${(finger.dx || 0).toFixed(1)}px, ${(finger.dy || 0).toFixed(1)}px) scale(${(0.85 + 0.15 * finger.vis).toFixed(3)})`;
      E.sim.textContent = settings.label ? `Simulation · stand-in rig · ${settings.label}` : 'Simulation · stand-in rig';
      E.simR.textContent = api.caption || '';
      // Doddy
      const z = D.mode === 'flight' ? D.z : D.anchor ? S(D.anchor.surface).layer + 0.2 : D.z;
      E.svg.style.zIndex = String(Math.round(z * 10));
      const s = D.scale;
      const hidden = D.hiddenBehind && false;
      rig.update({
        x: D.pos.x + D.xOff.x, y: D.pos.y, s,
        opacity: hidden ? 0 : D.opacity,
        crouch: Math.max(-1.2, D.crouch.x) + D.duck.x * 6 + D.dip.x + D.dragC.x,
        sit: clamp(D.sit.x, 0, 1), edge: clamp(D.edge.x, 0, 1), tuck: clamp(D.tuck.x, 0, 1), squash: D.squash.x, stretchUp: Math.max(0, D.stretchUp.x),
        lean: D.lean.x, roll: D.roll.x, facing: D.facing.x, gx: D.gx.x, gy: D.gy.x, blink: D.blink, squint: D.squint.x, shut: D.shut.x,
        armL: [D.armL1.x, D.armL2.x], armR: [D.armR1.x, D.armR2.x], breath: D.breath || 0, mood: D.mood,
        footL: D.footL, footR: D.footR, toe: clamp(D.toe.x, 0, 1), swing: D.swing,
      });
      debugG.style.display = settings.showAnchors || settings.showPath ? '' : 'none';
      trailEl.style.display = settings.showPath ? '' : 'none';
      if (settings.showPath && D.trail) { trailEl.setAttribute('points', D.trail.join(' ')); const age = D.mode === 'flight' ? 0 : simT - D.lastLand; trailEl.style.opacity = String(clamp(1 - (age - 700) / 500, 0, 0.85)); }
      anchorsG.style.display = settings.showAnchors ? '' : 'none';
      if (settings.showAnchors) drawAnchors();
      E.anno.style.display = settings.annotate ? 'block' : 'none';
      E.simRow.style.visibility = settings.annotate ? 'hidden' : 'visible'; // the annotated bar carries its own simulation label
      if (settings.annotate) drawAnno();
    }
    function visibleSurfaceIds() {
      const ids = ['stage', 'composer', 'panel', 'rail', 'detail'];
      if (ui.tab === 'memories') for (let i = 0; i < ui.layout.length; i++) { const y = ruleY(i); if (y > L.listTop && y < listBottom()) ids.push(`rule:${i}`); }
      return ids.filter((id) => S(id).vis());
    }
    function drawAnchors() {
      anchorsG.innerHTML = '';
      for (const id of visibleSurfaceIds()) {
        const s = S(id), y = s.top(), xr = s.xr(), dx = s.dx ? s.dx() : 0;
        el('line', { x1: xr[0] + dx, x2: xr[1] + dx, y1: y, y2: y, stroke: '#2F7D6D', 'stroke-width': 3, opacity: 0.45 }, anchorsG);
        const t = el('text', { x: xr[0] + dx, y: y + 12, 'font-size': 9, fill: '#2F7D6D', 'font-family': 'ui-monospace, monospace' }, anchorsG); t.textContent = `${id} · y ${Math.round(y)}`;
      }
      const pref = preferredAnchor();
      if (pref) { const p = anchorPoint(pref); el('circle', { cx: p.x, cy: p.y, r: 4, fill: 'none', stroke: '#C0582A', 'stroke-width': 1.5 }, anchorsG); }
    }
    /* annotated copy: frame counter and his current surface drawn as a line */
    let annoEls = null;
    function drawAnno() {
      const A = E.anno;
      if (!annoEls) {
        annoEls = {
          zone: el('rect', { fill: 'none', stroke: '#2C7A6B', 'stroke-width': 1, 'stroke-dasharray': '3 3', opacity: 0.8 }, A),
          trail: el('polyline', { fill: 'none', stroke: '#B4521F', 'stroke-width': 1.4, 'stroke-dasharray': '1.5 3' }, A),
          target: el('line', { stroke: '#B4521F', 'stroke-width': 3, 'stroke-dasharray': '6 4', opacity: 0.9 }, A),
          surf: el('line', { stroke: '#2C7A6B', 'stroke-width': 3.2, 'stroke-linecap': 'round' }, A),
          sole: el('circle', { r: 3, fill: '#2C7A6B' }, A),
          surfLab: el('text', { 'font-size': 9.5, 'font-weight': 600, fill: '#2C7A6B', 'font-family': '"DejaVu Sans Mono", ui-monospace, monospace' }, A),
          bar: el('rect', { x: 0, y: 786, width: 390, height: 58, fill: 'rgba(11,11,11,0.86)' }, A),
          l1: el('text', { x: 14, y: 801, 'font-size': 10.5, 'font-weight': 600, fill: '#F3EDDF', 'font-family': '"DejaVu Sans Mono", ui-monospace, monospace' }, A),
          l2: el('text', { x: 14, y: 815, 'font-size': 10, fill: '#E2C9A8', 'font-family': '"DejaVu Sans Mono", ui-monospace, monospace' }, A),
          l3: el('text', { x: 14, y: 829, 'font-size': 9.5, fill: '#BFB8AB', 'font-family': '"DejaVu Sans Mono", ui-monospace, monospace' }, A),
        };
      }
      const a = annoEls, frame = Math.round(simT / (1000 / 60));
      const cur = D.mode === 'flight' ? null : D.anchor;
      if (cur) {
        const s = S(cur.surface), seg = s.seg(), y = drawn[cur.surface] != null ? drawn[cur.surface] : s.top();
        a.surf.setAttribute('x1', seg[0]); a.surf.setAttribute('x2', seg[1]); a.surf.setAttribute('y1', y.toFixed(2)); a.surf.setAttribute('y2', y.toFixed(2)); a.surf.style.display = '';
        a.sole.setAttribute('cx', (D.pos.x + D.xOff.x).toFixed(2)); a.sole.setAttribute('cy', D.pos.y.toFixed(2)); a.sole.style.display = '';
        a.surfLab.textContent = cur.surface; a.surfLab.setAttribute('x', Math.min(seg[1] - 60, Math.max(seg[0] + 2, D.pos.x + 28))); a.surfLab.setAttribute('y', (y + 13).toFixed(1)); a.surfLab.style.display = '';
        const zd = zoneOf(D.scale); a.zone.setAttribute('x', (cur.x + (s.dx ? s.dx() : 0) - zd.w / 2).toFixed(1)); a.zone.setAttribute('y', (y - zd.h).toFixed(1)); a.zone.setAttribute('width', zd.w.toFixed(1)); a.zone.setAttribute('height', zd.h.toFixed(1));
        a.zone.style.display = D.mode === 'attached' && simT - D.lastLand > 340 && D.opacity > 0.5 ? '' : 'none';
      } else { a.surf.style.display = 'none'; a.sole.style.display = 'none'; a.zone.style.display = 'none'; a.surfLab.style.display = 'none'; }
      if (D.mode === 'flight' || D.mode === 'anticipate') {
        const tg = D.target, s = S(tg.surface), seg = s.seg(), y = s.top();
        a.target.setAttribute('x1', seg[0]); a.target.setAttribute('x2', seg[1]); a.target.setAttribute('y1', y.toFixed(2)); a.target.setAttribute('y2', y.toFixed(2)); a.target.style.display = '';
      } else a.target.style.display = 'none';
      const age = D.mode === 'flight' ? 0 : simT - D.lastLand;
      a.trail.setAttribute('points', D.trail.join(' ')); a.trail.style.opacity = String(clamp(1 - (age - 900) / 400, 0, 1));
      const phase = D.mode === 'anticipate' ? `crouch ${fmt(D.phaseT)}/${fmt(D.antDur)} ms` : D.mode === 'flight' ? `${D.flight.kind === 'flick' ? 'hop in place' : 'flight'} ${fmt(D.flight.t)}/${fmt(D.flight.T)} ms` : D.mode === 'fade' ? `fade ${fmt(D.phaseT)}/${fmt(D.fadeOutMs + D.fadeInMs)} ms` : D.mode === 'shuffle' ? `shuffle ${fmt(D.shuf ? D.shuf.t : 0)} ms` : simT - D.lastLand < 60 ? `contact ${fmt(simT - D.lastLand)} ms` : simT - D.lastLand < 340 ? `settle ${fmt(simT - D.lastLand)} ms` : D.activity;
      a.l1.textContent = `${settings.label || 'v2'} · f ${String(frame).padStart(4, '0')} · ${(simT / 1000).toFixed(3)} s · SIMULATION · STAND-IN RIG`;
      a.l2.textContent = `${cur ? cur.surface : '→ ' + (D.target ? D.target.surface : '?')} · ${phase} · ${D.scale.toFixed(2)}× · scroll ${fmt(Math.abs(scrollState.vel))} pt/s`;
      const ev = metrics.events.length ? metrics.events[metrics.events.length - 1] : null;
      a.l3.textContent = ev && simT - ev.t < 1600 ? `${(ev.t / 1000).toFixed(2)} s · ${ev.msg}`.slice(0, 66) : '';
    }

    /* ------------------------------------------------------------------ per-frame checks (acceptance) */
    const zoneMargins = { send: 24, review: 24, link: 16 };
    function zoneRects() {
      const pr = phone.getBoundingClientRect(), sc = pr.width / L.W || 1;
      const out = [];
      const add = (node, kind) => {
        let r;
        if (kind === 'text') { const rg = document.createRange(); rg.selectNodeContents(node); r = rg.getBoundingClientRect(); }
        else r = node.getBoundingClientRect();
        if (!r || r.width === 0) return;
        out.push({ kind, x0: (r.left - pr.left) / sc, y0: (r.top - pr.top) / sc, x1: (r.right - pr.left) / sc, y1: (r.bottom - pr.top) / sc, label: (node.textContent || node.getAttribute('aria-label') || '').trim().slice(0, 28) });
      };
      const scope = [];
      scope.push(root.querySelector('.dp-appbar'));
      if (ui.fade[ui.tab] > 0.5) scope.push(E.screens[ui.tab]);
      if (ui.draft === 'pending') { if (ui.panelMode === 'strip') scope.push(E.panelStripC); }
      if (ui.detail.open && ui.tab === 'memories') scope.push(E.detail);
      const scrimmed = panelOpenness() > 0.5;
      for (const sc2 of scope) {
        for (const n of sc2.querySelectorAll('[data-zone]')) {
          const kind = n.dataset.zone;
          const cs = getComputedStyle(n); if (cs.visibility === 'hidden' || +cs.opacity === 0) continue;
          if (scrimmed && (sc2 === E.screens.talk || sc2 === E.screens.memories || sc2 === E.screens.home)) continue;
          if (sc2 === E.screens.memories && n.closest('.dp-list')) { const r = n.getBoundingClientRect(); const top = (r.top - pr.top) / sc, bot = (r.bottom - pr.top) / sc; if (bot < L.listTop || top > listBottom() - 20) continue; }
          if (sc2 === E.screens.memories && ui.detail.open && ui.detailX.x < 1) continue;
          add(n, kind === 'text' ? 'text' : kind);
        }
      }
      return out;
    }
    function frameCheck() {
      metrics.frames++;
      const docCount = document.querySelectorAll('.doddy-rig').length;
      if (docCount !== 1) violation('one Doddy', `${docCount} figures`);
      // contact
      if ((D.mode === 'attached' || D.mode === 'anticipate' || D.mode === 'shuffle') && D.anchor && D.opacity > 0.01 && !D.hiddenBehind) {
        const y = drawn[D.anchor.surface];
        if (y != null) {
          const gap = Math.abs(D.pos.y - y);
          if (D.anchor.surface === 'composer') { metrics.maxComposerGap = Math.max(metrics.maxComposerGap, gap); if (gap > 1) violation('contact', `composer gap ${gap.toFixed(2)} pt`); }
          else { metrics.maxContactGap = Math.max(metrics.maxContactGap, gap); if (gap > 2) violation('contact', `${D.anchor.surface} gap ${gap.toFixed(2)} pt`); }
        }
      }
      // scale only in the air or faded out
      const sc = D.scale;
      if (Math.abs(sc - D.lastScale) > 1e-6) {
        const ok = D.mode === 'flight' || D.opacity < 0.01 || (D.mode === 'fade' && D.opacity < 0.01);
        metrics.scaleChanges.push({ t: Math.round(simT), mode: D.mode, s: +sc.toFixed(3), ok });
        if (!ok) violation('scale', `changed to ${sc.toFixed(3)} while ${D.mode}`);
      }
      D.lastScale = sc;
      if ((D.mode === 'attached' || D.mode === 'shuffle') && D.anchor && D.opacity > 0.01) {
        const want = scaleFor(D.anchor);
        if (Math.abs(sc - want) > 1e-3) violation('scale', `${sc.toFixed(2)}× on ${D.anchor.surface}`);
      }
      // listening pose only with the microphone indicator
      const listeningPose = D.armR1.x > 100 && D.armR2.x > 110 && D.roll.x > 3;
      if (listeningPose && !ui.voice.live && !D.gesture) { metrics.listenViolations++; violation('listening', 'listening pose without the microphone indicator'); }
      // Reduce Motion: only fades
      if (settings.reduceMotion) {
        if (D.mode === 'flight' || D.mode === 'shuffle') violation('reduce motion', `${D.mode} in view`);
        if (Math.abs(D.squash.x) > 0.01 || Math.abs(D.xOff.x) > 0.01) violation('reduce motion', 'squash or slide');
      }
      // clear zone at rest
      if (D.mode === 'attached' && D.anchor && simT - D.lastLand > 340 && D.opacity > 0.99 && !D.hiddenBehind && !ui.sheet.open && !supportMovingNow() && !D.pendingTransfer && metrics.frames % 3 === 0) {
        metrics.zoneChecks++;
        const p = anchorPoint(D.anchor), zd = zoneOf(D.scale);
        const z = { x0: p.x - zd.w / 2, x1: p.x + zd.w / 2, y0: p.y - zd.h, y1: p.y };
        for (const r of zoneRects()) {
          const m = zoneMargins[r.kind] || 0;
          if (z.x1 > r.x0 - m && z.x0 < r.x1 + m && z.y1 > r.y0 - (m ? 0 : 0) && z.y0 < r.y1) {
            if (r.kind === 'text' || r.kind === 'button' || r.kind === 'send' || r.kind === 'review' || r.kind === 'link') violation('clear zone', `${D.anchor.surface}: ${r.kind} “${r.label}” (margin ${m})`);
          }
        }
      }
      // scroll ends: never under the top edge, the tab bar or the strip
      if (scrollState.endedAt && simT - scrollState.endedAt > 900 && !scrollState.checked) {
        scrollState.checked = true;
        if (D.anchor && D.anchor.surface.startsWith('rule:') && D.mode === 'attached') {
          const y = anchorPoint(D.anchor).y;
          if (y - 96 < L.listTop - 0.5 || y > listBottom() + 0.5) violation('scroll end', `rule at ${y.toFixed(1)}`);
        }
      }
      if (!scrollState.endedAt || simT - scrollState.endedAt < 900) scrollState.checked = !scrollState.endedAt ? true : false;
    }

    /* ------------------------------------------------------------------ scene setup for studies */
    function place(sc) {
      sc = sc || {};
      if (sc.homeScale) settings.homeScale = sc.homeScale;
      if (sc.clock) ui.clockText = sc.clock;
      ui.tab = sc.tab || 'home';
      for (const k in ui.fade) ui.fade[k] = k === ui.tab ? 1 : 0;
      E.tabs.forEach((b) => { const on = b.dataset.tab === ui.tab; b.setAttribute('aria-selected', on ? 'true' : 'false'); b.classList.toggle('is-on', on); });
      ui.keyboard = !!sc.keyboard; ui.kbTop.snap(ui.keyboard ? L.H - L.kbH : L.H); E.composer.classList.toggle('is-focused', ui.keyboard);
      if (sc.draft) { ui.draft = 'pending'; ui.introduced = !!sc.introduced; ui.panelMode = sc.panel || 'strip'; E.panel.style.display = 'block'; ui.panelTop.snap(ui.panelMode === 'open' ? L.panelOpenTop : L.stripTop); ui.composerBase.snap(L.composerBottomStrip); }
      else { ui.draft = 'none'; ui.panelMode = 'hidden'; ui.panelTop.snap(L.panelHiddenTop); ui.composerBase.snap(L.composerBottomNoStrip); }
      ui.messages = (sc.messages || []).map((m, i) => ({ id: i, who: m[0], text: m[1], t: -9999 })); ui.msgVersion++;
      ui.typed = sc.typed || ''; ui.typingTarget = ''; renderComposer();
      if (sc.mic) setMic(true);
      scrollState.y = sc.scroll || 0; scrollState.lastY = scrollState.y; scrollState.v = 0; scrollState.mode = 'idle'; scrollState.vel = 0;
      if (sc.detail != null) { ui.detail.open = true; ui.detail.item = sc.detail; ui.detailX.snap(0); }
      ui.threadOcc.snap(Math.min(composerTop(), ui.draft === 'pending' && ui.panelMode === 'open' ? L.panelOpenTop : 9999));
      ui.badge = !!sc.badge;
      const a = sc.doddy || preferredAnchor();
      D.anchor = Object.assign({}, a); D.mode = 'attached'; D.scale = scaleFor(D.anchor); D.lastScale = D.scale;
      const p = anchorPoint(D.anchor); D.pos.x = p.x; D.pos.y = p.y; D.z = S(D.anchor.surface).layer + 0.2;
      D.memory = Object.assign({ home: { surface: 'stage', x: L.stage.x } }, sc.memory || {}); D.memory[screenKey()] = { surface: D.anchor.surface, x: D.anchor.x };
      D.lastLand = -99999; D.idleSince = simT - (sc.idle || 0); ui.lastInput = simT - (sc.idle || 0); ui.lastTap = simT - (sc.idle || 99999);
      D.budgets.welcome = sc.welcome ? 1 : 0; settings.autoWelcome = !!sc.welcome; if (sc.welcomeKind) settings.welcomeKind = sc.welcomeKind;
      D.session.playfulUsed = 0;
      D.visit = { start: simT - (sc.idle || 0), hadWelcome: !!sc.hadWelcome, glances: sc.glances || 0, lookAround: false, nextGlanceAt: sc.glanceAt != null ? simT + sc.glanceAt : simT + 25000, arrivalGlance: false };
      D.breathT = sc.breathAt != null ? simT + sc.breathAt : -1;
      if (sc.sitting) { D.sit.snap(1); D.satThisIdle = true; D.activity = 'sitting'; } else { D.sit.snap(0); D.satThisIdle = !!sc.noSit; D.activity = 'resting'; }
      D.edgeThisIdle = !!sc.noEdge;
      gazeAt('user'); D.gx.snap(0); D.gy.snap(0);
      if (sc.gaze) { gazeAt('dir', sc.gaze, 'resting look'); D.gx.snap(sc.gaze.x); D.gy.snap(sc.gaze.y); }
      D.vel = { x: 0, y: 0 }; D.accHist = [];
      if (sc.settings) Object.assign(settings, sc.settings);
      surfCache.clear();
      render();
    }

    /* ------------------------------------------------------------------ API */
    const api = {
      settings, ui, D, metrics, L, M,
      get simT() { return simT; },
      caption: '',
      step(dtMs) { let rem = dtMs; while (rem > 0) { const h = Math.min(4.2, rem); step(h); rem -= h; } },
      stepFrame() { const n = 4, h = (1000 / 60) / n; for (let i = 0; i < n; i++) step(h); render(); frameCheck(); },
      render, frameCheck, place, runScript, stopScript,
      get scripting() { return !!script; },
      finger: { down: (x, y, src) => fingerDown(x, y, src), move: (x, y) => fingerMove(x, y), up: () => fingerUp(), state: finger },
      tap(tab) { setTab(tab, 'user'); }, setTab,
      tapDoddy() { if (ui.tab === 'home' && !ui.sheet.open) { ui.lastTap = simT; note('tap on him: Talk opens'); openTalkFromHome(simT); } },
      focusField() { if (ui.tab === 'talk') setKeyboard(true); },
      resetBudgets() { D.budgets.welcome = 1; D.session.playfulUsed = 0; D.visit.hadWelcome = false; note('budgets reset: one welcome, one playful moment'); }, setPanel, setKeyboard, typeText, send, createDraft, clearDraft, reviewAndSend, composerResult,
      openDetail, closeDetail, setBanner, passToast, setMic, memorySaved, scrollToTop, playful, welcome, editDraft, introduceDraft,
      setNextReply(r) { ui.nextReply = r; },
      setHomeScale(v) { settings.homeScale = v; surfCache.clear(); if (D.mode === 'attached' && D.anchor && D.anchor.surface === 'stage' && Math.abs(D.scale - v) > 1e-3) startFade({ surface: 'stage', x: L.stage.x }, { why: 'Home size changed' }); },
      setReduceMotion(on) {
        settings.reduceMotion = on; note(`Reduce Motion ${on ? 'on: hops become fades; eyes still lead' : 'off'}`);
        if (on && (D.mode === 'flight' || D.mode === 'anticipate') && D.target) { const t = D.target; D.flight = null; resetArms(); D.tuck.target = 0; D.crouch.target = 0; D.lean.target = 0; startFade(t, { why: 'Reduce Motion turned on mid-hop' }); }
      },
      surfaceInfo: (id) => S(id), anchorPoint, preferredAnchor, composerTop, ruleY, listBottom,
      log, note, hops: () => metrics.hops,
      state() {
        const a = D.anchor;
        return {
          t: simT, screen: screenKey(), tab: ui.tab, mode: D.mode, surface: a ? a.surface : null, target: D.target ? D.target.surface : null,
          x: +(D.pos.x + D.xOff.x).toFixed(2), y: +D.pos.y.toFixed(2), scale: +D.scale.toFixed(3), opacity: +D.opacity.toFixed(3), activity: D.activity, mood: D.mood, gaze: D.gaze.label,
          scrollVel: +scrollState.vel.toFixed(1), mic: ui.voice.live, uiFade: Object.assign({}, ui.fade),
        };
      },
    };
    render();
    return api;
  }
  global.DoddyEngine = { createApp };
})(typeof window !== 'undefined' ? window : globalThis);

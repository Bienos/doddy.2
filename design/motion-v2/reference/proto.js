/* Doddy v2 prototype bench: drives the shared engine in real time with pointer input and review controls. */
(function () {
  'use strict';
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const bench = $('#bench');
  if (!bench) return;
  const host = $('#pb-phone');
  const scaler = $('#pb-scaler');
  const wrap = $('#pb-stagewrap');
  const out = {
    screen: $('#ro-screen'), surface: $('#ro-surface'), mode: $('#ro-mode'), scale: $('#ro-scale'), scroll: $('#ro-scroll'),
    gaze: $('#ro-gaze'), mood: $('#ro-mood'), hop: $('#ro-hop'), checks: $('#ro-checks'), commit: $('#ro-commit'),
    log: $('#pb-log'), toast: $('#pb-toast'), study: $('#pb-study'),
  };
  let prefersReduced = false;
  try { prefersReduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { /* ignore */ }
  const prefs = { timeScale: 1, reduceMotion: prefersReduced, showPath: true, showAnchors: false, lowPower: false, focusOnTalkTap: false, annotate: false, homeScale: 1.4, replyDelay: 2000, replyFails: false, composerResult: 'sent' };
  let app = null, last = 0, readoutAt = 0, toastTimer = 0, studyEnd = 0, studyName = '';

  function showToast(text) {
    out.toast.textContent = text; out.toast.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { out.toast.hidden = true; }, 3200);
  }
  function renderLog(log) {
    out.log.innerHTML = log.slice(0, 8).map((l) => `<li><span class="t">${(l.t / 1000).toFixed(2)} s</span>${l.msg.replace(/</g, '&lt;')}</li>`).join('');
  }
  function build(study) {
    app = DoddyEngine.createApp(host, {
      settings: Object.assign({}, prefs, { label: study ? study.code : 'live', autoWelcome: !study }, study && study.settings ? study.settings : {}),
      onLog: renderLog, onToast: showToast,
    });
    if (study) {
      app.place(study.scene || {});
      Object.assign(app.settings, { timeScale: prefs.timeScale, showPath: prefs.showPath, showAnchors: prefs.showAnchors, annotate: prefs.annotate, homeScale: prefs.homeScale, lowPower: prefs.lowPower });
      if (!(study.settings && study.settings.reduceMotion)) app.settings.reduceMotion = prefs.reduceMotion;
      app.caption = study.title;
      app.runScript(study.script(app));
      studyEnd = study.duration; studyName = `${study.code} ${study.title}`;
      out.study.textContent = `Playing ${studyName}. It hands back to you when it ends.`;
    } else {
      app.place({ tab: 'home', welcome: true });
      app.caption = 'Live';
      studyEnd = 0; studyName = '';
      out.study.textContent = 'Live: everything inside the phone responds to touch, mouse and keyboard.';
    }
    app.render();
    renderLog(app.log);
  }

  /* ---------- fit the phone to its column ---------- */
  function fit() {
    const w = wrap.parentElement.clientWidth;
    const maxH = Math.max(520, Math.min(window.innerHeight - 120, 884));
    const s = Math.min(1, w / 410, maxH / 864);
    scaler.style.transform = `scale(${s})`;
    wrap.style.width = `${410 * s}px`; wrap.style.height = `${864 * s}px`;
  }
  try { new ResizeObserver(fit).observe(wrap.parentElement); } catch (e) { window.addEventListener('resize', fit); }
  fit();

  /* ---------- pointer input becomes one finger ---------- */
  const phonePoint = (e) => { const r = $('.dp-phone', host).getBoundingClientRect(); const k = r.width / 390; return { x: (e.clientX - r.left) / k, y: (e.clientY - r.top) / k }; };
  let activePointer = null;
  host.addEventListener('pointerdown', (e) => {
    if (activePointer !== null || e.button > 0) return;
    if (app.scripting) app.stopScript();
    activePointer = e.pointerId;
    try { host.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
    const p = phonePoint(e); app.finger.down(p.x, p.y, 'user');
    e.preventDefault();
  });
  host.addEventListener('pointermove', (e) => { if (e.pointerId !== activePointer) return; const p = phonePoint(e); app.finger.move(p.x, p.y); });
  const end = (e) => { if (e.pointerId !== activePointer) return; activePointer = null; app.finger.up(); };
  host.addEventListener('pointerup', end);
  host.addEventListener('pointercancel', end);
  /* trackpad or wheel scrolling in Memories behaves like a finger drag */
  let wheel = null;
  host.addEventListener('wheel', (e) => {
    if (!app || app.ui.tab !== 'memories' || app.ui.detail.open || activePointer !== null) return;
    e.preventDefault();
    const p = phonePoint(e);
    if (!wheel) { wheel = { y: Math.min(Math.max(p.y, 300), 600) }; app.finger.down(200, wheel.y, 'wheel'); app.finger.move(200, wheel.y + 0.01); }
    wheel.y -= e.deltaY * (e.deltaMode === 1 ? 16 : 1);
    app.finger.move(200, wheel.y);
    clearTimeout(wheel.t); wheel.t = setTimeout(() => { app.finger.up(); wheel = null; }, 90);
  }, { passive: false });

  /* ---------- keyboard: every control in the phone is a real button ---------- */
  host.addEventListener('click', (e) => {
    if (e.detail !== 0) return; // pointer clicks go through the finger above
    const t = e.target.closest('button, [role="button"]'); if (!t) return;
    const ui = app.ui;
    if (t.matches('.dp-tab')) app.setTab(t.dataset.tab, 'keyboard');
    else if (t.matches('.dp-talkhit')) app.tapDoddy();
    else if (t.matches('.dp-send')) app.send();
    else if (t.matches('.dp-composer')) { app.focusField(); if (!ui.typed) app.typeText('Tell Mateusz I’m running ten minutes late.'); }
    else if (t.matches('.dp-panel-strip')) app.setPanel('open');
    else if (t.matches('.dp-grab, .dp-later')) app.setPanel('strip');
    else if (t.matches('.dp-reviewsend')) app.reviewAndSend();
    else if (t.matches('.dp-p-draft')) app.editDraft();
    else if (t.matches('.dp-back')) app.closeDetail();
    else if (t.matches('.dp-voice')) { /* the Stop control only exists while holding */ }
    else if (t.dataset.act === 'sheet-cancel') app.composerResult('cancelled');
    else if (t.dataset.act === 'sheet-send') app.composerResult(prefs.composerResult);
    else if (t.dataset.item != null) app.openDetail(+t.dataset.item);
  });
  host.addEventListener('keydown', (e) => {
    const t = e.target;
    if ((e.key === 'Enter' || e.key === ' ') && t.getAttribute && t.getAttribute('role') === 'button' && t.tagName !== 'BUTTON') { e.preventDefault(); t.click(); }
  });

  /* ---------- controls ---------- */
  function seg(group, attr, apply) {
    $$(`[data-${attr}]`, group).forEach((b) => b.addEventListener('click', () => {
      $$(`[data-${attr}]`, group).forEach((x) => x.setAttribute('aria-pressed', x === b ? 'true' : 'false'));
      apply(b.dataset[attr]);
    }));
  }
  seg($('#pb-speed'), 'speed', (v) => { prefs.timeScale = +v; });
  seg($('#pb-size'), 'size', (v) => { prefs.homeScale = +v; app.setHomeScale(+v); app.note(`Home size ${v}×`); });
  seg($('#pb-delay'), 'delay', (v) => { prefs.replyDelay = +v; app.settings.replyDelay = +v; });
  seg($('#pb-result'), 'result', (v) => { prefs.composerResult = v; app.settings.composerResult = v; });
  const sw = (id, key, fn) => { const el = $(id); el.checked = !!prefs[key]; el.addEventListener('change', () => { prefs[key] = el.checked; if (fn) fn(el.checked); else app.settings[key] = el.checked; }); };
  sw('#pb-rm', 'reduceMotion', (on) => app.setReduceMotion(on));
  sw('#pb-path', 'showPath');
  sw('#pb-anchors', 'showAnchors');
  sw('#pb-anno', 'annotate');
  sw('#pb-lowpower', 'lowPower');
  sw('#pb-focus', 'focusOnTalkTap');
  sw('#pb-fail', 'replyFails');

  const act = {
    send: () => { if (app.ui.tab !== 'talk') app.setTab('talk', 'event'); app.send({ text: 'Tell Mateusz I’m running ten minutes late.' }); },
    saved: () => app.memorySaved(),
    draft: () => { if (app.ui.draft === 'pending') { showToast('A draft is already waiting. Send it or keep it for later first.'); return; } app.createDraft(); },
    banner: () => app.setBanner(!app.ui.banner.show),
    toast: () => app.passToast({ text: 'Saved to Memories', from: 'right', restX: 24 }),
    mic: () => app.setMic(!app.ui.mic),
    wave: () => app.playful('wave'),
    stretch: () => app.playful('stretch'),
    skip: () => { app.step(10000); app.note('skipped ahead 10 s'); },
    budgets: () => app.resetBudgets(),
    welcome: () => { if (app.ui.tab !== 'home') { showToast('Welcomes only happen on Home.'); return; } app.resetBudgets(); app.welcome(); },
    welcomeEvening: () => { if (app.ui.tab !== 'home') { showToast('Welcomes only happen on Home.'); return; } app.resetBudgets(); app.welcome('evening'); },
    welcomeBack: () => { if (app.ui.tab !== 'home') { showToast('Welcomes only happen on Home.'); return; } app.resetBudgets(); app.welcome('back'); },
    live: () => build(null),
  };
  $$('[data-act]', bench).forEach((b) => { if (!host.contains(b)) b.addEventListener('click', () => act[b.dataset.act] && act[b.dataset.act]()); });
  $$('[data-study]', bench).forEach((b) => b.addEventListener('click', () => { build(DoddyStudies.get(b.dataset.study)); }));

  /* ---------- readout ---------- */
  const SURF = { stage: 'Home stage line', composer: 'Composer top edge', panel: 'Draft panel edge', rail: 'Tab rail', detail: 'Source block rule' };
  const surfName = (s) => (!s ? 'in the air' : s.startsWith('rule:') ? `List rule ${+s.slice(5) + 1}` : SURF[s] || s);
  function readout() {
    const st = app.state(), m = app.metrics, h = app.D.lastHop;
    out.screen.textContent = st.screen;
    out.surface.textContent = st.mode === 'flight' ? `→ ${surfName(st.target)}` : surfName(st.surface);
    out.mode.textContent = `${st.mode} · ${st.activity}`;
    out.scale.textContent = `${st.scale.toFixed(2)}×`;
    out.scroll.textContent = `${Math.abs(st.scrollVel).toFixed(0)} pt/s`;
    out.gaze.textContent = st.gaze;
    out.mood.textContent = st.mood;
    out.hop.textContent = h ? `${h.label}: ${h.D.toFixed(0)} pt, apex ${h.A.toFixed(1)} pt, ${h.T.toFixed(0)} ms, crouch ${h.ant} ms, ${h.s0.toFixed(1)}→${h.s1.toFixed(1)}×` : '—';
    const tt = m.tabTaps.filter((t) => t.done != null);
    out.commit.textContent = tt.length ? `${Math.round(tt[tt.length - 1].done)} ms (limit 140)` : '—';
    const v = m.violations;
    out.checks.textContent = v.length ? `${v.length} flagged · last: ${v[v.length - 1].kind}, ${v[v.length - 1].detail}` : `all passing · ${m.frames} frames checked`;
    out.checks.dataset.state = v.length ? 'bad' : 'ok';
  }

  /* ---------- loop ---------- */
  function frame(ts) {
    const dt = last ? Math.min(50, ts - last) : 16.7; last = ts;
    app.settings.timeScale = prefs.timeScale;
    app.step(dt * prefs.timeScale);
    app.render(); app.frameCheck();
    if (studyEnd && app.simT >= studyEnd) { studyEnd = 0; app.stopScript(); out.study.textContent = `${studyName} finished. It’s live now: carry on from here.`; }
    if (ts - readoutAt > 90) { readoutAt = ts; readout(); }
    requestAnimationFrame(frame);
  }
  build(null);
  requestAnimationFrame(frame);
})();

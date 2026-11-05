/* Doddy v2 motion studies: every clip is a deterministic script over the shared engine.
   Times are ms from the first frame. Each clip holds 0.5 s of stillness at the start and at least 1 s of rest at the end. */
(function (global) {
  'use strict';
  const TAB = { home: 73, talk: 195, memories: 317 }, TABY = 757;
  const studies = [];
  const add = (d) => studies.push(d);

  /* finger helpers */
  const tap = (t, x, y, hold = 60) => [{ t, type: 'down', x, y }, { t: t + hold, type: 'up' }];
  const tabTap = (t, tab, hold = 60) => tap(t, TAB[tab], TABY, hold);
  const path = (t0, x0, y0, segs) => {
    const out = [{ t: t0, type: 'down', x: x0, y: y0 }];
    let t = t0;
    for (const [dt, x, y, ease] of segs) { t += dt; out.push({ t, type: 'move', x, y, ease: ease || 'linear' }); }
    return out;
  };
  const up = (t) => ({ t, type: 'up' });
  /* a tap placed at run time (the target depends on where the list has scrolled) */
  const tapAt = (t, fn, hold = 60) => [[t, (a) => { const p = fn(a); a.finger.down(p.x, p.y, 'script'); }], [t + hold, (a) => a.finger.up()]];

  const TALK_MSGS = [['me', 'What’s Mateusz’s coffee order?'], ['doddy', 'Flat white with oat milk. You saved it on 12 October.']];

  /* ---------------------------------------------------------------- fixed v1 studies */
  add({
    id: '02', code: '02', file: 'v2-02-tab-hop', kind: 'fixed', title: 'Tab hop', duration: 5700,
    summary: 'Talk → Memories → Talk. Each tab commits in the tapped frame and finishes in 120 ms; he follows with one standard hop.',
    changes: 'The v1 walk is gone. Crouch 80 ms, one arc, 60 ms contact, settle. The selected tab is a real state: filled capsule, bold label, rust dot.',
    art: ['Gaze (pupils that move)'],
    scene: { tab: 'talk', messages: TALK_MSGS },
    script: () => ({ finger: [...tabTap(500, 'memories'), ...tabTap(2600, 'talk')] }),
  });
  add({
    id: '09a', code: '09', file: 'v2-09-introduce-draft', kind: 'fixed', title: 'Introduce the draft', duration: 5000,
    summary: 'A draft becomes reviewable on Talk. The rising panel picks him up; once settled he introduces it: eyes 0 ms, head −8° from 60 ms, arm −40° from 200 ms, hold 600 ms, back in about 260 ms, eyes on the draft 400 ms more.',
    changes: 'Eyes, then head, then arm; 1.3 s maximum; hand at least 12 pt clear of text. Once per draft.',
    art: ['Gaze', 'Pointing arm with glove (stand-in)'],
    scene: { tab: 'talk', messages: [['me', 'Tell Mateusz I’m running ten minutes late.'], ['doddy', 'Here’s a message for Mateusz. Have a look before it goes.']] },
    script: () => ({ timeline: [[500, (a) => a.createDraft()]] }),
  });
  add({
    id: '09b', code: '09b', file: 'v2-09b-editing-ends-it', kind: 'fixed', title: 'Editing ends the introduction', duration: 4000,
    summary: 'The introduction starts; the user touches the draft text to edit it. The gesture ends within 180 ms and his eyes go to the edit.',
    changes: 'Editing always wins over the introduction.',
    art: ['Gaze'],
    scene: { tab: 'talk', draft: true, panel: 'open', introduced: false, messages: [['me', 'Tell Mateusz I’m running ten minutes late.'], ['doddy', 'Here’s a message for Mateusz. Have a look before it goes.']] },
    script: () => ({ timeline: [[500, (a) => a.introduceDraft()]], finger: [...tap(860, 120, 494, 80)] }),
  });
  add({
    id: '12', code: '12', file: 'v2-12-return-to-spot', kind: 'fixed', title: 'Return to his spot at Home size', duration: 4600,
    summary: 'Memories → Home. Home is complete within 120 ms; he crouches, arcs, grows from 1.0× to 1.4× in the air, lands with a contact squash and a spring settle at the centre of the stage.',
    changes: 'A true arc with crouch, contact squash and spring settle. The size change hides inside the flight.',
    art: ['Gaze'],
    scene: { tab: 'memories' },
    script: () => ({ finger: [...tabTap(500, 'home')] }),
  });
  add({
    id: '14', code: '14', file: 'v2-14-behind-the-page', kind: 'fixed', title: 'Behind the page', duration: 5100,
    summary: '“View original note” pushes a detail page over his spot. He glances at it (100 ms), is covered in place, and stays put. Back pops the page; its left edge uncovers him first, where he stood.',
    changes: 'He stays put while covered. The mask is the real page edge, so the pop uncovers his left side first.',
    art: ['Gaze'],
    scene: { tab: 'memories' },
    script: () => ({ finger: [...tap(500, 80, 311), ...tap(2500, 52, 106)] }),
  });
  add({
    id: '16', code: '16', file: 'v2-16-change-direction', kind: 'fixed', title: 'Change direction mid-flight', duration: 5800,
    summary: 'Talk → Memories, then Home while he is in the air: the path bends from his current velocity and he grows on the way. Then Talk → Memories during the crouch: the hop is re-aimed before take-off.',
    changes: 'The interface commits in one frame on every tap; his path bends instead of stopping or restarting.',
    art: ['Gaze'],
    scene: { tab: 'talk', messages: TALK_MSGS },
    script: () => ({ finger: [...tabTap(500, 'memories'), ...tabTap(760, 'home', 50), ...tabTap(2800, 'talk', 40), ...tabTap(2860, 'memories', 40)] }),
  });

  /* ---------------------------------------------------------------- new studies */
  add({
    id: 'N1', code: 'N1', file: 'v2-N1-home-size', kind: 'new', title: 'Home size', duration: 5700,
    summary: 'Talk → Home → Talk. He takes off at 1.0×, lands at 1.4× on the stage, then takes off at 1.4× and lands at 1.0× on the composer. Scale = start + (target − start) × smoothstep(0.15, 0.9, s).',
    changes: 'New: two sizes, one figure. Line weight scales with him, so it reads as the camera coming closer.',
    art: ['Gaze'],
    scene: { tab: 'talk', messages: TALK_MSGS },
    script: () => ({ finger: [...tabTap(500, 'home'), ...tabTap(2700, 'talk')] }),
  });
  add({
    id: 'N2', code: 'N2', file: 'v2-N2-home-touch', kind: 'new', title: 'Home touch', duration: 5200,
    summary: 'A finger moves over Home and his eyes follow it, returning to you 300 ms after it lifts. The finger lands on him: squint and 3 pt dip within 60 ms. Release under 450 ms is a tap: Talk opens and he hops to the composer, shrinking in the air.',
    changes: 'New. A real “Talk to Doddy” button (91 × 175 pt) covers his clear zone; the drawing is never the only hit area.',
    art: ['Gaze', 'Squint'],
    scene: { tab: 'home' },
    script: () => ({ finger: [...path(600, 312, 262, [[420, 86, 300, 'inout'], [480, 300, 628, 'inout']]), up(1560), ...tap(2150, 196, 412, 110)] }),
  });
  add({
    id: 'N3', code: 'N3', file: 'v2-N3-home-play', kind: 'new', title: 'Home play', duration: 7200,
    summary: 'Head rub (slow stroke under 600 pt/s): eyes close, pleased mouth, head tips 6° with the stroke, eyes reopen 300 ms after. Drag on his body: lean = 12° × tanh(dx ÷ 60), pull down crouches; release springs back with one overshoot (0.30/0.55). Upward flick over 900 pt/s: one hop in place, pleased.',
    changes: 'New. Moves over 10 pt never open Talk. He never leaves the stage because of a gesture.',
    art: ['Eyes closed in contentment', 'Gaze'],
    scene: { tab: 'home' },
    script: () => ({
      finger: [
        ...path(600, 176, 356, [[260, 192, 354, 'inout'], [300, 214, 357, 'inout'], [360, 180, 352, 'inout'], [300, 206, 355, 'inout']]), up(1900),
        ...path(2700, 198, 424, [[420, 250, 432, 'inout'], [320, 246, 470, 'inout'], [220, 246, 470]]), up(3720),
        ...path(4500, 195, 432, [[40, 195, 418, 'in'], [50, 195, 352, 'linear']]), up(4600),
      ],
    }),
  });
  add({
    id: 'N4', code: 'N4', file: 'v2-N4-hold-to-talk', kind: 'new', title: 'Hold to talk', duration: 7200,
    summary: 'Press and hold on him. At 450 ms voice starts (curious brow, no listening pose yet). Only when capture is live do the microphone indicator, the Stop control and the listening pose appear, in the same frame. Release ends capture: the pose drops in that frame and he follows the conversation to Talk.',
    changes: 'New. Honest always: the listening pose exists only in frames where the microphone indicator is on.',
    art: ['Listening pose (glove at the ear)', 'Gaze'],
    scene: { tab: 'home' },
    script: () => ({ finger: [...tap(600, 196, 418, 2500)] }),
  });
  add({
    id: 'N5', code: 'N5', file: 'v2-N5-home-life', kind: 'new', title: 'Home life', duration: 18500, long: true,
    summary: 'He arrives on Home with a draft waiting: one glance at the strip on arrival. Two seconds after settling he breathes three times (0.6 pt × 1.4, 4.2 s period), then holds still. At 15 s idle he sits once, cross-legged on the stage line, and stays still.',
    changes: 'New. Runs 18.5 s in one real-time take, because the brief’s own timings (three 4.2 s breaths from 2 s, sitting at 15 s) cannot fit in 8 s.',
    art: ['Sitting cross-legged', 'Gaze'],
    scene: { tab: 'talk', draft: true, panel: 'strip', introduced: true, messages: TALK_MSGS },
    script: () => ({ finger: [...tabTap(500, 'home')] }),
  });
  const welcome = (id, file, title, kind, clock, summary) => add({
    id, code: id, file, kind: 'new', title, duration: 4000, summary,
    changes: 'New. One welcome per day, on Home, once Home is interactive. Reduce Motion: eyes only.',
    art: kind === 'back' ? ['Gaze', 'Pleased mouth'] : ['Gaze', 'Slow blink'],
    scene: { tab: 'home', welcome: true, welcomeKind: kind, clock, gaze: { x: -0.25, y: 0.55 } },
    script: () => ({}),
  });
  welcome('N6a', 'v2-N6a-welcome-default', 'Welcome: default', 'default', '9:41', 'Eyes to you first, then a 5° head roll: 200 ms out, 300 ms hold, 240 ms back.');
  welcome('N6b', 'v2-N6b-welcome-evening', 'Welcome: after 21:00', 'evening', '21:14', 'After 21:00: one slow 280 ms blink and a 3° roll.');
  welcome('N6c', 'v2-N6c-welcome-back', 'Welcome: back after 3 days', 'back', '9:41', 'After 3 or more days away: one hop in place (apex 10 pt × 1.4) with a pleased mouth, then the default welcome.');
  add({
    id: 'N7', code: 'N7', file: 'v2-N7-home-and-review', kind: 'new', title: 'Home and review', duration: 5600,
    summary: 'The strip is tapped on Home: the panel rises and he hops about 90 pt up onto it, aimed at its touchdown edge, shrinking in the air. “Keep for later” collapses it: he leaves before it drops away and hops back to the stage, growing.',
    changes: 'New. Every move between Home and another surface is a hop, so the size change always happens in the air; he is never picked up at 1.4×.',
    art: ['Gaze'],
    scene: { tab: 'home', draft: true, panel: 'strip', introduced: true },
    script: () => ({ finger: [...tap(500, 120, 680), ...tap(2600, 195, 654)] }),
  });
  add({
    id: 'N8', code: 'N8', file: 'v2-N8-shuffle', kind: 'new', title: 'Shuffle', duration: 4000,
    summary: 'A microphone button appears at the end of the composer and Send slides 44 pt toward him. To keep 24 pt clear of Send he shuffles 10 pt left: eyes first, two 110 ms steps (the moving foot lifts 3 pt, the planted foot never slides), face half-turned, settle 120 ms.',
    changes: 'New: moving along the same surface by up to 40 pt. Under 8 pt it is one side-step; over 40 pt he hops.',
    art: ['Two step poses', 'Gaze'],
    scene: { tab: 'talk', messages: TALK_MSGS },
    script: () => ({ timeline: [[500, (a) => a.setMic(true)]] }),
  });
  add({
    id: 'N9', code: 'N9', file: 'v2-N9-scroll-riding', kind: 'new', title: 'Scroll riding', duration: 7600,
    summary: 'A slow scroll (about 115 pt/s): he rides his rule in the same frame, then, as it is about to leave the safe band, one lily-pad hop to the nearest rule below in the middle 60%. A fling sends him to the rail; once the list has moved slower than 150 pt/s for 200 ms he makes one hop to the best rule.',
    changes: 'New. Lily-pad hops only under 300 pt/s, at most one every 1.2 s; anything faster goes to the rail.',
    art: ['Gaze'],
    scene: { tab: 'memories', scroll: 200, doddy: { surface: 'rule:2', x: 330 } },
    script: () => ({
      finger: [
        ...path(500, 150, 560, [[200, 150, 548, 'in'], [520, 150, 480], [480, 150, 440, 'out']]), up(1760),
        ...path(3200, 150, 600, [[40, 150, 588, 'in'], [70, 150, 500]]), up(3310),
      ],
    }),
  });
  add({
    id: 'N10', code: 'N10', file: 'v2-N10-brace', kind: 'new', title: 'Brace', duration: 4000,
    summary: 'He waits on the strip in Memories. The user flicks it up and the panel snaps open under him: his weight response plus arms out 25° for balance; the arms come back once the push has passed. Once per ride.',
    changes: 'New. Threshold calibrated (see notes): ordinary opens and keyboard rides don’t brace, a flick does.',
    art: ['Brace: arms out', 'Gaze'],
    scene: { tab: 'memories', draft: true, panel: 'strip', introduced: true },
    script: () => ({ finger: [...path(500, 120, 680, [[17, 120, 674], [17, 120, 660], [17, 120, 634], [17, 120, 594], [17, 120, 542]]), up(585)] }),
  });
  add({
    id: 'N11', code: 'N11', file: 'v2-N11-thinking', kind: 'new', title: 'Thinking', duration: 7700,
    summary: 'Send: his eyes follow the bubble up with a 4° nod. No reply within 600 ms: eyes up and to the right, head 4°, held still. Still waiting at 4 s: one slow blink and his eyes move to the upper left once. The reply lands: eyes snap to it (88 ms), head straightens (240 ms).',
    changes: 'New. Once per message, no loop. Optional art: glove at the chin.',
    art: ['Gaze', 'Slow blink', 'Optional: thinking with a glove at the chin'],
    scene: { tab: 'talk', keyboard: true, typed: 'What time does Mum land on Saturday?', messages: TALK_MSGS },
    script: () => ({
      timeline: [[0, (a) => a.setNextReply({ delay: 4400, text: 'Saturday at 14:20, terminal A.', draft: false })]],
      finger: [...tap(500, 352, 514)],
    }),
  });
  add({
    id: 'N12', code: 'N12', file: 'v2-N12-noticing', kind: 'new', title: 'Noticing', duration: 7800,
    summary: 'The reply lands (eyes to its first line, 300 ms) and saves a memory: eyes to the Memories tab for 400 ms as its dot appears, then back to the composer. An offline banner slides in: eyes to it with a concerned brow while it is up; calm once it is gone.',
    changes: 'New. Gaze-only reactions: one at a time, the latest wins, each at most 600 ms.',
    art: ['Gaze', 'Concerned brow'],
    scene: { tab: 'talk', messages: [['me', 'What’s Mateusz’s coffee order?'], ['doddy', 'Flat white with oat milk.']] },
    script: () => ({
      timeline: [
        [500, (a) => a.send({ text: 'We have coffee on Fridays, after work.', reply: { delay: 900, text: 'Got it. I saved “Coffee with Mateusz” to Memories.', saved: true, savedAfter: 520, draft: false } })],
        [3600, (a) => a.setBanner(true)],
        [5400, (a) => a.setBanner(false)],
      ],
    }),
  });
  add({
    id: 'N13', code: 'N13', file: 'v2-N13-strip-edge-sit', kind: 'new', title: 'Sitting on the strip edge', duration: 5600,
    summary: 'A draft waits in Memories; he stands on the strip over the gap before “Review ›”. At 10 s idle he sits on its top edge, legs hanging in front, swings them twice (600 ms) and holds still. The clip joins 7 s into his idle.',
    changes: 'New. He never sits on list rules (legs would cover the next item), on Talk (you may type) or on the rail (he is waiting).',
    art: ['Sitting on an edge with legs hanging'],
    scene: { tab: 'memories', draft: true, panel: 'strip', introduced: true, idle: 7000, breathAt: -5200 },
    script: () => ({}),
  });
  add({
    id: 'N14', code: 'N14', file: 'v2-N14-stretch', kind: 'new', title: 'Stretch', duration: 4000,
    summary: 'The session’s one playful moment, after 16 s idle on Home with no welcome this visit. Stands up (140 ms), raises both arms and rises 3 pt × 1.4 onto his toes over 500 ms, eyes closed for a 200 ms hold, back down in 400 ms with a small wobble. 1.3 s in total.',
    changes: 'New. Clumsy offline, never during a task, never on a tap, off under Reduce Motion.',
    art: ['Stretch: arms up, on his toes', 'Eyes closed in contentment', 'Sitting cross-legged'],
    scene: { tab: 'home', sitting: true, idle: 16000 },
    script: () => ({ timeline: [[500, (a) => a.playful('stretch')]] }),
  });
  add({
    id: 'N15', code: 'N15', file: 'v2-N15-ducking', kind: 'new', title: 'Ducking under a toast', duration: 4800,
    summary: 'A “Saved to Memories” toast slides in 8 pt above his head. He crouches 6 pt and looks up (140 ms), holds while it overlaps, and rises in 220 ms. It comes to rest clear of his clear zone, so he stays.',
    changes: 'New. If a toast came to rest over his clear zone he would shuffle or hop clear instead. Off under Reduce Motion.',
    art: ['Gaze'],
    scene: { tab: 'talk', messages: TALK_MSGS },
    script: () => ({ timeline: [[500, (a) => a.passToast({ text: 'Saved to Memories', from: 'right', restX: 24, response: 0.95, hold: 1400 })]] }),
  });

  add({
    id: 'RM', code: 'RM', file: 'v2-RM-reduce-motion', kind: 'extra', title: 'Reduce Motion', duration: 6200,
    summary: 'The same moves with Reduce Motion on: Talk → Home → Memories, then the keyboard. Every hop becomes a 120 ms fade out and a 180 ms fade in, his eyes still turn first, the size switches while he is invisible, and he still rides the keyboard without squash.',
    changes: 'Extra evidence for the Reduce Motion acceptance check (not in the brief’s list).',
    art: ['Gaze'],
    settings: { reduceMotion: true },
    scene: { tab: 'talk', messages: TALK_MSGS },
    script: () => ({ finger: [...tabTap(500, 'home'), ...tabTap(1900, 'memories'), ...tabTap(3300, 'talk'), ...tap(3900, 120, 682)] }),
  });

  /* ---------------------------------------------------------------- journey v2 */
  const linkTapFor = (a) => {
    const s = a.state(); const i = s.surface && s.surface.startsWith('rule:') ? +s.surface.slice(5) : 1;
    return { x: 84, y: a.ruleY(i) - 23 };
  };
  add({
    id: 'J', code: 'J', file: 'v2-J-journey', kind: 'journey', title: 'Journey v2: one 30-second take', duration: 30000,
    summary: 'One Doddy for 30 seconds across Home, Talk, review, Apple’s composer, Memories and a detail page, following the 16 beats of the brief.',
    changes: 'Replaces the v1 24-second journey.',
    art: ['Gaze', 'Squint', 'Pointing arm', 'Thinking (optional)'],
    scene: { tab: 'home', welcome: true, gaze: { x: -0.25, y: 0.55 } },
    beats: [
      [0, 'Home at 1.4×: daily welcome'], [1500, 'Eyes follow a finger; it lands on him'], [3000, 'Tap: Talk commits, he hops down, shrinking'],
      [3500, 'Field focuses; he rides the keyboard; typing'], [7000, 'Send: eyes follow the bubble, 4° nod'], [7500, 'No reply yet: thinking'],
      [9000, 'Reply lands; saved memory: eyes to Memories'], [10000, 'Draft: keyboard hides, he steps off at once'], [11000, 'He introduces the draft'],
      [12500, 'Apple’s composer covers the app; returns sent'], [14500, 'Panel clears; he rides it, steps onto the composer'], [15500, 'Memories: hop to the first rule'],
      [16500, 'Slow scroll, lily-pad hop, fling, rail wait, hop back'], [21000, 'Detail page covers him; Back reveals him'], [23500, 'Home: hop up, growing to 1.4×'], [25000, 'Settles; eyes to you; stillness'],
    ],
    script: () => ({
      timeline: [
        [3600, (a) => {}],
        [4300, (a) => a.typeText('Tell Mateusz I’m running late. Coffee is Fridays after work.', 32)],
        [6900, (a) => a.setNextReply({ delay: 1940, text: 'I’ll draft that for Mateusz. I also saved “Coffee with Mateusz” to Memories.', saved: true, savedAfter: 450, draft: true, draftAfter: 1000 })],
        ...tapAt(21200, linkTapFor),
      ],
      finger: [
        ...path(1550, 320, 252, [[400, 92, 300, 'inout'], [380, 300, 610, 'inout']]), up(2380),
        ...tap(2760, 196, 414, 240),
        ...tap(3600, 120, 682),
        ...tap(7000, 352, 514),
        ...tap(12600, 195, 573),
        ...tap(13900, 359, 466),
        ...tabTap(15500, 'memories'),
        ...path(16700, 150, 600, [[420, 150, 580, 'in'], [600, 150, 520], [500, 150, 496, 'out']]), up(18270),
        ...path(18900, 150, 620, [[40, 150, 608, 'in'], [70, 150, 520]]), up(19010),
        ...tap(22700, 52, 106),
        ...tabTap(23600, 'home'),
      ],
    }),
  });

  global.DoddyStudies = { list: studies, get: (id) => studies.find((s) => s.id === id) };
})(typeof window !== 'undefined' ? window : globalThis);

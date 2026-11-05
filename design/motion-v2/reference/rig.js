/* Doddy stand-in rig, v2.
   Source proportions: head 36 pt across including its outline, 96 pt tall, origin at the soles.
   Line weight scales with the figure (camera-close at Home), so nothing uses non-scaling strokes.
   Every pose here is a stand-in for art that still has to be drawn (see the package's art list). */
(function (global) {
  'use strict';
  const NS = 'http://www.w3.org/2000/svg';
  const DEG = Math.PI / 180;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const hyp = (x, y) => Math.sqrt(x * x + y * y);
  function el(tag, attrs, parent) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }
  const RIG = {
    headR: 17.5, headY: -77.5, neckY: -60, shoulderY: -55, hipY: -31,
    upper: 13.5, fore: 13, thigh: 12.6, shin: 13, ankleX: 7.5, ankleY: -6.5,
    ink: '#0B0B0B', paper: '#FCF8EF', stroke: 1.9,
  };
  // sneaker drawn toes-left, sole on y = 0
  const SHOE = 'M5.2,0 L-8.4,0 Q-11.2,0 -10.8,-3.1 Q-10,-6.2 -5.4,-6.6 L-1.4,-8.2 Q2.6,-9.8 5.4,-7.4 Q7.4,-4.4 5.2,0 Z';
  const LACES = 'M-4.6,-6.3 L-2.6,-8 M-3.1,-5.5 L-1,-7.3 M-1.6,-4.7 L0.5,-6.6';

  function createRig(parent, id) {
    const g = el('g', { class: 'doddy-rig', id: id || 'doddy' }, parent);
    const body = el('g', {}, g);
    const legs = el('g', {}, body);
    const ink = RIG.ink;
    const line = (w) => ({ fill: 'none', stroke: ink, 'stroke-width': w, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' });
    const legL = el('polyline', line(RIG.stroke), legs), legR = el('polyline', line(RIG.stroke), legs);
    const shoeL = el('g', {}, legs), shoeR = el('g', {}, legs);
    for (const s of [shoeL, shoeR]) {
      el('path', { d: SHOE, fill: '#FFFFFF', stroke: ink, 'stroke-width': 1.5, 'stroke-linejoin': 'round' }, s);
      el('path', { d: LACES, fill: 'none', stroke: ink, 'stroke-width': 0.9, 'stroke-linecap': 'round' }, s);
      el('path', { d: 'M-9.4,0 L5.4,0', fill: 'none', stroke: ink, 'stroke-width': 1.6, 'stroke-linecap': 'round' }, s);
    }
    const upperBody = el('g', {}, body);
    const torso = el('line', line(RIG.stroke), upperBody);
    const head = el('g', {}, upperBody);
    el('circle', { cx: 0, cy: 0, r: RIG.headR, fill: RIG.paper, stroke: ink, 'stroke-width': 2.0 }, head);
    const face = el('g', {}, head);
    const eyeL = el('ellipse', { cx: -5.4, cy: -1.5, rx: 1.15, ry: 2.25, fill: ink }, face);
    const eyeR = el('ellipse', { cx: 5.6, cy: -3.0, rx: 1.15, ry: 2.25, fill: ink }, face);
    const shutL = el('path', { d: 'M-7.9,-0.9 Q-5.4,-3.9 -2.9,-0.9', fill: 'none', stroke: ink, 'stroke-width': 1.3, 'stroke-linecap': 'round', opacity: 0 }, face);
    const shutR = el('path', { d: 'M3.1,-2.4 Q5.6,-5.4 8.1,-2.4', fill: 'none', stroke: ink, 'stroke-width': 1.3, 'stroke-linecap': 'round', opacity: 0 }, face);
    const brow = el('path', { d: 'M3.1,-9.3 Q5.7,-11.9 8.7,-9.6', fill: 'none', stroke: ink, 'stroke-width': 1.3, 'stroke-linecap': 'round' }, face);
    const mouth = el('path', { d: 'M-6.6,5.4 Q0.5,12.8 7.6,5.0', fill: 'none', stroke: ink, 'stroke-width': 1.6, 'stroke-linecap': 'round' }, face);
    const armL = el('polyline', line(RIG.stroke), upperBody), armR = el('polyline', line(RIG.stroke), upperBody);
    const glove = () => {
      const gg = el('g', {}, upperBody);
      el('circle', { cx: 0, cy: 0, r: 3.7, fill: '#FFFFFF', stroke: ink, 'stroke-width': 1.4 }, gg);
      el('path', { d: 'M1.6,-2.9 Q4.6,-3.6 4.1,-0.6', fill: '#FFFFFF', stroke: ink, 'stroke-width': 1.2, 'stroke-linecap': 'round' }, gg);
      return gg;
    };
    const gloveL = glove(), gloveR = glove();

    function knee(hx, hy, ax, ay, a, b, side) {
      const dx = ax - hx, dy = ay - hy, d = Math.min(hyp(dx, dy), a + b - 0.01);
      const ca = clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1);
      const base = Math.atan2(dy, dx), ang = Math.acos(ca);
      const k1 = { x: hx + a * Math.cos(base + ang), y: hy + a * Math.sin(base + ang) };
      const k2 = { x: hx + a * Math.cos(base - ang), y: hy + a * Math.sin(base - ang) };
      return side < 0 ? (k1.x < k2.x ? k1 : k2) : (k1.x > k2.x ? k1 : k2);
    }
    function armPts(side, a1, a2, sy) {
      const e = { x: side * RIG.upper * Math.sin(a1 * DEG), y: sy + RIG.upper * Math.cos(a1 * DEG) };
      const h = { x: e.x + side * RIG.fore * Math.sin(a2 * DEG), y: e.y + RIG.fore * Math.cos(a2 * DEG) };
      return { e, h };
    }
    const f2 = (v) => v.toFixed(2);

    /* p (all lengths in rig units, the engine divides world pt by scale):
       x, y soles (world) · s scale · opacity · crouch · sit (cross-legged) · edge (sit on an edge, legs hanging)
       tuck · squash (−1..1 landing squash/stretch) · stretchUp (0..0.06 drag stretch) · lean · roll · facing
       gx, gy pupils · blink · squint · shut (eyes closed in contentment) · armL/armR [upper, fore] degrees from straight down, outward
       breath · mood · footL/footR {dx, up} · toe (tiptoe 0..1) · swing (leg swing, edge sit) */
    function update(p) {
      const s = p.s || 1;
      g.setAttribute('transform', `translate(${f2(p.x)} ${f2(p.y)}) scale(${s.toFixed(4)})`);
      g.style.opacity = p.opacity == null ? 1 : p.opacity;
      const st = p.squash || 0, su = p.stretchUp || 0;
      body.setAttribute('transform', `scale(${(1 - 0.035 * st - 0.45 * su).toFixed(4)} ${(1 + 0.055 * st + su).toFixed(4)})`);
      const sit = clamp(p.sit || 0, 0, 1), edge = clamp(p.edge || 0, 0, 1), tuck = clamp(p.tuck || 0, 0, 1), toe = clamp(p.toe || 0, 0, 1);
      const rise = 3.0 * toe;
      const drop = (p.crouch || 0) + sit * 15 + edge * 30 - (p.breath || 0) - rise;
      const hipY = RIG.hipY + drop;
      const fL = p.footL || { dx: 0, up: 0 }, fR = p.footR || { dx: 0, up: 0 };
      // standing / tucked / cross-legged ankles
      let axL = -RIG.ankleX - 2 * tuck + fL.dx, axR = RIG.ankleX + 2 * tuck + fR.dx;
      let ayL = RIG.ankleY - 11 * tuck - fL.up - rise, ayR = RIG.ankleY - 11 * tuck - fR.up - rise;
      axL = lerp(axL, 4.5, sit); axR = lerp(axR, -4.5, sit); ayL = lerp(ayL, -4.2, sit); ayR = lerp(ayR, -4.2, sit);
      // hanging legs (edge sit): ankles below the seat, in front of the edge
      const sw = p.swing || 0;
      axL = lerp(axL, -5.5 + 1.6 * sw, edge); axR = lerp(axR, 5.5 - 1.6 * sw, edge);
      ayL = lerp(ayL, 21 + 1.2 * Math.abs(sw), edge); ayR = lerp(ayR, 21 + 1.2 * Math.abs(sw), edge);
      const kL = knee(0, hipY, axL, ayL, RIG.thigh + sit * 3, RIG.shin + sit * 3, -1);
      const kR = knee(0, hipY, axR, ayR, RIG.thigh + sit * 3, RIG.shin + sit * 3, 1);
      const kLx = lerp(kL.x, -7.2, edge), kLy = lerp(kL.y, 3.5, edge), kRx = lerp(kR.x, 7.2, edge), kRy = lerp(kR.y, 3.5, edge);
      legL.setAttribute('points', `0,${f2(hipY)} ${f2(kLx)},${f2(kLy)} ${f2(axL)},${f2(ayL)}`);
      legR.setAttribute('points', `0,${f2(hipY)} ${f2(kRx)},${f2(kRy)} ${f2(axR)},${f2(ayR)}`);
      const tilt = tuck * 18;
      const toeRot = Math.asin(clamp((rise + 0.0001) / 9.5, 0, 1)) / DEG;
      const sxL = lerp(1, -1, sit) * (1 - 0.15 * sit) * 0.95, sxR = lerp(-1, 1, sit) * (1 - 0.15 * sit) * 0.95;
      const syS = 0.95 * (1 - 0.15 * sit);
      const shoeT = (ax, ay, up, sx, side) => {
        // hanging over an edge: toes point down and forward
        if (edge > 0.5) return `translate(${f2(ax)} ${f2(ay + 5)}) rotate(${(side * 64).toFixed(1)}) scale(${(sx * 0.82).toFixed(3)} 0.82)`;
        // standing: the sole stays on the ground unless the foot is lifted; tiptoe rotates about the toe
        const oy = sit > 0.01 ? lerp(-up, ay + 6.5 - 0.3 * sit, sit) : -up;
        return `translate(${f2(ax)} ${f2(oy)}) rotate(${(side * -tilt).toFixed(1)}) scale(${sx.toFixed(3)} ${syS.toFixed(3)}) rotate(${(-toeRot).toFixed(1)} -9.4 0)`;
      };
      shoeL.setAttribute('transform', shoeT(axL + 0.2, ayL, fL.up, sxL, -1));
      shoeR.setAttribute('transform', shoeT(axR - 0.2, ayR, fR.up, sxR, 1));
      upperBody.setAttribute('transform', `rotate(${(p.lean || 0).toFixed(2)} 0 ${f2(hipY)})`);
      const neckY = RIG.neckY + drop, shY = RIG.shoulderY + drop, headY = RIG.headY + drop;
      torso.setAttribute('x1', 0); torso.setAttribute('y1', f2(neckY)); torso.setAttribute('x2', 0); torso.setAttribute('y2', f2(hipY));
      head.setAttribute('transform', `translate(0 ${f2(headY)}) rotate(${(p.roll || 0).toFixed(2)} 0 ${RIG.headR})`);
      const fc = clamp(p.facing || 0, -1, 1);
      face.setAttribute('transform', `translate(${f2(4.4 * fc)} 0)`);
      const gx = clamp(p.gx || 0, -1, 1) * 1.7, gy = clamp(p.gy || 0, -1, 1) * 1.3;
      const shut = clamp(p.shut || 0, 0, 1);
      const ry = 2.25 * (1 - 0.88 * clamp(p.blink || 0, 0, 1)) * (1 - 0.55 * clamp(p.squint || 0, 0, 1)) * (1 - shut);
      eyeL.setAttribute('cx', f2(-5.4 + gx)); eyeL.setAttribute('cy', f2(-1.5 + gy)); eyeL.setAttribute('ry', f2(Math.max(0.05, ry)));
      eyeR.setAttribute('cx', f2(5.6 + gx)); eyeR.setAttribute('cy', f2(-3.0 + gy)); eyeR.setAttribute('ry', f2(Math.max(0.05, ry)));
      eyeL.style.opacity = shut > 0.5 ? 0 : 1; eyeR.style.opacity = shut > 0.5 ? 0 : 1;
      shutL.setAttribute('opacity', shut > 0.5 ? 1 : 0); shutR.setAttribute('opacity', shut > 0.5 ? 1 : 0);
      const mood = p.mood || 'calm';
      mouth.setAttribute('d', mood === 'pleased' ? 'M-7.4,4.8 Q0.4,14.2 8.4,4.4' : mood === 'concerned' ? 'M-5.6,8.2 Q0.5,6.2 6.4,7.9' : 'M-6.6,5.4 Q0.5,12.8 7.6,5.0');
      brow.setAttribute('d', mood === 'concerned' ? 'M3.1,-11.6 Q6.2,-10.4 8.9,-8.6' : mood === 'curious' ? 'M3.1,-10.6 Q5.7,-13.4 8.7,-10.9' : 'M3.1,-9.3 Q5.7,-11.9 8.7,-9.6');
      const aL = p.armL || [30, 20], aR = p.armR || [30, 20];
      const L1 = armPts(-1, aL[0], aL[1], shY), R1 = armPts(1, aR[0], aR[1], shY);
      armL.setAttribute('points', `0,${f2(shY)} ${f2(L1.e.x)},${f2(L1.e.y)} ${f2(L1.h.x)},${f2(L1.h.y)}`);
      armR.setAttribute('points', `0,${f2(shY)} ${f2(R1.e.x)},${f2(R1.e.y)} ${f2(R1.h.x)},${f2(R1.h.y)}`);
      gloveL.setAttribute('transform', `translate(${f2(L1.h.x)} ${f2(L1.h.y)}) scale(-1 1)`);
      gloveR.setAttribute('transform', `translate(${f2(R1.h.x)} ${f2(R1.h.y)})`);
      return { headY, shY, hipY, handL: L1.h, handR: R1.h };
    }
    update({ x: 0, y: 0 });
    return { g, update };
  }
  global.DoddyRig = { createRig, RIG };
})(typeof window !== 'undefined' ? window : globalThis);

// "Take a shot": Doddy throws the ball at a hoop. Drag back anywhere on the court and let go
// (slingshot), or press "Shoot for me". Plain canvas, no libraries, nothing stored.

(() => {
  const canvas = document.querySelector("#court");
  if (!canvas || !canvas.getContext) return;
  const ctx = canvas.getContext("2d");
  const madeEl = document.querySelector("#made");
  const shotsEl = document.querySelector("#shots");
  const autoBtn = document.querySelector("#auto-shot");

  // Logical court; scaled to the canvas size.
  const W = 800, H = 520, GROUND = 496, G = 1500;
  const INK = "#171715", ORANGE = "#F58A24", SOFT = "#DFD5C6", ACCENT = "#A64B00";

  // Doddy, drawn from the app's pose art (512 x 512 artboard).
  const DODDY = { x: 0, size: 270 };
  DODDY.y = GROUND + 8 - DODDY.size * (440 / 512);
  const fromArt = (ax, ay) => ({ x: DODDY.x + ax * DODDY.size / 512, y: DODDY.y + ay * DODDY.size / 512 });
  const HAND = fromArt(371, 80);            // where the ball sits in the "shot" pose
  const R = 29 * DODDY.size / 512;          // ball radius, same scale as the drawing

  // Hoop
  const RIM = { front: 618, back: 694, y: 214 };
  const BOARD = { x: 708, top: 128, bottom: 240 };
  const RIM_PEG = 4;

  const poses = {};
  for (const name of ["basketball-shot", "basketball-follow-through", "basketball-gather"]) {
    const img = new Image();
    img.src = `assets/poses/doddy-pose-${name}-light-v1.3-r1.svg`;
    img.onload = () => draw();
    poses[name] = img;
  }

  const state = {
    pose: "basketball-shot",
    ball: null,              // { x, y, vx, vy, spin, angle, scored, t }
    aim: null,               // { sx, sy, x, y }
    made: 0, shots: 0,
    swish: 0,                // net animation time left
    say: null,               // { text, t }
    running: false,
    last: 0,
    resetTimer: null,
  };

  // ---------- sizing ----------
  let scale = 1;
  function resize() {
    const cssW = canvas.clientWidth;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(cssW * dpr);
    canvas.height = Math.round(cssW * (H / W) * dpr);
    scale = (cssW / W) * dpr;
    draw();
  }
  new ResizeObserver(resize).observe(canvas);

  // ---------- input ----------
  const MAX_PULL = 170, POWER = 8.6;

  function toCourt(event) {
    const rect = canvas.getBoundingClientRect();
    return { x: (event.clientX - rect.left) * (W / rect.width), y: (event.clientY - rect.top) * (H / rect.height) };
  }
  function launchVelocity(aim) {
    let dx = aim.sx - aim.x, dy = aim.sy - aim.y;
    const len = Math.hypot(dx, dy);
    if (len > MAX_PULL) { dx *= MAX_PULL / len; dy *= MAX_PULL / len; }
    return { vx: dx * POWER, vy: dy * POWER, pull: Math.min(len, MAX_PULL) };
  }

  canvas.addEventListener("pointerdown", (e) => {
    if (state.ball) return;
    const p = toCourt(e);
    state.aim = { sx: p.x, sy: p.y, x: p.x, y: p.y };
    canvas.setPointerCapture(e.pointerId);
    draw();
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!state.aim) return;
    const p = toCourt(e);
    state.aim.x = p.x; state.aim.y = p.y;
    draw();
  });
  const release = () => {
    if (!state.aim) return;
    const v = launchVelocity(state.aim);
    state.aim = null;
    if (v.pull < 14) { draw(); return; }  // a tap, not a throw
    throwBall(v.vx, v.vy);
  };
  canvas.addEventListener("pointerup", release);
  canvas.addEventListener("pointercancel", () => { state.aim = null; draw(); });

  autoBtn?.addEventListener("click", () => {
    if (state.ball) return;
    // Solve for a flight time, with a little wobble so it doesn't always go in.
    const T = 0.95 + (Math.random() - 0.5) * 0.2;
    const tx = (RIM.front + RIM.back) / 2 + (Math.random() - 0.5) * 92;
    const ty = RIM.y - 4;
    throwBall((tx - HAND.x) / T, (ty - HAND.y - 0.5 * G * T * T) / T);
  });

  function throwBall(vx, vy) {
    clearTimeout(state.resetTimer);
    state.shots += 1;
    shotsEl.textContent = state.shots;
    state.pose = "basketball-follow-through";
    state.ball = { x: HAND.x, y: HAND.y, vx, vy, angle: 0, spin: -vx / 90, scored: false, t: 0, rested: 0 };
    start();
  }

  // ---------- physics ----------
  function step(dt) {
    const b = state.ball;
    if (b) {
      const prevY = b.y;
      b.vy += G * dt;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.angle += b.spin * dt;
      b.t += dt;

      // rim pegs
      for (const px of [RIM.front, RIM.back]) collidePoint(b, px, RIM.y, RIM_PEG, 0.55);
      // backboard
      if (b.x + R > BOARD.x && b.x < BOARD.x + 10 && b.y > BOARD.top - R && b.y < BOARD.bottom + R && b.vx > 0) {
        b.x = BOARD.x - R; b.vx = -b.vx * 0.55; b.spin *= -0.5;
      }
      // basket: centre passes down through the rim between the pegs
      if (!b.scored && prevY < RIM.y && b.y >= RIM.y && b.vy > 0 && b.x > RIM.front + RIM_PEG && b.x < RIM.back - RIM_PEG) {
        b.scored = true;
        state.made += 1;
        madeEl.textContent = state.made;
        state.swish = 0.45;
        say(pick(["Swish.", "Nothing but net.", "Too easy.", "Again?"]));
      }
      // ground
      if (b.y + R > GROUND) {
        b.y = GROUND - R; b.vy = -b.vy * 0.5; b.vx *= 0.8; b.spin = b.vx / 40;
        if (Math.abs(b.vy) < 90) { b.vy = 0; b.rested += dt; }
      }
      const gone = b.x < -80 || b.x > W + 80 || b.t > 5 || b.rested > 0.35;
      if (gone) {
        if (!b.scored) say(pick(["Off the rim.", "Close one.", "Warm-up shot.", "Wind, probably."]));
        state.ball = null;
        state.pose = "basketball-gather";
        state.resetTimer = setTimeout(() => { state.pose = "basketball-shot"; draw(); }, 380);
      }
    }
    if (state.swish > 0) state.swish = Math.max(0, state.swish - dt);
    if (state.say) { state.say.t -= dt; if (state.say.t <= 0) state.say = null; }
  }

  function collidePoint(b, px, py, pr, bounce) {
    const dx = b.x - px, dy = b.y - py, d = Math.hypot(dx, dy), min = R + pr;
    if (d >= min || d === 0) return;
    const nx = dx / d, ny = dy / d;
    b.x = px + nx * min; b.y = py + ny * min;
    const vn = b.vx * nx + b.vy * ny;
    if (vn < 0) { b.vx -= (1 + bounce) * vn * nx; b.vy -= (1 + bounce) * vn * ny; b.spin += vn / 200; }
  }

  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  function say(text) { state.say = { text, t: 1.6 }; }

  function start() {
    if (state.running) return;
    state.running = true;
    state.last = performance.now();
    requestAnimationFrame(tick);
  }
  function tick(now) {
    const dt = Math.min(0.033, (now - state.last) / 1000);
    state.last = now;
    // two sub-steps keep fast balls from skipping through the rim
    step(dt / 2); step(dt / 2);
    draw();
    if (state.ball || state.swish > 0 || state.say) requestAnimationFrame(tick);
    else state.running = false;
  }

  // ---------- drawing ----------
  function line(x1, y1, x2, y2, w, color) {
    ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = "round";
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
  }

  function drawBall(x, y, angle) {
    ctx.save();
    ctx.translate(x, y); ctx.rotate(angle);
    ctx.fillStyle = ORANGE; ctx.strokeStyle = INK; ctx.lineWidth = 2.2;
    ctx.beginPath(); ctx.arc(0, 0, R, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    ctx.lineWidth = 1.4; ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(-R, 0); ctx.quadraticCurveTo(0, -R * 0.28, R, 0);
    ctx.moveTo(0, -R); ctx.quadraticCurveTo(-R * 0.3, 0, 0, R);
    ctx.moveTo(-R * 0.7, -R * 0.7); ctx.quadraticCurveTo(R * 0.75, -R * 0.14, R * 0.7, R * 0.7);
    ctx.moveTo(R * 0.7, -R * 0.7); ctx.quadraticCurveTo(-R * 0.75, R * 0.14, -R * 0.7, R * 0.7);
    ctx.stroke();
    ctx.restore();
  }

  function drawHoop() {
    // pole and arm
    line(752, BOARD.top + 40, 752, GROUND, 6, INK);
    line(BOARD.x + 6, BOARD.top + 60, 752, BOARD.top + 60, 4, INK);
    // backboard with target square
    ctx.fillStyle = "#FFFDF8"; ctx.strokeStyle = INK; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.roundRect(BOARD.x, BOARD.top, 12, BOARD.bottom - BOARD.top, 3); ctx.fill(); ctx.stroke();
    // net (swings when a basket drops through)
    const sway = state.swish > 0 ? Math.sin(state.swish * 40) * 5 : 0;
    ctx.strokeStyle = INK; ctx.lineWidth = 1.4;
    const top = RIM.y, bottom = RIM.y + 52, n = 6;
    for (let i = 0; i <= n; i++) {
      const xt = RIM.front + (RIM.back - RIM.front) * (i / n);
      const xb = RIM.front + 12 + (RIM.back - RIM.front - 24) * (i / n) + sway;
      ctx.beginPath(); ctx.moveTo(xt, top); ctx.lineTo(xb, bottom); ctx.stroke();
    }
    for (let k = 1; k <= 3; k++) {
      const yy = top + (bottom - top) * (k / 3.4);
      const inset = 12 * (k / 3.4);
      ctx.beginPath(); ctx.moveTo(RIM.front + inset + sway * k / 3, yy); ctx.lineTo(RIM.back - inset + sway * k / 3, yy); ctx.stroke();
    }
    // rim (drawn last so the ball passes behind its front edge)
    line(RIM.front, RIM.y, BOARD.x, RIM.y, 5, ORANGE);
  }

  function drawAimGuide() {
    const v = launchVelocity(state.aim);
    if (v.pull < 14) return;
    // dotted preview of the first part of the arc
    ctx.fillStyle = ACCENT;
    for (let i = 1; i <= 9; i++) {
      const t = i * 0.055;
      const x = HAND.x + v.vx * t, y = HAND.y + v.vy * t + 0.5 * G * t * t;
      ctx.globalAlpha = 1 - i / 11;
      ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
    }
    ctx.globalAlpha = 1;
    // the pull itself
    ctx.setLineDash([6, 8]);
    line(state.aim.sx, state.aim.sy, state.aim.x, state.aim.y, 2, SOFT);
    ctx.setLineDash([]);
  }

  function draw() {
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    ctx.clearRect(0, 0, W, H);
    // floor line
    line(16, GROUND + 2, W - 16, GROUND + 2, 2, SOFT);

    const img = poses[state.pose];
    if (img?.complete && img.naturalWidth) ctx.drawImage(img, DODDY.x, DODDY.y, DODDY.size, DODDY.size);

    const b = state.ball;
    // ball behind the net/rim when it's inside the hoop area
    const behind = b && b.x > RIM.front - R && b.x < BOARD.x && b.y > RIM.y - R;
    if (b && behind) drawBall(b.x, b.y, b.angle);
    drawHoop();
    if (b && !behind) drawBall(b.x, b.y, b.angle);

    if (state.aim) drawAimGuide();

    if (state.say) {
      ctx.globalAlpha = Math.min(1, state.say.t * 2);
      ctx.fillStyle = INK;
      ctx.font = "700 38px Caveat, 'Bradley Hand', cursive";
      ctx.textAlign = "center";
      ctx.fillText(state.say.text, 470, 96);
      ctx.globalAlpha = 1;
    }
  }

  resize();
})();

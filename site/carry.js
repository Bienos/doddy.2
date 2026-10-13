/* "Doddy carries you across": the page-to-page transition from the motion board.
   Progressive enhancement. A link marked data-carry is a plain link first. With JavaScript, motion allowed and
   the frames loaded, a click plays (about 0.9 s) and then goes to the link; the next page plays the arrival (about 0.5 s).
   Without JavaScript, with reduced motion, with frames not ready, with a modifier-click, or on a direct visit: a normal page load.

   Old page, from the click:
     0 to 200 ms    Doddy pops out of the link (pop frames) and lands on the page.
     200 to 600 ms  He runs right (run frames) while the page fades to paper (carry.css: opacity only, nothing moves).
     600 to 900 ms  Ink wipes left to right ahead of him, then we navigate.
   New page: ink covers the screen; it is wiped off left to right with Doddy running just behind the edge to
   [data-carry-ring], where he waves (wave frames) and the items of [data-carry-objects] drop in 60 ms apart.

   The one thing kept between pages is a flag in sessionStorage (a timestamp and the target path, read once and removed,
   good for 10 s). No cookies, nothing leaves the browser. The art is the pack's frames in assets/motion/ (see site/README.md). */
(() => {
  "use strict";

  const root = document.documentElement;
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");

  const FLAG = "doddy-carry";
  const FRESH_MS = 10000;      // a flag older than this is ignored
  const FRAME_DIR = "/assets/motion/";
  const FRAME_COUNT = { pop: 4, run: 6, wave: 5 };

  // Old page timeline (ms from the click).
  const POP_END = 200, RUN_END = 600, INK_END = 900;
  const POP_STEP = 50, RUN_STEP = 66, SPRINT_STEP = 50;
  // New page timeline (ms from the page being ready).
  const REVEAL_MS = 200;
  const WAVE_SEQUENCE = [1, 2, 3, 4, 5, 4], WAVE_STEP = 40;
  const OBJECTS_START = 40, OBJECTS_STEP = 60, OBJECT_MS = 100;
  const ARRIVE_FAILSAFE_MS = 4000;

  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const easeOut = (t) => 1 - (1 - t) * (1 - t);
  const easeIn = (t) => t * t;
  const easeInOut = (t) => 0.5 - Math.cos(Math.PI * t) / 2;

  const frameUrl = (kind, n) => `${FRAME_DIR}${kind}_${n}.png`;
  const frameUrls = (kind) => Array.from({ length: FRAME_COUNT[kind] }, (_, i) => frameUrl(kind, i + 1));

  // ---------- Frames: load each once; "ready" means every frame of the kinds asked for has loaded ----------
  const loads = new Map();
  function load(src) {
    if (!loads.has(src)) {
      loads.set(src, new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error(`frame failed: ${src}`));
        img.src = src;
      }));
    }
    return loads.get(src);
  }
  const ready = (kinds) => Promise.all(kinds.flatMap(frameUrls).map(load));

  let outReady = false;          // pop and run frames are loaded: safe to play the run
  function warm() {              // start loading (on idle, and again on hover or focus of a carry link)
    ready(["pop", "run"]).then(() => { outReady = true; }, () => {});
  }

  // ---------- Sprite: one fixed element with every frame stacked; show one at a time ----------
  function makeSprite(kinds, height) {
    const el = document.createElement("div");
    el.className = "carry-doddy";
    el.setAttribute("aria-hidden", "true");
    el.style.height = `${height}px`;
    el.style.width = `${height * 2 / 3}px`;   // the pack's frames are 2:3
    const frames = {};
    for (const kind of kinds) {
      frames[kind] = frameUrls(kind).map((src) => {
        const img = new Image();
        img.alt = "";
        img.src = src;
        el.append(img);
        return img;
      });
    }
    let current = null;
    return {
      el,
      show(kind, n) {            // n is 1-based, wraps
        const list = frames[kind];
        const next = list[(n - 1) % list.length];
        if (next === current) return;
        if (current) current.classList.remove("on");
        next.classList.add("on");
        current = next;
      },
      place(x, feetY, scale = 1) {
        el.style.transform = `translate3d(${x}px, ${feetY - height}px, 0) scale(${scale})`;
      },
    };
  }

  // Drive tick(t) every animation frame for `ms`, then resolve. Navigation never waits on this (see setTimeout below).
  function run(ms, tick) {
    return new Promise((resolve) => {
      let start = null;
      const step = (now) => {
        if (start === null) start = now;
        const t = now - start;
        tick(Math.min(t, ms));
        if (t >= ms) resolve(); else requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    });
  }

  const feather = () => parseFloat(getComputedStyle(root).getPropertyValue("--carry-f")) || 160;
  const setInk = (px) => root.style.setProperty("--carry-ink-x", `${px}px`);

  // ---------- The old page ----------
  let running = false;
  let sprite = null;

  function cleanupOut() {
    running = false;
    root.classList.remove("carry-run");
    root.style.removeProperty("--carry-ink-x");
    if (sprite) { sprite.el.remove(); sprite = null; }
  }

  function carryOut(link) {
    const href = link.href;
    const to = new URL(href).pathname;
    try {
      sessionStorage.setItem(FLAG, `${Date.now()}|${to}`);
    } catch {
      location.assign(href);   // no storage, so the next page couldn't play its half: plain load
      return;
    }
    running = true;
    // Whatever happens to the animation, the page is on its way at 900 ms. If it still hasn't come 3 s later
    // (slow or failed request), take the ink off so this page isn't left black.
    setTimeout(() => location.assign(href), INK_END);
    setTimeout(cleanupOut, INK_END + 3000);

    const vw = window.innerWidth, vh = window.innerHeight;   // the ink is as wide as the window, scrollbar included
    const f = feather();
    const tab = link.getBoundingClientRect();
    const navBottom = document.querySelector(".nav")?.getBoundingClientRect().bottom ?? 0;
    const h = clamp(vh * 0.2, 96, 168), w = h * 2 / 3;
    const ground = navBottom + (vh - navBottom) * 0.66;       // where his feet land
    const x0 = clamp(tab.left + tab.width / 2 - w / 2, 0, vw - w);

    sprite = makeSprite(["pop", "run"], h);
    document.body.append(sprite.el);
    root.classList.add("carry-run");
    setInk(-(vw + f));

    run(INK_END, (t) => {
      // He stays at the tab while popping, then makes one accelerating run out of the right edge of the window.
      const x = lerp(x0, vw + 4, easeIn(clamp((t - POP_END) / (INK_END - POP_END), 0, 1)));
      // The ink starts at 600 ms and wipes left to right behind him (his x is raised if it ever catches up).
      const inkP = easeIn(clamp((t - RUN_END) / (INK_END - RUN_END), 0, 1));
      setInk(-(1 - inkP) * (vw + f));
      const ahead = Math.max(x, inkP * (vw + f) + 4);

      if (t < POP_END) {
        const n = Math.min(4, Math.floor(t / POP_STEP) + 1);
        const rise = easeOut(clamp(t / 120, 0, 1));
        sprite.show("pop", n);
        sprite.place(ahead, lerp(tab.bottom, ground, rise), lerp(0.4, 1, rise));
      } else {
        const step = t < RUN_END ? RUN_STEP : SPRINT_STEP;
        sprite.show("run", Math.floor((t - POP_END) / step) % FRAME_COUNT.run + 1);
        sprite.place(ahead, ground, 1);
      }
    });
  }

  document.addEventListener("click", (event) => {
    const link = event.target instanceof Element ? event.target.closest("a[data-carry]") : null;
    if (!link || event.defaultPrevented) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (link.target && link.target !== "_self") return;
    if (link.hasAttribute("download")) return;
    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin) return;
    if (url.pathname === location.pathname) return;
    if (reduce.matches) return;
    if (running) { event.preventDefault(); return; }
    if (!outReady) { warm(); return; }          // frames not here yet: a normal click, nothing half-played
    event.preventDefault();
    try {
      carryOut(link);
    } catch {
      cleanupOut();
      location.assign(link.href);
    }
  });

  // Intent: start loading the frames before the click.
  document.addEventListener("pointerover", (e) => { if (e.target instanceof Element && e.target.closest("a[data-carry]")) warm(); });
  document.addEventListener("focusin", (e) => { if (e.target instanceof Element && e.target.closest("a[data-carry]")) warm(); });
  window.addEventListener("load", () => {
    if (reduce.matches || !document.querySelector("a[data-carry]")) return;
    if (navigator.connection && navigator.connection.saveData) return;
    (window.requestIdleCallback || ((fn) => setTimeout(fn, 1200)))(warm);
  });

  // Back button (page restored from the cache with the run frozen on it): put the page back as it was.
  window.addEventListener("pageshow", (event) => { if (event.persisted) { cleanupOut(); clearIn(); } });

  // ---------- The new page ----------
  function clearIn() {
    root.classList.remove("carry-in", "carry-play");
    root.style.removeProperty("--carry-ink-x");
  }

  function arrive() {
    const ring = document.querySelector("[data-carry-ring]");
    const ringImg = ring && ring.querySelector("img");
    if (!ringImg) { clearIn(); return; }   // this page has no ring to land in: just show it
    const objects = [...document.querySelectorAll("[data-carry-objects] > *")];
    objects.forEach((el, i) => {   // carry.css plays the drop; these are its delay and length
      el.style.setProperty("--carry-delay", `${OBJECTS_START + i * OBJECTS_STEP}ms`);
      el.style.setProperty("--carry-drop-ms", `${OBJECT_MS}ms`);
    });

    const slow = new Promise((_, reject) => setTimeout(() => reject(new Error("frames slow")), 600));
    Promise.race([ready(["run", "wave"]), slow]).then(() => {
      const vw = window.innerWidth, f = feather();
      const target = ringImg.getBoundingClientRect();
      const h = clamp(target.height, 90, 280), w = h * 2 / 3;
      const ringX = target.left + (target.width - w) / 2;
      const runner = makeSprite(["run"], h);
      document.body.append(runner.el);
      root.classList.add("carry-play");
      setInk(-f);

      const waves = WAVE_SEQUENCE.map((n) => frameUrl("wave", n));
      const end = Math.max(REVEAL_MS + waves.length * WAVE_STEP,
                           OBJECTS_START + Math.max(objects.length - 1, 0) * OBJECTS_STEP + OBJECT_MS);
      let handoff = null;      // the time he reached the ring and the wave began

      return run(end, (t) => {
        // The ink leaves left to right; he runs on the paper just behind its edge until he is at the ring.
        const edge = lerp(-f, vw, easeInOut(clamp(t / REVEAL_MS, 0, 1)));
        setInk(edge);
        if (handoff === null) {
          const x = Math.min(ringX, edge - w);
          if (x >= ringX - 0.5 || t >= REVEAL_MS) {
            handoff = t;
            runner.el.remove();
            ring.classList.add("is-here");
          } else {
            runner.show("run", Math.floor(t / RUN_STEP) % FRAME_COUNT.run + 1);
            runner.place(x, target.bottom, 1);
          }
        }
        if (handoff !== null) {
          const src = waves[Math.min(waves.length - 1, Math.floor((t - handoff) / WAVE_STEP))];
          if (ringImg.getAttribute("src") !== src) ringImg.src = src;
        }
      });
    }).catch(() => {}).then(() => {
      document.querySelectorAll(".carry-doddy").forEach((el) => el.remove());
      ring.classList.add("is-here");
      clearIn();
    });
  }

  // Did the last page send us here? Read the flag once, then drop it.
  let arriving = false;
  try {
    const raw = sessionStorage.getItem(FLAG);
    if (raw) {
      sessionStorage.removeItem(FLAG);
      const [stamp, to] = raw.split("|");
      const same = (a, b) => a.replace(/\/+$/, "") === b.replace(/\/+$/, "");
      if (!reduce.matches && Date.now() - Number(stamp) < FRESH_MS && to && same(to, location.pathname)) arriving = true;
    }
  } catch { /* storage blocked: a direct visit looks the same */ }

  if (arriving) {
    root.classList.add("carry-in");               // the ink is already over the page before it paints
    setTimeout(clearIn, ARRIVE_FAILSAFE_MS);      // never leave the page covered
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", arrive, { once: true });
    else arrive();
  }
})();

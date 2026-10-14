// "What can Doddy do?" Plain script, no libraries. Nothing is stored and nothing leaves the page except
// the waitlist form (same endpoint and consent wording as the homepage). The page is complete without it:
// every scene is its finished card, every object a link, the day strip a list of links.

(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const phone = window.matchMedia("(max-width: 700px)");
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const POSES = "/assets/day/poses/";
  const WAITLIST_URL = "/api/waitlist";
  const CONSENT_VERSION = "waitlist-note-v1";  // same note text as the homepage form

  // ---------- Helpers ----------
  // Animated images use one file per role (large for the hero and the join panel, small elsewhere),
  // so a frame swap is one request, or none when it is already loaded.
  const poseUrl = (name, big) => `${POSES}${name}${big ? "" : "-320"}.webp`;
  function setPose(img, name) {
    img.removeAttribute("srcset");
    img.src = poseUrl(name, img.dataset.big === "1");
  }
  const loaded = new Map();
  const keep = [];  // a preloading Image that gets garbage collected is cancelled, so hold on to them
  function loadFrame(name, big = false) {
    const key = poseUrl(name, big);
    if (!loaded.has(key)) {
      loaded.set(key, new Promise((resolve) => {
        const img = new Image();
        keep.push(img);
        img.onload = img.onerror = resolve;
        img.src = key;
      }));
    }
    return loaded.get(key);
  }
  const soon = (promise, ms = 800) => Promise.race([promise, new Promise((resolve) => setTimeout(resolve, ms))]);
  // The pack's strips: frames swapped at a fixed rate, never tweened.
  async function playFrames(img, names, fps = 8) {
    await soon(Promise.all(names.map((n) => loadFrame(n, img.dataset.big === "1"))));
    await new Promise((resolve) => {
      let i = 0;
      const next = () => {
        setPose(img, names[i]);
        i += 1;
        if (i < names.length) setTimeout(next, 1000 / fps); else resolve();
      };
      next();
    });
  }
  function swapText(el, text) {
    if (el.textContent === text) return;
    if (reduce.matches) { el.textContent = text; return; }
    el.classList.add("swap");
    setTimeout(() => { el.textContent = text; el.classList.remove("swap"); }, 120);
  }
  function preload(names, big = false) { names.forEach((n) => loadFrame(n, big)); }
  const pad = (n) => String(n).padStart(2, "0");

  // One thing at a time: a beat, a travel or a surprise, never two together.
  let busy = 0;
  let lastMove = 0;
  function moveStart() { busy += 1; lastMove = performance.now(); }
  function moveEnd() { busy = Math.max(0, busy - 1); lastMove = performance.now(); }
  function whenQuiet(fn, gap = 0) {
    if (busy > 0 || performance.now() - lastMove < gap) setTimeout(() => whenQuiet(fn, gap), 200); else fn();
  }

  const moments = $$(".moment");
  const passed = new Set();   // moments the visitor has scrolled to, in memory only

  // ---------- Hero: the visitor's clock, Doddy's reactions ----------
  const hero = $(".wcd-hero");
  const stage = $(".stage");
  const heroImg = $("#hero-doddy");
  const heroSays = $(".stage .says");
  const heroLine = $("#hero-line");
  const objs = $$(".obj");
  requestAnimationFrame(() => requestAnimationFrame(() => hero.classList.add("loaded")));

  const HOURS = [
    { to: 5, pose: "shush", line: "Why are we both awake?" },
    { to: 10, pose: "yawn_stretch", line: "Morning. Ish." },
    { to: 12, pose: "wave", line: "Pick one." },
    { to: 14, pose: "fistpump", line: "Lunch. Finally." },
    { to: 18, pose: "leaning", line: "Still here." },
    { to: 24, pose: "crosslegged", line: "Nearly done for the day." },
  ];
  const timed = moments.map((m) => {
    const t = /^(\d\d):(\d\d)$/.exec(m.dataset.time);
    return t && { m, minutes: Number(t[1]) * 60 + Number(t[2]) };
  }).filter(Boolean);

  const now = new Date();
  const minutes = now.getHours() * 60 + now.getMinutes();
  const hourInfo = HOURS.find((h) => now.getHours() < h.to);
  const nearest = minutes < 5 * 60 ? timed[0]
    : timed.reduce((a, b) => (Math.abs(b.minutes - minutes) < Math.abs(a.minutes - minutes) ? b : a));
  // The visitor's own clock; nothing is sent or kept.
  $("#clock-text").textContent = `It's ${pad(now.getHours())}:${pad(now.getMinutes())} where you are`;
  const start = $("#start-day");
  start.textContent = `Start at ${nearest.m.dataset.time}`;
  start.setAttribute("href", `#${nearest.m.id}`);

  const rest = { pose: hourInfo.pose, line: hourInfo.line };
  heroImg.dataset.pose = "wave";
  // The line lives in a span so its underline stays put while the words change.
  function swapLine(line) {
    if (heroLine.textContent === line) return;
    if (reduce.matches) { heroLine.textContent = line; return; }
    heroSays.classList.add("swap");
    setTimeout(() => { heroLine.textContent = line; heroSays.classList.remove("swap"); }, 120);
  }
  function show(pose, line) {
    if (heroImg.dataset.pose !== pose) {
      setPose(heroImg, pose);
      heroImg.dataset.pose = pose;
      heroImg.alt = "Doddy";
    }
    swapLine(line);
  }
  let leaveTimer = null;
  function react(o) { clearTimeout(leaveTimer); show(o.dataset.pose, o.dataset.line); }
  function calm() { clearTimeout(leaveTimer); leaveTimer = setTimeout(() => show(rest.pose, rest.line), 300); }

  let lastType = "mouse";
  objs.forEach((o) => {
    o.addEventListener("pointerenter", (e) => { if (e.pointerType === "mouse") react(o); });
    o.addEventListener("pointerleave", (e) => { if (e.pointerType === "mouse") calm(); });
    o.addEventListener("focus", () => react(o));
    o.addEventListener("blur", calm);
    o.addEventListener("pointerdown", (e) => { lastType = e.pointerType; });
    // No hover on a phone: the first tap is the hover, the second opens the moment.
    o.addEventListener("click", (e) => {
      if (lastType === "touch" && !o.classList.contains("is-active")) {
        e.preventDefault();
        objs.forEach((x) => x.classList.toggle("is-active", x === o));
        react(o);
      }
    });
  });
  document.addEventListener("pointerdown", (e) => {
    if (!e.target.closest(".obj") && objs.some((x) => x.classList.contains("is-active"))) {
      objs.forEach((x) => x.classList.remove("is-active"));
      calm();
    }
  });

  // Arrival: Doddy pops in, the seven objects drop in 60 ms apart. Never under reduced motion.
  preload(["facepalm", "listening", "fistpump", "tiptoe", "kneeling_inspect", "reaching_high", "shush"], true);
  if (!reduce.matches) {
    objs.forEach((o, i) => o.style.setProperty("--i", String(i)));
    stage.classList.add("intro");
    const go = () => {
      stage.classList.add("in");
      const last = rest.pose === "wave" ? ["wave_2", "wave_4", "wave"] : [rest.pose];
      playFrames(heroImg, ["pop_2", "pop_3", "pop_4"], 8).then(() => playFrames(heroImg, last, 8)).then(() => {
        heroImg.dataset.pose = rest.pose;
        if (rest.pose !== "wave") heroImg.alt = "Doddy";
        swapLine(rest.line);
        setTimeout(() => { stage.classList.remove("intro", "in"); }, 500);
      });
    };
    soon(Promise.all(["pop_2", "pop_3", "pop_4", ...(rest.pose === "wave" ? ["wave_2", "wave_4"] : [rest.pose])].map((n) => loadFrame(n, true))), 900).then(go);
  } else {
    show(rest.pose, rest.line);
  }

  // ---------- Day strip: which moment is in view; and how long each one held the visitor ----------
  const strip = $$(".daystrip .chapters a");
  const stripList = $(".daystrip .chapters");
  const byId = Object.fromEntries(strip.map((a) => [a.hash.slice(1), a]));
  const dwell = {};
  let current = null;
  let since = performance.now();
  function flush() {
    const t = performance.now();
    if (current) dwell[current] = (dwell[current] || 0) + (t - since);
    since = t;
  }
  function setCurrent(id) {
    flush();
    current = id;
    passed.add(id);
    strip.forEach((a) => a.setAttribute("aria-current", String(a === byId[id])));
    const link = byId[id];
    if (link && stripList.scrollWidth > stripList.clientWidth) {
      stripList.scrollTo({ left: Math.max(0, link.offsetLeft - 16), behavior: reduce.matches ? "auto" : "smooth" });
    }
  }
  const stripObserver = new IntersectionObserver((entries) => {
    entries.forEach((en) => { if (en.isIntersecting) setCurrent(en.target.id); });
  }, { rootMargin: "-40% 0px -40% 0px", threshold: 0 });
  moments.forEach((m) => stripObserver.observe(m));
  document.addEventListener("visibilitychange", () => { flush(); });

  // ---------- Scenes: three beats, once, when the card is 40% in view (a chip plays it on phones) ----------
  const BEATS = ["b1", "b2", "b2b", "b3", "b4"];
  function splitWords(line) {
    if (line.dataset.split) return;
    const words = line.textContent.split(" ");
    line.textContent = "";
    words.forEach((word, i) => {
      const span = document.createElement("span");
      span.className = "w";
      span.textContent = word;
      span.style.setProperty("--d", `${Math.round((i * 700) / words.length)}ms`);
      line.append(span);
      if (i < words.length - 1) line.append(" ");
    });
    line.dataset.split = "1";
  }
  function prime(scene) {
    const bubble = $(".d-bubble .line", scene);
    if (bubble) { splitWords(bubble); bubble.closest(".d-bubble").classList.remove("show", "done"); bubble.closest(".d-bubble").classList.add("typing"); }
    scene.classList.remove(...BEATS);
    scene.classList.add("primed");
  }
  function updateChip(scene) {
    const chip = $(".play-chip", scene);
    if (chip) chip.hidden = reduce.matches || !(phone.matches || scene.classList.contains("has-played"));
  }
  function play(scene) {
    if (scene.classList.contains("is-running")) return;
    moveStart();
    scene.classList.add("is-running");
    scene.classList.remove("has-played");
    prime(scene);
    void scene.offsetWidth;
    const enter = $(".r-enter", scene);
    const bubble = $(".d-bubble", scene);
    const frames = (enter.dataset.frames || "").split(",").filter(Boolean);
    const at = (ms, fn) => setTimeout(fn, ms);
    scene.classList.add("b1");                                     // 0 ms: the problem
    if (frames.length) playFrames(enter, frames, 8);
    at(600, () => scene.classList.add("b2"));                       // your ask
    at(750, () => { scene.classList.add("b2b"); bubble.classList.add("show"); });  // pose swap, Doddy's line
    at(1450, () => { bubble.classList.add("done"); scene.classList.add("b3"); });  // the fix: the app's card
    at(1600, () => scene.classList.add("b4"));                      // the stamp
    at(2100, () => {                                               // at rest: the finished card
      scene.classList.remove("primed", ...BEATS, "is-running");
      bubble.classList.remove("typing", "show");
      scene.classList.add("has-played");
      updateChip(scene);
      moveEnd();
    });
  }

  const scenes = $$(".scene");
  scenes.forEach((scene) => {
    const chip = $(".play-chip", scene);
    if (chip) chip.addEventListener("click", () => play(scene));
    updateChip(scene);
  });
  if (!reduce.matches && !phone.matches) {
    scenes.forEach(prime);
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        const scene = en.target.closest(".scene");
        if (en.isIntersecting && scene.classList.contains("primed") && !scene.classList.contains("is-running")) {
          io.unobserve(en.target);
          whenQuiet(() => play(scene));
        }
      });
    }, { threshold: 0.4 });
    scenes.forEach((scene) => io.observe($(".scene-card", scene)));
  }

  // The visitor's choices inside a scene change the card's text.
  $$(".choices").forEach((group) => {
    const target = $("[data-choice-target]", group.closest(".scene"));
    group.addEventListener("change", (event) => {
      const text = event.target.dataset.text;
      if (text && target) swapText(target, text);
    });
  });

  // ---------- Between moments, and one surprise per visit ----------
  const SURPRISE = ["peek", "balance", "yawn", "shush"][Math.floor(Date.now() / 864e5) % 4];  // seeded by the date; nothing stored
  const SURPRISES = {
    balance: { pose: "oneleg_balance", line: "Balance. Mostly." },
    yawn: { pose: "yawn_stretch", line: "Long day." },
  };
  preload(["walk_3", "walk_5", "walk_7", "run_2", "run_4", "run_6", "kneeling_inspect", ...(SURPRISES[SURPRISE] ? [SURPRISES[SURPRISE].pose] : [])]);
  const travels = $$(".travel");
  async function runTravel(t) {
    moveStart();
    const doddy = $(".t-doddy", t);
    const line = $(".line", t);
    let frames = t.dataset.frames.split(",");
    const sur = t.dataset.surprise;
    if (sur && sur === SURPRISE && passed.size >= 2) {
      frames = [SURPRISES[sur].pose];
      line.textContent = SURPRISES[sur].line;
    }
    t.classList.remove("primed");
    t.classList.add("go");
    await playFrames(doddy, frames, t.dataset.kind === "look" ? 2.5 : 8);
    setTimeout(moveEnd, 700);
  }
  if (!reduce.matches) {
    travels.forEach((t) => { t.classList.add("primed"); setPose($(".t-doddy", t), t.dataset.frames.split(",")[0]); });
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting) { io.unobserve(en.target); whenQuiet(() => runTravel(en.target)); }
      });
    }, { threshold: 0.6 });
    travels.forEach((t) => io.observe(t));
  }

  function reveal(el, ...more) {
    [el, ...more].forEach((x) => x && (x.hidden = false));
    if (reduce.matches) return;
    el.classList.add("pre");
    void el.offsetWidth;
    el.classList.add("in");
    el.classList.remove("pre");
  }
  if (SURPRISE === "peek") {
    const card = $("#brain .scene-card");
    const peek = $(".peek", card);
    new IntersectionObserver(([en], io) => {
      if (en.isIntersecting && passed.size >= 2) { io.disconnect(); whenQuiet(() => reveal(peek, $(".peek-note", card)), 2000); }
    }, { threshold: 0.6 }).observe(card);
  } else if (SURPRISE === "shush") {
    const figure = $(".surprise-shush");
    new IntersectionObserver(([en], io) => {
      if (en.isIntersecting && passed.size >= 2) { io.disconnect(); whenQuiet(() => reveal(figure), 2000); }
    }, { threshold: 0.4 }).observe($(".truth-panel"));
  }

  // ---------- Send this one to someone ----------
  function say(el, text) {
    if (!el) return;
    el.textContent = text;
    setTimeout(() => { el.textContent = ""; }, 2600);
  }
  async function shareMoment(id, statusEl) {
    const section = document.getElementById(id);
    const url = `${location.origin}${location.pathname}#${id}`;
    if (navigator.share) {
      try { await navigator.share({ title: document.title, text: section.dataset.share, url }); return; }
      catch (error) { if (error && error.name === "AbortError") return; }
    }
    try { await navigator.clipboard.writeText(url); say(statusEl, "Copied"); }
    catch { say(statusEl, "Copy the link from the address bar"); }
  }
  $$("[data-send]").forEach((link) => {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      shareMoment(link.dataset.send, $(".send-status", link.closest(".send-row")));
    });
  });

  // The day signs off by suggesting the moment that held the visitor longest (08:45 if none did).
  const signoff = $("[data-signoff]");
  function bestMoment() {
    flush();
    let best = moments[0];
    let most = 1500;
    moments.forEach((m) => { if ((dwell[m.id] || 0) > most) { most = dwell[m.id]; best = m; } });
    return best;
  }
  function updateSignoff() {
    const best = bestMoment();
    $(".so-who").textContent = best.dataset.who;
    $(".so-time").textContent = best.dataset.time;
    signoff.setAttribute("href", `#${best.id}`);
    signoff.dataset.id = best.id;
  }
  new IntersectionObserver(([en]) => { if (en.isIntersecting) updateSignoff(); }, { threshold: 0.6 }).observe(signoff.closest(".signoff"));
  signoff.addEventListener("click", (event) => {
    event.preventDefault();
    updateSignoff();
    shareMoment(signoff.dataset.id, $(".send-status", signoff.parentElement));
  });

  // ---------- Waitlist (same endpoint, consent wording and checks as the homepage form) ----------
  const form = $(".waitlist");
  const email = $("#email", form);
  const status = $("#waitlist-status", form);
  const submit = $("button", form);
  const joinPose = $("#join-pose");
  function say2(text, kind) { status.textContent = text; status.className = `status ${kind || ""}`.trim(); }
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!email.value.trim() || !email.checkValidity()) {
      email.setAttribute("aria-invalid", "true");
      say2("Enter an email address, like name@example.com.", "err");
      email.focus();
      return;
    }
    email.removeAttribute("aria-invalid");
    submit.disabled = true;
    say2("Sending…");
    try {
      const res = await fetch(WAITLIST_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.value.trim(), page: location.origin + location.pathname, consent: CONSENT_VERSION, website: $("#website", form).value }),
      });
      const reply = await res.json();
      if (reply.ok) {
        say2("You're on the list. We'll email you when early access opens.", "ok");
        form.reset();
        // The one animation tied to a real event: the fist pump becomes a wave.
        if (!reduce.matches) playFrames(joinPose, ["wave_2", "wave_4", "wave"], 8);
      } else if (reply.error === "invalid_email") {
        email.setAttribute("aria-invalid", "true");
        say2("That email address doesn't look right. Check it and try again.", "err");
      } else {
        throw new Error(reply.error);
      }
    } catch {
      say2("That didn't go through. Check your connection and try again.", "err");
    } finally {
      submit.disabled = false;
    }
  });
})();

// Doddy landing page. No trackers, no cookies, no storage.

// Where the waitlist form posts { email } as JSON. Empty = waitlist not open: nothing is sent.
const WAITLIST_URL = "";
// Deep link into the app. The app must register this URL scheme first (see site/README.md).
const APP_URL = "doddy://home";

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const poseSrc = (name, scheme) => `assets/poses/doddy-pose-${name}-${scheme}-v1.3-r1.svg`;
const screenSrc = (name) => `assets/screens/${name}.png`;

function setPose(picture, name) {
  picture.querySelector("source").srcset = poseSrc(name, "dark");
  picture.querySelector("img").src = poseSrc(name, "light");
}

// Swap with a short fade unless reduced motion is on.
function swap(el, apply) {
  if (reduceMotion.matches) { apply(); return; }
  el.classList.add("swap");
  setTimeout(() => { apply(); el.classList.remove("swap"); }, 180);
}

// ---------- Headings: draw the orange underline once, when seen ----------
const headingObserver = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    if (entry.isIntersecting) {
      entry.target.classList.add("drawn");
      headingObserver.unobserve(entry.target);
    }
  }
}, { threshold: 0.6 });
document.querySelectorAll(".display").forEach((h) => headingObserver.observe(h));

// ---------- Sticky stage: phone screen and Doddy's pose follow the story ----------
const stage = document.querySelector(".stage");
const stagePose = stage.querySelector(".stage-pose");
const stageScreen = stage.querySelector(".stage-screen");
const voiceStates = [...stage.querySelectorAll(".voice-states li")];
let current = { pose: "approaching", screen: "welcome" };
let voiceTimers = [];

function playVoiceStates() {
  voiceTimers.forEach(clearTimeout);
  voiceTimers = [];
  voiceStates.forEach((li) => li.classList.remove("on", "now"));
  const step = (i) => {
    voiceStates.forEach((li, j) => { li.classList.toggle("on", j <= i); li.classList.toggle("now", j === i); });
  };
  if (reduceMotion.matches) { step(voiceStates.length - 1); return; }
  voiceStates.forEach((_, i) => voiceTimers.push(setTimeout(() => step(i), 150 + i * 650)));
}

function show(beat) {
  const { pose, screen } = beat.dataset;
  const isVoice = screen === "voice";
  stage.classList.toggle("is-voice", isVoice);
  if (isVoice) playVoiceStates();
  if (pose !== current.pose) swap(stagePose, () => setPose(stagePose, pose));
  if (!isVoice && screen !== current.screen) swap(stageScreen, () => { stageScreen.src = screenSrc(screen); });
  current = { pose, screen: isVoice ? current.screen : screen };
}

const beatObserver = new IntersectionObserver((entries) => {
  for (const entry of entries) if (entry.isIntersecting) show(entry.target);
}, { rootMargin: "-45% 0px -45% 0px" });
document.querySelectorAll(".beat").forEach((b) => beatObserver.observe(b));

// One orchestrated arrival: Doddy walks in, settles, then waves.
if (reduceMotion.matches) {
  setPose(stagePose, "waving");
  current.pose = "waving";
} else {
  stagePose.classList.add("arrive");
  setTimeout(() => {
    stagePose.classList.remove("arrive");
    if (current.pose === "approaching") { swap(stagePose, () => setPose(stagePose, "waving")); current.pose = "waving"; }
  }, 900);
}

// ---------- Sketchbook: Doddy takes a shot ----------
const shot = document.querySelector(".shot");
const shotPicture = shot.querySelector("picture");
let shooting = false;
shot.addEventListener("click", () => {
  if (shooting) return;
  shooting = true;
  const frames = [["basketball-gather", 0], ["basketball-shot", 260], ["basketball-follow-through", 620], ["basketball-dribble", 1700]];
  for (const [name, at] of frames) setTimeout(() => setPose(shotPicture, name), reduceMotion.matches ? 0 : at);
  setTimeout(() => { shooting = false; }, reduceMotion.matches ? 0 : 1700);
  if (reduceMotion.matches) setPose(shotPicture, "basketball-shot");
});

// ---------- Waitlist ----------
const form = document.querySelector(".waitlist");
const email = form.querySelector("#email");
const status = form.querySelector("#waitlist-status");
const submit = form.querySelector("button");

function say(el, text, kind) {
  el.textContent = text;
  el.className = `status ${kind || ""}`.trim();
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!email.value.trim() || !email.checkValidity()) {
    email.setAttribute("aria-invalid", "true");
    say(status, "Enter an email address, like name@example.com.", "err");
    email.focus();
    return;
  }
  email.removeAttribute("aria-invalid");
  if (!WAITLIST_URL) {
    say(status, "The waitlist isn't open yet, so nothing was sent. Check back soon.");
    return;
  }
  submit.disabled = true;
  say(status, "Sending…");
  try {
    const res = await fetch(WAITLIST_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email.value.trim() }),
    });
    if (!res.ok) throw new Error(String(res.status));
    say(status, "You're on the list. We'll email you when early access opens.", "ok");
    form.reset();
  } catch {
    say(status, "That didn't go through. Check your connection and try again.", "err");
  } finally {
    submit.disabled = false;
  }
});

// ---------- Open the app, with a fallback ----------
const openApp = document.querySelector("#open-app");
const openStatus = document.querySelector("#open-app-status");
openApp.href = APP_URL;
openApp.addEventListener("click", (event) => {
  const onIPhone = /iPhone|iPod/.test(navigator.userAgent);
  if (!onIPhone) {
    event.preventDefault();
    say(openStatus, "Doddy runs on iPhone. Open this page on your iPhone to jump into the app.");
    return;
  }
  // If the app opened, the page goes to the background. If it's still visible, Doddy isn't installed.
  setTimeout(() => {
    if (document.visibilityState === "visible") {
      say(openStatus, "Doddy isn't on this iPhone yet. Join early access above to hear when it's ready.");
    }
  }, 1500);
});

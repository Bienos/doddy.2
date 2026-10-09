// Doddy landing page. No trackers, no cookies, no storage.

// The waitlist receiver's web app URL (tools/waitlist/Code.gs, writes to the "Doddy waitlist" sheet).
// Empty = waitlist not open: the form says so and sends nothing.
const WAITLIST_URL = "";
// Saved with each signup, so you know which wording of the form note someone agreed to.
const CONSENT_VERSION = "waitlist-note-v1";
// Deep link into the app. The app must register this URL scheme first (see site/README.md).
const APP_URL = "doddy://home";

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const poseSrc = (name, scheme) => `assets/poses/doddy-pose-${name}-${scheme}-v1.3-r1.svg`;

function setPose(picture, name) {
  picture.querySelector("source").srcset = poseSrc(name, "dark");
  picture.querySelector("img").src = poseSrc(name, "light");
}

// Poses swap to their dark drawings with the OS setting. An explicit data-theme="light"/"dark"
// on the root (set by a host page or a future toggle) wins, so the art always matches the tokens.
function syncPoseTheme() {
  const theme = document.documentElement.dataset.theme;
  const media = theme === "dark" ? "all" : theme === "light" ? "not all" : "(prefers-color-scheme: dark)";
  document.querySelectorAll("picture source").forEach((s) => { s.media = media; });
}
syncPoseTheme();
new MutationObserver(syncPoseTheme).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

// ---------- Hero: one arrival moment. Doddy settles, then the greeting underlines itself. ----------
const hero = document.querySelector(".hero");
requestAnimationFrame(() => requestAnimationFrame(() => hero.classList.add("loaded")));

// ---------- Voice: step through the app's real status words while the section is on screen ----------
const voiceStates = [...document.querySelectorAll(".voice-states li")];
let voiceTimer = null;
function showVoiceState(i) {
  voiceStates.forEach((li, j) => li.classList.toggle("now", j === i));
}
if (reduceMotion.matches) {
  showVoiceState(1);
} else {
  new IntersectionObserver(([entry]) => {
    clearInterval(voiceTimer);
    if (!entry.isIntersecting) return;
    let i = 0;
    showVoiceState(i);
    voiceTimer = setInterval(() => { i = (i + 1) % voiceStates.length; showVoiceState(i); }, 1400);
  }, { threshold: 0.4 }).observe(document.querySelector(".voice"));
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
    // text/plain (no Content-Type header) keeps this a simple request, which the Apps Script
    // receiver (tools/waitlist/Code.gs) accepts without a CORS preflight.
    const res = await fetch(WAITLIST_URL, {
      method: "POST",
      body: JSON.stringify({
        email: email.value.trim(),
        page: location.origin + location.pathname,
        consent: CONSENT_VERSION,
        website: form.querySelector("#website").value,
      }),
    });
    const reply = await res.json();
    if (reply.ok) {
      say(status, reply.status === "already"
        ? "You're already on the list. We'll email you when early access opens."
        : "You're on the list. We'll email you when early access opens.", "ok");
      form.reset();
    } else if (reply.error === "invalid_email") {
      email.setAttribute("aria-invalid", "true");
      say(status, "That email address doesn't look right. Check it and try again.", "err");
    } else {
      throw new Error(reply.error);
    }
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

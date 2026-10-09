// Doddy landing page. No trackers, no cookies, no storage.

// The site's own waitlist endpoint (api/waitlist.js): stores each email privately in Vercel Blob.
// Empty = waitlist not open: the form says so and sends nothing.
const WAITLIST_URL = "/api/waitlist";
// Saved with each signup, so you know which wording of the form note someone agreed to.
const CONSENT_VERSION = "waitlist-note-v1";
// Deep link into the app. The app must register this URL scheme first (see site/README.md).
const APP_URL = "doddy://home";

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

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

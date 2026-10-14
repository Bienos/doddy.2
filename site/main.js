// Doddy landing page. No cookies, no storage. Page views are counted by Vercel Web Analytics
// (script tag in index.html, served by Vercel); nothing here calls it.

// The site's own waitlist endpoint (api/waitlist.js): stores each email privately in Vercel Blob.
// Empty = waitlist not open: the form says so and sends nothing.
const WAITLIST_URL = "/api/waitlist";
// Saved with each signup, so you know which wording of the form note someone agreed to.
// The form carries its own version (data-consent), one per language.
// Deep link into the app. The app must register this URL scheme first (see site/README.md).
const APP_URL = "doddy://home";

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

// ---------- Hero: one arrival moment. Doddy settles, then the greeting underlines itself. ----------
const hero = document.querySelector(".hero");
requestAnimationFrame(() => requestAnimationFrame(() => hero.classList.add("loaded")));

// ---------- Film: a muted 9-second preview loops while on screen; sound only after a tap ----------
const PREVIEW_SECONDS = 9;
const film = document.querySelector(".film");
const player = film.querySelector(".player");
const video = player.querySelector("video");
const chapters = [...film.querySelectorAll("[data-seek]")];
let filmFull = false;

// Take over from the native controls: muted, inline, no controls until someone asks for sound.
video.controls = false;
video.muted = true;
video.loop = true;
if (reduceMotion.matches) player.classList.add("still");

function playFull(at) {
  filmFull = true;
  player.classList.add("playing");
  video.loop = false;
  video.muted = false;
  video.controls = true;
  video.currentTime = at;
  video.play().catch(() => {});
}
player.querySelector(".cover").addEventListener("click", () => playFull(0));
chapters.forEach((button) => button.addEventListener("click", () => {
  playFull(Number(button.dataset.seek));
  video.focus();
}));
video.addEventListener("timeupdate", () => {
  if (!filmFull) {
    if (video.currentTime > PREVIEW_SECONDS) video.currentTime = 0;
    return;
  }
  const now = chapters.filter((b) => video.currentTime >= Number(b.dataset.seek)).pop();
  chapters.forEach((b) => b.setAttribute("aria-current", String(b === now)));
});
new IntersectionObserver(([entry]) => {
  if (entry.isIntersecting) film.classList.add("loaded");
  if (filmFull) return;
  if (entry.isIntersecting && !reduceMotion.matches) video.play().catch(() => {});
  else video.pause();
}, { threshold: 0.4 }).observe(player);

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
    say(status, doddyT("Enter an email address, like name@example.com."), "err");
    email.focus();
    return;
  }
  email.removeAttribute("aria-invalid");
  if (!WAITLIST_URL) {
    say(status, doddyT("The waitlist isn't open yet, so nothing was sent. Check back soon."));
    return;
  }
  submit.disabled = true;
  say(status, doddyT("Sending…"));
  try {
    const res = await fetch(WAITLIST_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: email.value.trim(),
        page: location.origin + location.pathname,
        consent: form.dataset.consent,
        website: form.querySelector("#website").value,
      }),
    });
    const reply = await res.json();
    if (reply.ok) {
      // Same words for a new and an already stored email, so the form can't tell anyone who signed up.
      say(status, doddyT("You're on the list. We'll email you when early access opens."), "ok");
      form.reset();
      if (reply.id && reply.key) askQuestions(reply.id, reply.key);
    } else if (reply.error === "invalid_email") {
      email.setAttribute("aria-invalid", "true");
      say(status, doddyT("That email address doesn't look right. Check it and try again."), "err");
    } else {
      throw new Error(reply.error);
    }
  } catch {
    say(status, doddyT("That didn't go through. Check your connection and try again."), "err");
  } finally {
    submit.disabled = false;
  }
});

// ---------- Optional questions after a new signup ----------
const answers = document.querySelector("#answers");
const answersStatus = document.querySelector("#answers-status");
const answersTitle = document.querySelector("#answers-title");
const answersSubmit = answers.querySelector('button[type="submit"]');
let signup = null;  // { id, key } from the signup reply; kept in memory only

function askQuestions(id, key) {
  signup = { id, key };
  form.hidden = true;
  answers.hidden = false;
  answersTitle.focus();
}
function finishQuestions(message) {
  answers.hidden = true;
  signup = null;
  say(status, message, "ok");
}
answers.querySelector("#answers-skip").addEventListener("click", () => {
  finishQuestions(doddyT("You're on the list. We'll email you when early access opens."));
});
answers.addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = new FormData(answers);
  const phone = data.get("phone") || "";
  const picked = { phone, heard: data.get("heard") || "", wish: String(data.get("wish") || "").trim() };
  const thanks = doddyT("Thanks, that helps a lot. We'll email you when early access opens.")
    + (phone === "android" ? doddyT(" Doddy starts on iPhone; we'll tell you if Android comes later.") : "");
  if (!picked.phone && !picked.heard && !picked.wish) { finishQuestions(doddyT("You're on the list. We'll email you when early access opens.")); return; }
  answersSubmit.disabled = true;
  say(answersStatus, doddyT("Sending…"));
  try {
    const res = await fetch("/api/waitlist-answers", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...signup, ...picked }),
    });
    const reply = await res.json();
    if (!reply.ok) throw new Error(reply.error);
    finishQuestions(thanks);
  } catch {
    say(answersStatus, doddyT("That didn't go through. Try again, or skip. You're on the list either way."), "err");
  } finally {
    answersSubmit.disabled = false;
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
    say(openStatus, doddyT("Doddy runs on iPhone. Open this page on your iPhone to jump into the app."));
    return;
  }
  // If the app opened, the page goes to the background. If it's still visible, Doddy isn't installed.
  setTimeout(() => {
    if (document.visibilityState === "visible") {
      say(openStatus, doddyT("Doddy isn't on this iPhone yet. Join early access above to hear when it's ready."));
    }
  }, 1500);
});

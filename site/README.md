# Doddy landing page

A static, single-page site that explains Doddy (the character) and the Doddy app, built from `prompts/LANDING_PAGE_DESIGN.md`. Nothing is deployed.

## Preview

```sh
cd site && python3 -m http.server 8765
# open http://localhost:8765
```

There's no build step: plain HTML, CSS and a small vanilla script. No cookies, no storage. Visits are counted with Vercel Web Analytics (see [Analytics](#analytics)).

## How it connects to the app

| Link | Where |
|---|---|
| Colours | `tokens.css` holds the app's light values only (the site is light-only by owner request, including on dark-mode devices). It is generated from `Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift`. Run `python3 -I tools/gen_site_tokens.py` after changing app tokens; `--check` fails if the site is out of date. |
| Character | `assets/poses/` are copies of the light poses in `design/interface-v1.2/assets/`. |
| Copy | Headings and disclosures reuse the app's words (`HomeView`, `VoiceView`, `SettingsView`, `RecallCopy.noMatch`). |
| Waitlist | The form posts to `api/waitlist.js` on the same site, which stores each signup as one private JSON file in the Vercel Blob store **doddy-waitlist** (region fra1, private access; the site gets `BLOB_READ_WRITE_TOKEN` automatically). Stored: email, page, consent version, time, plus the optional answers (phone, where they heard about Doddy, what they'd like Doddy to do). See the admin page at `/admin/` or download an Excel-ready CSV from `/api/waitlist-export` (password = `WAITLIST_ADMIN_PASSWORD`, any username). |
| Open Doddy | `APP_URL` in `main.js` (`doddy://home`); the app handles `doddy://home`, `memories` and `settings`. On non-iPhone devices it explains that Doddy runs on iPhone; on iPhone, if the page is still visible after 1.5 s, it says the app isn't installed. |
| App Store | Commented-out Smart App Banner in `index.html`; enable when there's an App Store ID. |

## What's real on the page

- **Design v3 (light editorial notebook):** light-only; brighter paper cards derived from the app's canvas, a warm glow and a "Saved" receipt chip in the hero, a light privacy panel, footer links. Headings in Bricolage Grotesque (OFL, Google Fonts), Caveat only for Doddy's own voice and the wordmark, system text for reading. Sections: hero, the brand film, the problem, three-step How it works, the note receipt, voice (In testing), privacy panel, Meet Doddy, Take a shot (basketball game), join. The example note in the receipt card is labelled as an example.
- **Screens are design previews**, copied from `design/interface-v1.2/previews/` and labelled "Design preview". Replace them with simulator screenshots of the native app (same file names in `assets/screens/`) once someone with Xcode captures them.
- The voice section has no app screenshot. It shows the app's real status words and its "Save this note?" card as an illustration, labelled as such, and is marked **In testing** because voice hasn't run on a real iPhone.
- Claims follow the feature table in the prompt: save, search, edit, export and delete are described as working; reminders and other languages sit under "Later, maybe" with no dates.

## Waitlist

- **Storage:** private Vercel Blob store `doddy-waitlist` (Frankfurt). One file per email, named by a SHA-256 hash of the email, so the same address is stored once and emails never appear in file names or logs.
- **Optional questions:** after a new signup the form is replaced by three optional questions (iPhone / Android / something else; where they heard about Doddy; what they'd like Doddy to do, max 300 characters). `api/waitlist.js` returns a one-time key to that browser and stores only its hash; `api/waitlist-answers.js` saves answers only with that key, keeps known choices only and strips formula characters. Skipping sends nothing. Android pickers are told Doddy starts on iPhone.
- **Checks in `api/waitlist.js`:** same-site origin only, 2 KB body limit, email format and length, honeypot field, leading formula characters stripped.
- **Admin page:** `/admin/` (Doddy style, not linked from the site, `noindex`). Sign in with `WAITLIST_ADMIN_PASSWORD`. Shows total, today, last 7 days, latest signup, answer breakdowns (phone, heard about Doddy, latest wishes), sign-ups per day (30 days, 14 on phones), and a searchable, filterable table (iPhone, Android, answered, has a wish) with copy, delete (two taps, for removal requests), copy all emails and download for Excel. Data comes from `api/waitlist-admin.js` (GET list, DELETE one by hashed id); shared code in `api/_waitlist-store.js`.
- **Download:** open `/api/waitlist-export` in a browser, enter any username and the `WAITLIST_ADMIN_PASSWORD`; you get `doddy-waitlist-YYYY-MM-DD.csv` (UTF-8 with BOM, opens in Excel). Change the password in Vercel → Project → Settings → Environment Variables, then redeploy.
- **Not built:** rate limiting beyond Vercel's defaults, double opt-in emails, multiple admin accounts.

## Analytics

Vercel Web Analytics counts page views and visitors on the landing page. It is the plain-HTML
setup from [vercel.com/docs/analytics](https://vercel.com/docs/analytics/quickstart), not the
`@vercel/analytics` package: `index.html` loads `/_vercel/insights/script.js`, which Vercel serves
from the site's own origin, after a two-line inline queue (`window.va`) so custom events can be
sent before the script has loaded. No npm dependency, no build step.

- **Turn it on:** Vercel → project `doddy` → Analytics → Enable, then deploy. Until that deploy
  is live, the script URL answers 404; the page works unchanged apart from one failed request in
  the browser console.
- **Where it runs:** only `index.html`. `/admin/` has no analytics, so the owner's own visits to
  the waitlist page don't count as traffic.
- **CSP:** `vercel.json` allows the inline queue by its SHA-256 hash; the script and its beacons
  (`/_vercel/insights/*`) are same-origin, so the existing `'self'` entries cover them. If the
  inline snippet changes, recompute the hash:
  `printf '%s' "<exact script contents>" | openssl dgst -sha256 -binary | base64`.
- **Privacy:** no cookies. Vercel identifies a visitor by a hash of the incoming request that it
  discards after 24 hours, and keeps page, referrer, country, device and browser class; see
  [Vercel's analytics privacy note](https://vercel.com/docs/analytics/privacy-policy). The footer
  says so. Check the wording against your privacy policy once there is one.
- **Custom events** (for example a waitlist signup) are possible with
  `window.va('event', { name: '...' })`; none are sent yet.

## Film

"One morning in Warsaw" sits directly after the hero (`#film`); the hero's second link reads "Watch the film (1:20)" and jumps to it. Design: concept A from `design/landing-film-mockup/` (owner-picked).

- **Files:** `assets/film/doddy-film.mp4` (H.264 + AAC, 854×480, 1:20, faststart, 5.6 MB) re-encoded from the owner's `DODDY-LOW_RES.mov` (HEVC, which most desktop Chrome and Firefox can't play); `assets/film/poster.jpg` is the frame at 0:03. Same-origin, so the existing CSP (`default-src 'self'`) covers it; `/assets/` caching applies.
- **Behaviour (`main.js`):** a muted 9-second preview loops while the film is on screen and pauses off screen. Tapping the play button or a chapter turns sound on, shows native controls and plays from 0:00 or that chapter. Reduced motion: no autoplay, poster until tapped. Without JavaScript it is a plain video with native controls and no chapter list.
- **Chapters** are cut at the film's scene changes and named from what's on screen; rename them if the voice-over calls the moments something else.
- **Not done:** captions (add a WebVTT `<track>` once the script is final), a higher-resolution master, an AV1/WebM copy, and analytics events for plays.

## Needs the owner

1. **Check the deep link on an iPhone.** The app now registers `doddy://` (`project.yml`) and opens `home`, `memories` or `settings` (`DeepLink` in DoddyCore, handled in `RootView`). Not yet built or tried on a device. Universal Links (needs a domain and an `apple-app-site-association` file) would remove the "isn't installed" guesswork later.
2. **Waitlist:** add a contact address people can use to ask for deletion; the form promises deletion on request.
3. **Domain, contact address and privacy policy.** Hosted on Vercel (project `doddy`, team bienos) at https://doddy-eight.vercel.app, deployed from this branch to production. The Vercel project's production branch is the repo default (`claude/loving-dirac-uuxoux`), so pushes here create previews; redeploy production after changes, or point the production branch at this one in Vercel settings. No custom domain, contact address or privacy policy yet.
4. **Fonts:** Bricolage Grotesque and Caveat (both OFL) load from Google Fonts, which sends visitors' IP addresses to Google. For an EU audience, self-host them after licence review; the CSS falls back to system fonts without them.
5. **Brand approval:** colours, character drawings and wordmark are candidates (`docs/design/CANONICAL_DESIGN_DIRECTION.md`), not an approved brand.

## Checked (2026-10-09, design v3, headless Chromium 1194 via Playwright, local server)

- 1440, 390 and 320 px widths, with the OS in light and in dark mode (the page stays light): no horizontal scroll, no console errors. Screenshots in `VISUAL_REVIEW/landing/`.
- Under the production CSP from `vercel.json`: scripts, fonts and poses load, no violations.
- Dark OS setting and an explicit `data-theme="dark"` both still render the light page and light poses.
- Waitlist form against a mocked `/api/waitlist`: added, already on the list, invalid email, server busy; body is JSON with email, page, consent version and the empty honeypot.
- `api/waitlist.js` and `api/waitlist-export.js` against an in-memory Blob stand-in: added, already, invalid, formula email, honeypot, bad JSON, oversized body, foreign origin, hashed file names; export locked without/with wrong password, CSV with BOM, quoting and formula neutralising.
- Admin page against a mocked API at 1440 and 390 px: wrong password refused, stats, chart tooltip on hover, search, two-step delete, copy, download, stays signed in on reload, an `<img onerror>` "email" renders as text. Admin API against the in-memory Blob stand-in: list, delete, bad id, wrong password, export after delete.
- Optional questions: browser flow at 1280 and 390 px (focus moves to the questions, chips work by keyboard, answers sent with id and key, Skip sends nothing, Android note); `api/waitlist-answers.js` against the Blob stand-in (wrong key, unknown id, foreign origin, unknown choices dropped, wish capped and formula-stripped, admin never sees the key hash, CSV has the new columns).
- "Take a shot" (`court.js`): auto shots and a dragged slingshot throw at 1440 and 390 px; "Shoot for me" lands about 60% of the time.
- Analytics (2026-10-09, headless Chromium 1194 via Playwright, local server sending the `vercel.json` headers, `/_vercel/insights/script.js` stubbed): under the production CSP the inline queue runs (`window.va` is a function), the script is requested and runs, queued calls land in `window.vaq`, no CSP violations, page or console errors; an unhashed inline script is still blocked; with the script answering 404 (analytics not enabled yet) the page works with no errors; 390 px has no horizontal scroll; `/admin/` carries no analytics. Not checked: the real Vercel script and that the dashboard shows data; that needs the deploy described under Analytics.

- Film (2026-10-09, headless Chromium 1194 via Playwright, local server sending the `vercel.json` headers): at 1440, 390 and 320 px no horizontal scroll, no console errors, no CSP violations; JS takes over (muted, no controls, play button and chapters shown); tapping play turns on sound and controls and stops the loop; chapter buttons respond; reduced motion leaves the film paused with the poster; with JavaScript off the native controls show and the play button and chapters are hidden. At 1440×900 the film starts 93 px below the first screen. Screenshots: `VISUAL_REVIEW/landing/v3-film-1440.png`, `v3-film-390.png`. Not checked: actual playback, seeking and sound (Playwright's Chromium has no H.264 decoder), iPhone Safari inline autoplay, Low Power Mode.

Not checked: real Safari on iPhone (deep-link fallback timing, Dynamic Type zoom, touch throwing), VoiceOver, Lighthouse.

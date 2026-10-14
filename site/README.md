# Doddy landing page

A static, single-page site that explains Doddy (the character) and the Doddy app, built from `prompts/LANDING_PAGE_DESIGN.md`. Live on Vercel at https://www.doddy.lol (project `doddy`, team `doddyyyy`; `https://doddy.lol` redirects to it). See "Needs the owner" for hosting details.

## Preview

```sh
cd site && python3 -m http.server 8765
# open http://localhost:8765
```

There's no build step: plain HTML, CSS and a small vanilla script. Visits are counted with Vercel Web Analytics (no cookies) and, only for visitors who allow it, Google Analytics 4 (cookies); see [Analytics](#analytics).

## How it connects to the app

| Link | Where |
|---|---|
| Colours | `tokens.css` holds the app's light values only (the site is light-only by owner request, including on dark-mode devices). It is generated from `Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift`. Run `python3 -I tools/gen_site_tokens.py` after changing app tokens; `--check` fails if the site is out of date. |
| Character | `assets/day/` holds the owner's `DODDY-Numbered-Video-Assets-v01` pack as WebP (poses at 640 and 320 px, 16:9 scenery at 1600 and 800 px, props, effects, one face); every pose, scene and prop on the homepage and on `/what-can-doddy-do/` comes from it (CLAUDE.md, 11 October). `assets/poses/` still holds the v1.3 SVGs, which `court.js` (the canvas game) and the blog banners (`tools/build_blog.py`) draw, so those two still show the old Doddy; see "Needs the owner". The favicon and touch icon are a square cut of the pack's wave frame (`assets/doddy-favicon.png`, `assets/doddy-touch-icon.png`). |
| Copy | Headings and disclosures reuse the app's words (`HomeView`, `VoiceView`, `SettingsView`, `RecallCopy.noMatch`). |
| Waitlist | The form posts to `api/waitlist.js` on the same site, which stores each signup as one private JSON file in the Vercel Blob store **doddy-waitlist** (region fra1, private access; the site gets `BLOB_READ_WRITE_TOKEN` automatically). Stored: email, page, consent version, time, plus the optional answers (phone, where they heard about Doddy, what they'd like Doddy to do). See the admin page at `/admin/` or download an Excel-ready CSV from `/api/waitlist-export` (password = `WAITLIST_ADMIN_PASSWORD`, any username). |
| Open Doddy | `APP_URL` in `main.js` (`doddy://home`); the app handles `doddy://home`, `memories` and `settings`. On non-iPhone devices it explains that Doddy runs on iPhone; on iPhone, if the page is still visible after 1.5 s, it says the app isn't installed. |
| Telegram | Community group link `https://t.me/+u-YA6P_MISFjYWE0` in the join section ("Want to chat now?") and the footer; opens in a new tab. Change it in both places in `index.html`. |
| Social | TikTok `https://www.tiktok.com/@doddy_mate` and Instagram `https://www.instagram.com/doddy_mate/` in the join section ("Follow Doddy", labelled with the handle) and the footer (labelled just "TikTok" and "Instagram"); open in a new tab. The app links the same two accounts from Settings → Follow Doddy (ADR-130). |
| App Store | Commented-out Smart App Banner in `index.html`; enable when there's an App Store ID. |
| Blog | `blog/` pages are **generated** by `tools/build_blog.py` from `../blog/posts/*.md` (published posts only); don't edit them by hand. Styles in `blog.css`. Linked from the nav and footer. See `../blog/README.md`. |
| What can Doddy do? | `what-can-doddy-do/index.html` and `day-scenes.css` are **generated** by `tools/build_day.py` (`--check` runs in `scripts/ci.sh`); hand-written are `day.css` and `day.js`. See [What can Doddy do?](#what-can-doddy-do). |
| Nav | One nav, six links and a phone menu (`nav.js`), on the homepage, the new page and every blog page. The blog and the new page share `tools/partials/site-nav.html`; the homepage nav is hand-kept with hash links, so change both together. |

## What's real on the page

- **Design v3 (light editorial notebook):** light-only; brighter paper cards derived from the app's canvas, a warm glow and a "Saved" receipt chip in the hero, a light privacy panel, footer links. Headings in Bricolage Grotesque (OFL, Google Fonts), Caveat only for Doddy's own voice and the wordmark, system text for reading. Sections (ADR-482, 14 October, "Say it once. Tap once. Done."): hero (one spoken sentence and the plan card it becomes, the app's `propose_plan` pattern, with ink icons for Calendar, Maps, Messages and Lists), the big asks (six cards: Gmail/Outlook, Calendar/Maps, Drive/Notion, translator, Shortcuts/Reminders, routines/Todoist; a swipe row on phones), the brand film, most agents vs Doddy, the phone line (spec'd, not live), Meet Doddy, Play (Take a shot and Remember it under one head), the privacy panel, and the join panel (same waitlist endpoint, payload, consent, honeypot and optional questions; new frame, three facts, scraps of example asks). Removed on 14 October: the problem section, What's real today, How it works, the three-moments teaser, the voice section. One honest line under the big asks and one in the footer link to `/what-can-doddy-do/` for what works today; that page keeps the only Built / In testing / Later, maybe list.
- **No app screenshots on the page (14 October, owner: change or remove them for now).** The hero and the three steps show example note cards drawn in HTML (`.hero-note`, `.step-card`), captioned "Example note" and "Examples, not screenshots of the app". The four design-preview PNGs in `assets/screens/` were deleted; they are still in git history and in `design/interface-v1.2/previews/`. When someone with Xcode can capture the native app, add real simulator screenshots back deliberately rather than reusing the design previews.
- The voice section has no app screenshot. It shows the app's real status words and its "Save this note?" card as an illustration, labelled as such, and is marked **In testing**. The owner had a first real iPhone conversation on 9 October (`docs/implementation/V1_VOICE_STATUS.md`); the fine print says only "Voice is in testing." (owner's instruction, 13 October).
- Claims follow the feature table in the prompt: save, search, edit, export and delete are described as working; reminders, voice and the rest sit under "In testing" and translation, restaurant picking and Android under "Later, maybe", with no dates (the "What's real today" strip).

## Waitlist

- **Storage:** private Vercel Blob store `doddy-waitlist` (Frankfurt). One file per email, named by a SHA-256 hash of the email, so the same address is stored once and emails never appear in file names or logs.
- **Optional questions:** after a new signup the form is replaced by three optional questions (iPhone / Android / something else; where they heard about Doddy; what they'd like Doddy to do, max 300 characters). `api/waitlist.js` returns a one-time key to that browser and stores only its hash; `api/waitlist-answers.js` saves answers only with that key, keeps known choices only and strips formula characters. Skipping sends nothing. Android pickers are told Doddy starts on iPhone.
- **Checks in `api/waitlist.js`:** same-site origin only, 2 KB body limit, email format and length, honeypot field, leading formula characters stripped.
- **Same reply for a known email:** a signup for an email already on the list gets the same `added` reply, without the answers key, so the form can't be used to check who signed up.
- **Answers can't bring a deleted signup back:** `api/waitlist-answers.js` writes only if the file is still the one it read (`ifMatch` on the etag). A signup deleted in between gets 403, and nothing is written.
- **Tests:** `npm test` in `site/` (also in `scripts/ci.sh`) runs the waitlist, answers, export and admin functions against an in-memory `@vercel/blob` stand-in (`test/fake-blob.js`), with no network. `.vercelignore` keeps `test/` out of the deployment.
- **Admin page:** `/admin/` (Doddy style, not linked from the site, `noindex`). Sign in with `WAITLIST_ADMIN_PASSWORD`. Shows total, today, last 7 days, latest signup, answer breakdowns (phone, heard about Doddy, latest wishes), sign-ups per day (30 days, 14 on phones), and a searchable, filterable table (iPhone, Android, answered, has a wish) with copy, delete (two taps, for removal requests), copy all emails and download for Excel. Data comes from `api/waitlist-admin.js` (GET list, DELETE one by hashed id); shared code in `api/_waitlist-store.js`.
- **Download:** open `/api/waitlist-export` in a browser, enter any username and the `WAITLIST_ADMIN_PASSWORD`; you get `doddy-waitlist-YYYY-MM-DD.csv` (UTF-8 with BOM, opens in Excel). Change the password in Vercel → Project → Settings → Environment Variables, then redeploy.
- **Not built:** rate limiting beyond Vercel's defaults, double opt-in emails, multiple admin accounts.
- **Admin password:** the admin routes have no lockout, so `WAITLIST_ADMIN_PASSWORD` must be long and random (for example `openssl rand -base64 24`), never a word.
- **Rate limit (owner, recommended):** add a Vercel Firewall rule (Project → Firewall → Rules): rate-limit `/api/` by IP to about 20 requests a minute. It needs no code, and slows scripted signups and admin password guessing. Not set yet.

## Languages (ADR-460)

- **Pages:** the landing page is in English and nine other languages: Spanish, German, French, Simplified Chinese, Japanese, Brazilian Portuguese, Italian, Croatian and Polish. Each has its own URL (`/de/`, `/zh-hans/`, …); `/` stays English. The header and footer have a language menu, and every page has `hreflang` links, its canonical URL and an entry in `sitemap.xml`. The blog is English only.
- **Sources:** `site/index.html` is the English master. `tools/build_site_i18n.py` writes every other page, `sitemap.xml` and the script dictionaries in `site/i18n/`. Don't edit those by hand. `--check` runs in `scripts/ci.sh` and fails when one is out of date.
- **Translations:** `l10n/site/<code>.json` maps English text to the language. `l10n/site/en.json` lists the keys. Work on them with `python3 -I tools/l10n_batch.py show|merge|status <code> --table site`. A new sentence in the master or in a script needs a line in every table; `--check` names the missing ones. `l10n/site/keep-english.json` lists the sentences that may stay in English (the tagline in the title).
- **Scripts:** text a script shows goes through `doddyT("English text", values)` in `site/i18n.js`. It returns the translation for the page's language, or the English. `{name}` is filled from the values.
- **Consent:** the signup form sends its consent wording version (`data-consent`). English uses `waitlist-note-v1`; each other language uses `waitlist-note-v1-<code>`, for example `waitlist-note-v1-de`. The API stores what the page sends. The versions are listed in `docs/legal/PRIVACY_POLICY_DRAFT.md`.
- **URLs:** a translated page lives in a folder (`/de/`), so every file URL in it must start with `/`: the generator rewrites `href`, `src`, `poster` and every `srcset` candidate, including those inside a text block, and `--check` fails on one it missed. Scripts must load images from `/assets/…`, never `assets/…`.
- **Status:** live at https://www.doddy.lol since 14 October. The translations are drafts until a native speaker has read them. On 14 October the Doddy pictures were broken on the nine translated pages (page-relative `srcset`); fixed and checked in a browser (every image loads, no HTTP 4xx).

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

### Google Analytics 4 (ADR-245)

`analytics.js`, loaded on `index.html` and every blog page (`tools/build_blog.py` adds it), not on `/admin/`.

- **Measurement ID:** `G-WQXYVSGD4Q`, the `GA_MEASUREMENT_ID` constant at the top of `analytics.js`
  (Google Analytics → Admin → Data streams → Web). Empty it to switch GA off: the file then does
  nothing, with no banner, no footer sentence and no request to Google.
- **Consent first:** GA sets cookies, so on a first visit a banner asks "Can we use Google
  Analytics?". Only **Allow** loads `https://www.googletagmanager.com/gtag/js`; **No thanks**
  sends nothing. The choice is stored in `localStorage` (`doddy-analytics-consent`) on that
  device. The footer's "Analytics choices" reopens the banner; switching to No thanks sets GA
  consent to denied and deletes the `_ga` / `_ga_*` cookies. If storage is blocked (private
  mode) the visitor is asked again next visit.
- **Settings:** ads storage, ad user data, ad personalisation and Google signals are off.
  No custom events yet (a waitlist signup event would be `gtag('event', 'sign_up')` after the
  visitor allowed GA).
- **CSP:** `vercel.json` allows `https://www.googletagmanager.com` in `script-src` and the GA
  collection hosts (`*.google-analytics.com`, `*.analytics.google.com`, `*.googletagmanager.com`)
  in `img-src` and `connect-src`, as Google's CSP guide lists. No inline script was added.
- **Privacy:** the footer says GA is used only if the visitor allows it. A privacy policy naming
  Google Analytics is still needed (see Needs the owner).

## Film

"One morning in Warsaw" sits directly after the hero (`#film`); the hero's second link reads "Watch the film (1:15)" and jumps to it. Design: concept A from `design/landing-film-mockup/` (owner-picked).

- **Files:** `assets/film/doddy-film-v2.mp4` (H.264 + AAC, 854×480, 30 fps, 1:15, faststart, 5.6 MB) re-encoded from the owner's `doddy_new1.mov` (HEVC, which most desktop Chrome and Firefox can't play); `assets/film/poster-v2.jpg` is the frame at 0:03. A new cut gets a new file name (`-v3`, …) because `/assets/` is cached for a day. Same-origin, so the existing CSP (`default-src 'self'`) covers it; `/assets/` caching applies.
- **Behaviour (`main.js`):** a muted 9-second preview loops while the film is on screen and pauses off screen. Tapping the play button or a chapter turns sound on, shows native controls and plays from 0:00 or that chapter. Reduced motion: no autoplay, poster until tapped. Without JavaScript it is a plain video with native controls and no chapter list.
- **Chapters** are cut at the film's scene changes and named from what's on screen; rename them if the voice-over calls the moments something else.
- **Not done:** captions (add a WebVTT `<track>` once the script is final), a higher-resolution master, an AV1/WebM copy, and analytics events for plays.

## Remember it

A memory card game after "Take a shot" (`#remember`, `memory.js`). Twelve cards, six pairs of the small things the page talks about (spare keys, locker 4471, Marta's book, shoe size 31, Wi-Fi password, parked on B2). A match makes Doddy say where the thing is; finishing swaps him to the fist-bump pose. Cards are buttons with spoken labels ("Card 3, face down" / "Card 3: Spare keys, matched"), so it works with a keyboard and VoiceOver; Doddy's bubble is a polite live region. Nothing is stored. Hidden without JavaScript. Icons are inline line drawings in `memory.js`.

## Builds on Vercel

`vercel.json` has an `ignoreCommand`: a push builds this project only when something under `site/` changed since the last deployment (or, without one, in the last commit). It builds whenever it can't tell. `gateway/` and `server/voice-token/` have the same rule. **Daily cap:** the Vercel team is on the free plan, which allows 100 deployments a day. On 13 October Vercel began refusing new ones (API error `api-deployments-free-per-day`, "try again in 24 hours"), and from about 22:47 UTC no push to any branch produced a build, so the first push of the What can Doddy do? work to the default branch made no deployment. Every push can create up to three deployments (this site, the gateway, the voice-token server), including ones the ignore step then cancels. Promoting an existing preview (`request_promote`) was refused too (422). If production doesn't update after a push, look for this error in the dashboard before suspecting the code. Before this, every push to any branch built all three projects and used up the free plan's 100 deployments a day.

## Needs the owner

1. **Check the deep link on an iPhone.** The app now registers `doddy://` (`project.yml`) and opens `home`, `memories` or `settings` (`DeepLink` in DoddyCore, handled in `RootView`). Not yet built or tried on a device. Universal Links (needs a domain and an `apple-app-site-association` file) would remove the "isn't installed" guesswork later.
2. **Waitlist:** add a contact address people can use to ask for deletion; the form promises deletion on request.
3. **Domain, contact address and privacy policy.** Pages now name `https://www.doddy.lol/` as their canonical host (`canonical`, `og:url`, `og:image`); the RSS feed keeps `https://doddy-eight.vercel.app` so item links and guids don't change under subscribers. Hosted on Vercel (project `doddy`, team `doddyyyy`) at https://www.doddy.lol, with `doddy.lol` redirecting to it. The old `doddy-eight.vercel.app` belonged to the previous team and answers 402; nothing should point at it. Production deploys from the repo default branch (`claude/loving-dirac-uuxoux`); every other branch gets a preview that sits behind Vercel login. No contact address or privacy policy yet.
4. **Fonts:** Bricolage Grotesque and Caveat (both OFL) load from Google Fonts, which sends visitors' IP addresses to Google. For an EU audience, self-host them after licence review; the CSS falls back to system fonts without them.
5. **Character art, two places left:** the homepage and the new page use the pack. The basketball game (`court.js`, a canvas that draws `assets/poses/*.svg` and places the ball by those drawings' hand position) and the blog banners (`tools/build_blog.py` `pose()`) still use the v1.3 SVGs. The game needs the pack's basketball shooting frames cut and imported (not yet), or a pack pose with only the ball animated; the banners need a pose choice per post. Then `assets/poses/` can go.
6. **Voice testing line:** done on the owner's word (13 October): the page says "Voice is in testing." and nothing about real-iPhone testing.
7. **Brand approval:** colours, character drawings and wordmark are candidates (`docs/design/CANONICAL_DESIGN_DIRECTION.md`), not an approved brand.

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
- Google Analytics (2026-10-10, same setup, test ID `G-TEST123`, Google's script stubbed): first visit shows the banner and requests nothing from Google; Allow loads `gtag/js` once, pushes consent/js/config to `dataLayer` and stores the choice; No thanks loads nothing; returning visitors (allowed or declined) are not asked again; Analytics choices reopens the banner with focus on Allow, and switching to No thanks clears `_ga` cookies; banner on blog index and post; none on `/admin/`; 390 and 1440 px no horizontal scroll; no console errors or CSP violations. With the real empty ID: no banner, no footer sentence, no request. Not checked: real GA collection and the GA dashboard.

- Film (2026-10-09, headless Chromium 1194 via Playwright, local server sending the `vercel.json` headers): at 1440, 390 and 320 px no horizontal scroll, no console errors, no CSP violations; JS takes over (muted, no controls, play button and chapters shown); tapping play turns on sound and controls and stops the loop; chapter buttons respond; reduced motion leaves the film paused with the poster; with JavaScript off the native controls show and the play button and chapters are hidden. At 1440×900 the film starts 93 px below the first screen. Screenshots: `VISUAL_REVIEW/landing/v3-film-1440.png`, `v3-film-390.png`. Not checked: actual playback, seeking and sound (Playwright's Chromium has no H.264 decoder), iPhone Safari inline autoplay, Low Power Mode.

- Remember it (2026-10-09, headless Chromium 1194 via Playwright, `vercel.json` headers): full game at 1440, 390 and 320 px; a mismatch flips back, a pair played by keyboard (focus + Enter) matches, the win message and fist-bump pose show, New game resets; no horizontal scroll, console errors or CSP violations; hidden with JavaScript off. Screenshots: `VISUAL_REVIEW/landing/v3-remember-1440.png`, `v3-remember-390.png`. Not checked: VoiceOver, real touch.

Not checked: real Safari on iPhone (deep-link fallback timing, Dynamic Type zoom, touch throwing), VoiceOver, Lighthouse.

## What can Doddy do?

`/what-can-doddy-do/`, second in the nav (ADR-468 to 471; design and rationale in `design/website-what-can-doddy-do/`). Ten scripted moments from one day, 08:45 to 23:30, each in the owner's approved words (`design/website-what-can-doddy-do/COPY.md`) and each labelled Built, In testing or Later, maybe. Only saved notes is Built; Lost in translation is a labelled concept.

- **Files:** `tools/build_day.py` writes `what-can-doddy-do/index.html` and `day-scenes.css`; `day.css` and `day.js` are by hand; `nav.js` is the phone menu. Every position is a class in `day-scenes.css` because the production CSP has no inline-style allowance (the page has no `style=` attributes and no `<style>`). The only inline scripts are the two the CSP already hashes (the `js` class and the Vercel queue).
- **Moments:** each is a paper card on the page: Doddy and a prop in a pack scene, what you say (ink bubble), what Doddy says (handwriting), and the card the app would show. The finished card is the default. With motion allowed on a desktop-width screen, a card plays three beats once when 40% is in view (the problem, about 0.6 s; the ask and Doddy's line, word by word; the card and its stamp; at rest by 2.1 s); a Replay chip repeats it. On a phone the card is the page and a "Play the scene" chip plays it. Under `prefers-reduced-motion`, or without JavaScript, the page is the finished cards and nothing else.
- **Hero:** seven objects are links to their moments; hover, focus or a first tap makes Doddy swap pose and say one line (a second tap opens the moment). The pill and Doddy follow the visitor's own clock (browser time; nothing is sent or stored) and the button starts at the nearest moment.
- **Between moments:** walk, run and stop-to-look strips from the pack's frames; one surprise per visit, seeded by the date (no storage), only after two moments have been passed, never within 2 s of another move.
- **Share:** "Send this one to someone who…" uses the Web Share API, or copies the link and says "Copied". The sign-off suggests the moment that held the visitor longest (08:45 if none), measured in memory only.
- **Choices** under the 10:20 and 13:00 cards change the draft and the search text (JavaScript only; hidden without it).
- **Waitlist:** the same endpoint, payload, consent wording and honeypot as the homepage (`/api/waitlist`). It does not ask the optional three questions; the signup is stored without answers. The join pose waves on success.
- **Head:** title "What can Doddy do? · Doddy", description = the lede, canonical `https://www.doddy.lol/what-can-doddy-do/`, share image `assets/day/og-day.png` (1200×630, the page's own 08:45 art).
- **Not built (from the design):** Doddy running out of the hero ring on selection (the page just scrolls), the scroll-triggered preloading of the next moment's frames, the "Play the scene" two-frame storyboard that the mockups showed above the card on phones (the chip replays inside the card instead), analytics events.
- **Weight:** about 2.7 MB of WebP in `assets/day/` for the whole set, lazy-loaded below the first screen; a visitor downloads the scenes they scroll to.

### Checked (2026-10-13, headless Chromium 1194 via Playwright, local server sending the `vercel.json` headers incl. the CSP and the `/assets/` cache header; Vercel's insights script stubbed, `/api/waitlist` mocked)

- Homepage, `/what-can-doddy-do/` and `/blog/` at 1440, 1024, 390 and 320 px: no horizontal scroll, no console errors, no CSP violations, no failed requests (the film's mp4 and cancelled swaps of already-cached animation frames excluded), no broken images, Bricolage Grotesque and Caveat loaded. All inline scripts match the CSP hashes; the new page has no `style=` attributes.
- New page, desktop: the clock pill and the nearest-moment button; hover on an object swaps Doddy's pose and line, leaving restores; the hero arrival ends on the rest pose with its classes cleared; the 08:45 card plays its beats and ends as the finished card; the day strip follows the page; the Replay chip appears after a scene played; the draft chips change the card text; "Send this one" copies the link (desktop Chromium has no share sheet); the sign-off names a moment; the waitlist refuses a bad email and posts the homepage payload.
- New page, phone (390 px, touch): the menu opens and Escape closes it; the first tap on an object reacts without leaving, the card is the finished page with a "Play the scene" chip, and the chip plays it and then offers Replay.
- Reduced motion: nothing primed, no chips, no hero arrival, finished cards. No JavaScript: finished cards, seven object links, ten day-strip links, choices hidden.
- Homepage: six-link nav, the phone menu lists the new page, three moments in the teaser, the voice sentence replaced, canonical on `www.doddy.lol`. Blog: six-link nav with Blog current. `npm test` in `site/`: 18 pass. `python3 -I tools/build_day.py --check` and `tools/build_blog.py --check`: pass.
- Not checked: real Safari on iPhone (the Web Share sheet, touch, Low Power Mode), VoiceOver reading order of a scene, Dynamic Type, Lighthouse, the real Vercel deploy and `www.doddy.lol` serving the new files, the share image in a real link preview.

### Homepage and page B made to agree (ADR-480, 2026-10-14)

From the audit in `design/website-what-can-doddy-do/PROMPT_how-it-works-vs-the-day.md` and mockup 26. `site/index.html`, `styles.css`, `tools/build_day.py` (page B) and `COPY.md`:

- The receipt section is gone; its "nothing matches" line moved to step 2 and the corrected-note receipt to step 3. "Your words, not a guess" now appears once on the homepage (step 2); the 18:45 scene left the teaser (it stays on page B).
- New `#real` strip, "What's real today", with the exact three lines page B's truth panel uses. The homepage's separate "Later, maybe" paragraph is deleted, and page B's panel links to `/#real`. Removing `.later` from the CSS also fixes a leak: the bare `.later` rule was styling every `.cap.later` pill (a 40 px top margin).
- "How it works" no longer says "all on your iPhone. No account, no setup"; it says the notes stay on the phone with no account.
- Teaser heading and lede say the three scenes are in testing; the third scene is 10:20 (page B's own train-platform art) instead of 18:45.
- Voice section: "Say any of it out loud", scope matches the scenes, and the confirm-on-screen rule for calendar, reminders and alarms (quick list edits are undone instead), which `voice-agent/instructions.md` supports.
- Privacy note names weather and Wikipedia lookups (a place name or search words).
- Page B's 18:45 caption now says searching notes in the app works today and asking out loud is in testing.

Checked (headless Chromium 1194, `python3 -m http.server`, no production headers or CSP run this time): homepage at 1440, 390 and 320 px: no horizontal scroll, no page errors, no broken images, no `.receipt-section` or `div.later` left. `npm test` in `site/`: 18 pass; `build_day.py --check` and `build_blog.py --check`: pass. Not checked: the CSP headers, real Safari, VoiceOver, the live deploy.

**Open, needs the owner or an app check:** (1) page B's captions say weather and Wikipedia are "asked for by ElevenLabs' servers", but OpenAI Realtime is now the default voice and `voice-agent/README.md` says those web tools may run in the app or on the token server, so the caption may be stale; (2) the old homepage line listed alarms and Polish under "In testing"; the shared strip follows page B's wording and omits both, so say if they should come back; (3) the translation branch (`claude/inspiring-rubin-1agiui`) rewrites `index.html`, so it will conflict with this change.

### Screens removed (ADR-481, 2026-10-14)

The hero's iPhone frame and the three phone screens in How it works are replaced by example cards (real text, no images), and `assets/screens/` is deleted, along with the unused `.device`, `.hero-chip` and `.step-receipt` CSS. The step 3 receipt moved into step 3's card. Checked in headless Chromium 1194 (`python3 -m http.server`, analytics banner declined, no CSP headers): homepage at 1440, 390 and 320 px has no horizontal scroll, page errors or broken images; the phone hero no longer lets Doddy cover the card's text. Not checked: real Safari, VoiceOver, the live deploy. The translation branch `claude/inspiring-rubin-1agiui` rewrites `index.html`, so it will conflict with this change too.

### Say it once (ADR-482, 2026-10-14)

Design: `design/website-homepage-vision/g-sort-thursday.html` (round 3, chosen by the owner). Built into `index.html` and `styles.css`; `main.js` now skips the voice-section code when there is no voice section; `tools/build_day.py` no longer links page B's truth panel to a homepage strip. The games, film, privacy panel, nav, menu, analytics and the whole waitlist flow are unchanged in behaviour. Ink icons for the apps are inline SVG symbols in the sprite (no new hosts, no inline styles).

Checked (headless Chromium 1194, a local server sending the `vercel.json` headers including the CSP; Vercel's insights script stubbed; `/api/waitlist` mocked with `{ok:true,id,key}`): homepage at 1440, 390 and 320 px: no horizontal scroll (the big-asks row scrolls sideways on phones by design), no console errors, no CSP violations, no broken images, no `style=` attributes, every anchor the nav and footer use exists; the hero's arrival class is set; the memory game builds its 12 cards; the waitlist posts and shows "You're on the list" and the optional questions. `npm test` in `site/`: 18 pass; `build_day.py --check` and `build_blog.py --check`: pass. Not checked: real Safari on iPhone, VoiceOver, the film's playback, the live deploy.

**Claims past today's tools, for the owner's eye:** the phone line (ADR-152/172, needs Twilio and the messaging server); the translator offering to answer on its own; Drive and Notion combined in one reply; routines by name. The footer and the truth line frame the page as where Doddy is heading. The translation branch `claude/inspiring-rubin-1agiui` rewrites `index.html` and will conflict.

### Checked (2026-10-14, hero and moment-card cleanup, headless Chromium 1194 via Playwright, site/ served with the vercel.json headers)

- Hero: "Quite a lot, actually." is one line at 320, 390, 1024 and 1440 px, and fits its column. Each of the seven tiles shows its own time and short title without hovering. Tiles don't touch each other, the reaction line, Doddy or the copy at any of the four widths, including while each tile is hovered. Doddy's reaction line sits in one fixed place under the ring. The coffee cup's stray speck is removed from the pack image and the site's WebP.
- Moment cards (all ten) at 320, 390, 1024 and 1440 px: no card has a stamp, bubble, note or panel covering text. Stamps sit on the card's top edge. At 1100 px and below the cards stack like the phone layout. No sideways scroll, console errors, failed requests or broken images on the page at any width.
- Known small remaining item: at 1440 px the 10:20 card's "You say" bubble rises a few pixels into the card's padding. It overlaps nothing and clips nothing.
- Regression: check.mjs (82 checks: CSP, nav, phone menu, interactions, reduced motion, no-JS, homepage and blog) passes. `npm test` in site/: 18 pass. `build_day.py --check` and `build_blog.py --check`: pass. `verify_imported_pack.py`: pass.
- Not checked: real Safari on iPhone, VoiceOver, Dynamic Type, Low Power Mode, and the live deploy (the daily Vercel cap is still blocking builds).

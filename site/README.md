# Doddy landing page

A static, single-page site that explains Doddy (the character) and the Doddy app, built from `prompts/LANDING_PAGE_DESIGN.md`. Nothing is deployed.

## Preview

```sh
cd site && python3 -m http.server 8765
# open http://localhost:8765
```

There's no build step: plain HTML, CSS and a small vanilla script. No analytics, no cookies, no storage.

## How it connects to the app

| Link | Where |
|---|---|
| Colours | `tokens.css` (light, dark, and an explicit `data-theme` override; poses follow it too) is generated from `Packages/DoddyCore/Sources/DoddyDesignTokens/CandidateTokens.swift`. Run `python3 -I tools/gen_site_tokens.py` after changing app tokens; `--check` fails if the site is out of date. |
| Character | `assets/poses/` are copies of the poses in `design/interface-v1.2/assets/` (light and dark; dark swaps in with the system appearance). |
| Copy | Headings and disclosures reuse the app's words (`HomeView`, `VoiceView`, `SettingsView`, `RecallCopy.noMatch`). |
| Waitlist | Sign-ups go to the Google Sheet **Doddy waitlist** (tab "Signups": time, email, page, consent version) through the Apps Script in `tools/waitlist/Code.gs`. `WAITLIST_URL` in `main.js` holds the script's web app URL; empty means the form says the waitlist isn't open and sends nothing. See "Turn on the waitlist" below. |
| Open Doddy | `APP_URL` in `main.js` (`doddy://home`); the app handles `doddy://home`, `memories` and `settings`. On non-iPhone devices it explains that Doddy runs on iPhone; on iPhone, if the page is still visible after 1.5 s, it says the app isn't installed. |
| App Store | Commented-out Smart App Banner in `index.html`; enable when there's an App Store ID. |

## What's real on the page

- **Design v2 (editorial notebook):** headings in Bricolage Grotesque (OFL, Google Fonts), Caveat only for Doddy's own voice and the wordmark, system text for reading. Sections: hero, the problem, three-step How it works, the note receipt, voice (In testing), privacy panel, Meet Doddy, join. The example note in the receipt card is labelled as an example.
- **Screens are design previews**, copied from `design/interface-v1.2/previews/` and labelled "Design preview". Replace them with simulator screenshots of the native app (same file names in `assets/screens/`) once someone with Xcode captures them.
- The voice section has no app screenshot. It shows the app's real status words and its "Save this note?" card as an illustration, labelled as such, and is marked **In testing** because voice hasn't run on a real iPhone.
- Claims follow the feature table in the prompt: save, search, edit, export and delete are described as working; reminders and other languages sit under "Later, maybe" with no dates.

## Turn on the waitlist

1. Open the **Doddy waitlist** sheet in Google Drive → **Extensions → Apps Script**.
2. Replace the editor's contents with `tools/waitlist/Code.gs` and save.
3. **Deploy → New deployment → Web app.** Execute as: *Me*. Who has access: *Anyone*. Authorise when asked.
4. Copy the web app URL (`https://script.google.com/macros/s/…/exec`) into `WAITLIST_URL` in `main.js`.

The script stores only time, email, page and consent version; duplicates return "already on the list"; a hidden honeypot field drops most bots; cells are forced to plain text so nobody can inject formulas. Tested against a fake sheet (`Code.gs` logic) and a mocked endpoint (form messages); not yet run inside Google.

## Needs the owner

1. **Check the deep link on an iPhone.** The app now registers `doddy://` (`project.yml`) and opens `home`, `memories` or `settings` (`DeepLink` in DoddyCore, handled in `RootView`). Not yet built or tried on a device. Universal Links (needs a domain and an `apple-app-site-association` file) would remove the "isn't installed" guesswork later.
2. **Waitlist:** deploy the script (below) and add a contact address people can use to ask for deletion; the form promises deletion on request.
3. **Domain, hosting, contact address and privacy policy.** The footer has none yet.
4. **Fonts:** Bricolage Grotesque and Caveat (both OFL) load from Google Fonts, which sends visitors' IP addresses to Google. For an EU audience, self-host them after licence review; the CSS falls back to system fonts without them.
5. **Brand approval:** colours, character drawings and wordmark are candidates (`docs/design/CANONICAL_DESIGN_DIRECTION.md`), not an approved brand.

## Checked (2026-10-09, design v2, headless Chromium 1194 via Playwright, local server)

- 1440, 390 and 320 px widths, light and dark: no horizontal scroll, no console errors. Screenshots in `VISUAL_REVIEW/landing/`.
- Under the production CSP from `vercel.json`: scripts, fonts and poses load, no violations.
- Explicit `data-theme` light/dark overrides the OS setting for colours and poses.
- Waitlist against a mocked Apps Script endpoint: added, already on the list, invalid email, server busy; body is text/plain JSON with email, page, consent version and the empty honeypot.
- `tools/waitlist/Code.gs` against a fake sheet: validation, dedupe, honeypot, formula stripping, malformed JSON.

Not checked: real Safari on iPhone (deep-link fallback timing, Dynamic Type zoom), VoiceOver, Lighthouse, and the Apps Script running inside Google.

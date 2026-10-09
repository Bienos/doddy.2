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
4. **Fonts:** the handwritten face (Caveat, OFL) loads from Google Fonts, which sends visitors' IP addresses to Google. For an EU audience, self-host it after licence review; the CSS falls back to system handwriting fonts without it.
5. **Brand approval:** colours, character drawings and wordmark are candidates (`docs/design/CANONICAL_DESIGN_DIRECTION.md`), not an approved brand.

## Checked (2026-10-09, headless Chromium 1194 via Playwright, local server)

- 1440, 390 and 320 px widths: no horizontal scroll; light and dark; reduced motion (static poses, underlines already drawn).
- No console or page errors.
- Waitlist: empty and invalid email show an error and mark the field; no endpoint shows "isn't open yet"; a mocked endpoint gets `{"email":"name@example.com"}` and shows success; a 500 shows the retry message.
- Open Doddy on desktop shows the iPhone message and doesn't navigate. Tab order: skip link, header, hero actions, basketball button, email field, submit, Open Doddy.
- Screenshots: `VISUAL_REVIEW/landing/`.

Not checked: real Safari on iPhone (deep-link fallback timing, Dynamic Type zoom), VoiceOver, a screen-reader pass, and Lighthouse.

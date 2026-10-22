# Legal pages: owner checklist (2026-10-22)

> **Draft pages, not legal advice.** The Terms and the Privacy Policy on the site were written from this repository's code on 2026-10-22 for the owner and a lawyer to review. They are not approved, carry a visible draft banner and `noindex`, and are not in `sitemap.xml`.

| Page | File | URL |
|---|---|---|
| Terms and Conditions (EN) | `site/terms/index.html` | https://www.doddy.lol/terms/ |
| Privacy Policy (EN) | `site/privacy/index.html` | https://www.doddy.lol/privacy/ (voice and AI: `#voice-and-ai`) |
| Regulamin (PL) | `site/pl/terms/index.html` | https://www.doddy.lol/pl/terms/ |
| Polityka prywatności (PL) | `site/pl/privacy/index.html` | https://www.doddy.lol/pl/privacy/ (`#voice-and-ai`) |

Both documents are **version `2026-10-22`**, the same strings as `LegalDocuments` in `Packages/DoddyCore/Sources/DoddyCore/LegalAcceptance.swift`. How to change a version: `site/README.md`, "Legal pages".

Every gap is a visible `<span class="ph" data-ph="ID">` on the page: `[OWNER: …]` in English, `[WŁAŚCICIEL: …]` in Polish. The same ID is used in both languages. To list them: `grep -o 'data-ph="[A-Z0-9]*"' site/terms/index.html site/privacy/index.html site/pl/*/index.html | sort | uniq -c`. When a gap is filled, replace the whole `<span class="ph" …>…</span>` with plain text in **both** languages.

"Where" below uses the section anchors (`#who` = section "Who we are" / "Kim jesteśmy"). T = Terms, P = Privacy Policy; every item appears in the same place on the EN and PL page.

## 1. Placeholders

### Business identity
- [ ] **ID1** Legal name of the business (controller). T `#who`, `#ip`; P `#who`, `#contact`. The repository only shows "Bienos" as the GitHub organisation and bundle ID prefix, which is not shown to be a legal entity.
- [ ] **ID2** Postal address. T `#who`; P `#who`, `#contact`.
- [ ] **ID3** Company register and number, tax ID (NIP), if any. T `#who`.

### Contacts
- [ ] **C1** Support email address. T `#who`, `#law`, `#contact`. (Also the "deletion on request" address the waitlist form promises; `site/README.md` "Needs the owner" 2.)
- [ ] **C2** Privacy contact email address. P `#who`, `#deleting`, `#rights`, `#contact`.
- [ ] **C3** Data protection officer, or "not appointed". P `#who`.
- [ ] **C4** EU or UK representative, or "not needed" (depends on where the controller is established). P `#who`.
- [ ] **C5** Lead supervisory authority. P `#rights`. If the controller is established in Poland this would normally be the President of the Personal Data Protection Office (UODO); the repo shows the owner in Warsaw but not where the business is established, so the page doesn't say it.

### Version and publication
- [ ] **V1** Effective date. All four pages, header. Set on publication; do not change the version string unless the text changes.
- [ ] **V2** Where earlier versions of the Terms are kept (an archive URL or "on request"). T `#changes`.
- [ ] **V3** Which language version prevails if EN and PL differ. T `#other`.
- [ ] Remove the draft banner (`.legal-draft`) and `<meta name="robots" content="noindex">` from all four pages, then decide on `sitemap.xml` (`site/README.md`, "Legal pages").

### Age
- [ ] **A1** Minimum age. T `#eligibility`; P `#children`. The app has no age gate, no children's mode and no parental controls (searched `DoddyApp` and `Packages`). Decide together with the App Store age rating (AI chat, user content, contacts).

### Governing law, liability, notice
- [ ] **L1** Governing law. T `#law`.
- [ ] **L2** Courts with jurisdiction. T `#law`.
- [ ] **L3** Out-of-court dispute resolution body, if any. T `#law`. (The EU ODR platform no longer exists, so it is not mentioned.)
- [ ] **L4** The limitation-of-liability paragraph for consumers in Poland and the EU. T `#liability`.
- [ ] **L5** Notice period before a feature or the service is stopped. T `#availability`.

### Paid services
- [ ] **P1** Whether paid plans are planned. T `#paid`. Today: no subscriptions, in-app purchases or charges in the code; web search and Claude cost the owner per use and have daily caps.

### Retention
- [ ] **R1** ElevenLabs retention for recordings and transcripts at release. P `#voice-kept`, `#retention`. **Today the live agent keeps recordings with no time limit** (STATUS.md, read 20 Oct; ADR-057 accepted that for the owner's own phone only). The page says so.
- [ ] **R2** OpenAI retention for Realtime voice. P `#voice-kept`, `#retention`. The app itself says it "isn't verified in this build" (`DataFlow`).
- [ ] **R3** How a user asks for ElevenLabs/OpenAI recordings and transcripts to be deleted. P `#voice-kept`, `#deleting`. No app function deletes them.
- [ ] **R4** Waitlist retention. P `#website`, `#retention`. No period in the code; deletion on request through `/admin/`.
- [ ] **R5** Server log retention at Vercel (site, voice sign-in) and Render. P `#website`, `#retention`.
- [ ] **R6** Retention of account and connection records on Doddy's server (`backend/`), and how a user deletes them. P `#retention`. There is no account-delete route in `backend/src/http.ts`; the page says "write to us" (C2) instead.

### Processors, agreements, providers
- [ ] **D1** Which data processing agreements exist, and each company's role (processor, sub-processor, independent controller). P `#processors`. The page lists: ElevenLabs, Google (Gemini via ElevenLabs), OpenAI, Anthropic, Composio, Monid / Search1API / LiteScrape, Open-Meteo, Wikipedia, Apple, ECB, Vercel, Upstash, Render, Supabase, Google Analytics / Fonts. Twilio and GNews are mentioned only under the messaging server, which no shipped build reaches.
- [ ] **D2** Which model the live ElevenLabs agent uses at release. P `#voice-provider`. `voice-agent/session.json` says `gemini-3.5-flash` (values "as read on 2026-10-09"); the unmerged `claude/ecstatic-allen-ptjm3u` says the live agent runs Eleven Realtime Max. The page names Gemini from the file on main and flags it.
- [ ] **D3** Each provider's training and retention terms (ElevenLabs, Google, OpenAI, Anthropic). P `#ai-training`. The page says *we* don't train on user data (no training code exists in the repo); it makes no claim for the providers.

### International transfers
- [ ] **T1** Where each service processes data and the transfer safeguard (adequacy, EU-US Data Privacy Framework, SCCs). P `#transfers`. Known from the repo: `render.yaml` puts `doddy`, `doddy-messaging` and its worker in Frankfurt; the waitlist Blob store is `fra1`. Not known: Supabase project region, Vercel Functions region, Upstash, and every AI provider.

### Legal bases (all in P `#legal-bases`, marked "proposed")
- [ ] **B1** Review the whole table.
- [ ] **B2** Analytics cookies: Google Analytics runs on every page with no consent step (`site/analytics.js`, owner's choice of 15 Oct). P `#website` and `#legal-bases`. For EU visitors this very likely needs prior consent (ePrivacy rules); decide with the lawyer.
- [ ] **B3** Special-category data users put in notes or say aloud (health etc.): explicit consent as proposed?
- [ ] **B4** Other people's voices in translator mode (and people near the phone): basis and how they are told.

## 2. Open questions that are not a single placeholder
- [ ] **App Store:** privacy label answers (draft in `PRIVACY_POLICY_DRAFT.md` Appendix C, now out of date for camera, photos, motion, Claude and device sign-in), privacy policy URL and support URL in App Store Connect, account deletion rule 5.1.1(v): the app has Delete Doddy voice account and Delete my Doddy messaging data, but nothing for the device account on Doddy's server (R6).
- [ ] **Google Fonts** load before any choice and send the visitor's IP to Google (P `#website`). Self-hosting would remove that sentence.
- [ ] **Polish review:** the Polish pages need a native speaker and the lawyer (`l10n/REVIEW_NOTES.md`). App labels that are still English in the Polish app are quoted in English on the PL pages ("What leaves this iPhone", "Delete Doddy voice account", "Sign out of voice", "Ask again before sharing voice").
- [ ] **Re-acceptance flow:** both pages say a material change will be shown in the app for re-acceptance. That depends on the app's `LegalAcceptance` work (being added in parallel; not checked here).
- [ ] **"Doddy asks first" claims** (T `#asks`, P summary) rest on `AskFirst.swift`, the guard script and `backend/src/tools/askFirst.ts`; none has been seen on a device.
- [ ] **Site footer sentence** (all pages, unchanged): "voice, phone calls, shared lists and connected accounts send data off it only when you switch them on." Public look-ups now run without asking (ADR-575); consider adding them.
- [ ] **Ask Doddy gateway:** the page says it "isn't set up yet" (Vercel `doddy-gateway` had no environment variables on 19 Oct, STATUS.md). Update if it is deployed.
- [ ] **Messaging server:** described as "not switched on yet" (`ServerConfig.defaultBaseURL` is empty). Before it is switched on, add its retention (sent-message metadata is not pruned, call notes have no expiry; old draft 5.5 to 5.9) and Twilio/GNews to the processor table.

## 3. Where the old draft (`PRIVACY_POLICY_DRAFT.md`, 2026-10-11) was wrong, and what the code says now
1. **Permissions.** Draft §6 and §3: "no camera, no photo library, no motion". Now the app asks for Camera, Photo Library (read) and Motion & Fitness (`project.yml` `INFOPLIST_KEY_NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSMotionUsageDescription`; ADR-567 to 569). Photos taken in Doddy stay on the iPhone and aren't saved to the library; only photo counts and times and step numbers go to the voice.
2. **Default voice.** Draft §7 said OpenAI Realtime is the default. ElevenLabs is the default again; OpenAI is a choice (ADR-546, `VoiceProvider.effective`). The app also asks before first sharing voice with each provider (`VoiceProviderConsent`).
3. **Doddy's server and Claude.** Draft §5.10: "sign-in by a token the owner mints; real app sign-in not built". The app now signs itself in with a Keychain device ID (`POST /v1/session/device`, ADR-563); the server stores an HMAC-derived account ID, not the device ID. The built-in address is `https://doddy-yaci.onrender.com` (`Config/Doddy-Info.plist`). New: Claude on the server for `ask_claude` / `make_document`, documents kept 7 days (ADR-564, `backend/src/store.ts`).
4. **Backend retention.** Draft: "no retention policy, never pruned". The server now prunes hourly: approvals and attempts a day after expiry, receipts after 90 days or beyond 200 per user, usage counters after about 62 days (daily) and 400 days (monthly), documents after 7 days (`backend/src/store.ts` `prune`, `pruneDocuments`; `backend/src/app.ts`). Database: Postgres, currently a Supabase project for testing (ADR-525), not a SQLite file.
5. **Errands.** Not in the draft. Tasks handed to Doddy go to the messaging server and Anthropic (web search and fetch), off unless `ERRANDS_ENABLED` is set; kept encrypted until saved on the iPhone, unfetched results deleted after 30 days (ADR-570, `DataFlow` row `errands`).
6. **Asking first.** Draft §7: "small list edits by voice are shown with Undo". Now every list change needs a tap on a card (`AskFirst.need`: `addToList`, `checkOff`, `removeFromList` are `.tapFirst`, ASK-01/ADR-483), and public look-ups (weather, Wikipedia, web, news, places, sums, conversions) run without asking (ADR-575, `AskFirst.publicLookups`). Web search is on by default (ADR-563).
7. **Web, news and place search providers.** Draft named Monid only. `backend/src/tools/websearch.ts`: web and news through Monid's Search1API endpoints, places through LiteScrape's Google local results.
8. **Language.** Polish is the default for screens and voice (ADR-573). The draft's "Polish version: owner decision" is now answered by these pages; Polish is still unreviewed.
9. **Watch and Mac.** Draft §1 covered the Apple Watch app. Watch and Mac are paused and out of the shipping build (ADR-572), so the pages cover iPhone (and iPad) only.
10. **Hey Doddy / Picovoice.** Removed (ADR-549); not mentioned. The SDK list in the draft's App Store checklist ("ElevenLabs, LiveKit, Porcupine") is now ElevenLabs and LiveKit (`project.yml` packages).
11. **Website address.** Draft §1: `https://doddy-eight.vercel.app`. The site is https://www.doddy.lol.
12. **Voice account deletion label.** The Settings button is "Delete Doddy voice account" (its confirmation button says "Delete voice account"); it revokes all Doddy voice sessions and asks the user to also remove Doddy in Apple ID settings (`SettingsView.swift`, `VoiceAccountSettings`). "Delete my Doddy messaging data" is under Settings › Notifications and texts.
13. **AI transparency.** Draft §7 said "OpenAI Realtime by default, or ElevenLabs"; reversed (item 2). The draft's Siri default question is answered: on by default (`SiriNoteLookup`, `@AppStorage … = true`).
14. **Private notes and Memory on calls.** Confirmed excluded on main (`MemoryCopySync.swift` filters `PrivateNotesStore.current()` before every upload), although PR #94 with a similar change is still listed as unmerged in STATUS.md.

# Review — `site/` (landing page, blog, waitlist, 2026-10-11)

Read-only review. No code changed.

**Scope:**
- Code, in full: `api/*.js`, `vercel.json`, `package.json`, `analytics.js`, `main.js`.
- Searched rather than read in full: `admin/admin.js`, `memory.js`, `court.js`.
- Pages: `index.html` and `blog/meet-doddy-ai-agent/index.html`, checked as visible text for claims.
- `README.md`, from its outline and "Needs the owner" section.

**Not opened:** images, video and fonts (blocked by `.claude/settings.json`).

**Checked against:** the app and decisions (`DECISIONS.md` ADR-254 and ADR-265) for whether the page's claims are still true.

## Tests run

| Command | Result |
|---|---|
| A script hashing each inline `<script>` in the four pages, compared with the CSP `script-src` hashes in `vercel.json` | match: two hashes on the home page, one on each blog page, none on admin |
| A search for `style=""` attributes and `on…=""` handlers in the four pages, which the CSP would block | none |

**There are no automated tests for `site/`, so none were run.**

**Not run:**
- A deploy.
- The waitlist against a real Vercel Blob store.
- A browser check of the page.

## What is solid

- **Waitlist storage:**
  - Signups are private Vercel Blob objects named by a hash of the email, so each email is stored once.
  - There is no IP or user agent, and nothing goes to the logs.
  - There is a honeypot field.
  - Same-origin POSTs only.
  - There is a size cap.
  - Formula characters are stripped on the way in and escaped again in the CSV.
- **Optional answers:** they need a one-time key that only the signing-up browser holds. Only a hash of the key is stored, and it is compared in constant time.
- **Admin:** Basic auth is compared in constant time and is locked when the password isn't set. Responses carry `no-store` and `noindex`, and the page uses `textContent`, not `innerHTML`, for records.
- **Content Security Policy:**
  - Strict, with `frame-ancestors 'none'`, `base-uri 'none'` and `form-action 'none'`.
  - Inline scripts are hash-pinned, and the hashes match.
- **Google Analytics:** loads only after the visitor taps Allow. Turning it off removes the `_ga` cookies.

## Findings (most severe first)

### Medium

1. **`index.html`: "Your notes stay on your iPhone" is no longer true for every user**
   - **Where:** the hero, the privacy panel's "Stays on your iPhone", and the footer.
   - **Problem:** Several features the user switches on send notes or note-derived data off the phone:
     - **Memory copy for phone calls:** encrypted, on Doddy's messaging server.
     - **iCloud shared lists:** CloudKit.
     - **Online accounts:** Gmail, Drive, Notion and Todoist, through Doddy's backend and Composio.
     - **The OpenAI test voice.**

     ElevenLabs is the only service the page names.
   - **Failure scenario:** A visitor relies on "stays on your iPhone", turns on memory on calls, and their notes are copied to a server they were never told about. The page makes a privacy claim the product doesn't keep (CLAUDE.md: never claim privacy you can't show).
   - **Fix:** Say "Your notes are stored on your iPhone", plus one sentence listing what leaves the phone when switched on: memory on calls, shared lists in iCloud, connected accounts, and voice. Use the same wording in all three places.

2. **`index.html` (voice section): "Doddy only listens while the voice screen is open" is false when "Hey Doddy" is on**
   - **Problem:** The opt-in "Hey Doddy" wake word (ADR-254) listens in the background, with the island and the microphone dot showing.
   - **Failure scenario:** A user turns on "Hey Doddy" and the microphone is in use while the page said it wouldn't be.
   - **Fix:** "Doddy only listens while the voice screen is open, or, if you turn on Hey Doddy, while the Dynamic Island shows it's listening."

3. **`index.html` (voice section and footer): voice providers are only partly named**
   - **Problem:** "Talking uses ElevenLabs only while a conversation is open", and the footer says the same. The OpenAI Realtime test voice (ADR-265, a switch on Home) sends voice and notes to OpenAI. Phone calls go through Twilio and ElevenLabs.
   - **Failure scenario:** A tester switches on the OpenAI voice, and their audio goes to a provider the site never names.
   - **Fix:** Name every provider that can receive voice, and say which switch turns each on.

4. **`site/vercel.json`, `gateway/vercel.json`, voice-token (dashboard only): every push builds all three Vercel projects**
   - **Problem:** No project has an Ignored Build Step (`ignoreCommand`). A push to any branch, including Swift-only or docs-only changes, starts three deployments. On the free plan (100 a day) the limit was reached on 2026-10-11, so every PR shows three red Vercel checks that say nothing about the code.
   - **Failure scenario:** A real site or gateway change can't get a preview for 24 hours.
   - **Fix:** In each project, skip the build when nothing in its directory changed since the last deployment, and build whenever unsure:
     ```
     "ignoreCommand": "[ -n \"$VERCEL_GIT_PREVIOUS_SHA\" ] && git cat-file -e \"$VERCEL_GIT_PREVIOUS_SHA^{commit}\" 2>/dev/null && git diff --quiet \"$VERCEL_GIT_PREVIOUS_SHA\" HEAD -- ."
     ```
     - `voice-token` has no `vercel.json`, so add one or set it in the dashboard.
     - **Not verified:** whether an ignored build still counts toward the daily limit.

### Low

5. **`index.html`: the page says features aren't built that the app and the blog say are**
   - **Problem:** The page says "Reminders and other apps aren't built yet". Its "Not built yet" list includes reminders and "more languages, starting with Polish". The blog post (`blog/meet-doddy-ai-agent/`) says Doddy already helps with calendar, reminders, timers, maps and message drafts, in English or Polish. The app has those, plus alarms and lists.
   - **Failure scenario:** Two pages on the same site contradict each other. Under-claiming is the safe direction, but it reads as out of date.
   - **Fix:** Match the blog's "in testing" list. Keep the "in early testing" and design-preview labels.

6. **`index.html`: "Voice hasn't been tested on a real iPhone yet." — owner to confirm**
   - **Problem:** The live ElevenLabs agent shows 43 conversations in the last 7 days. I can't tell from here whether they came from an iPhone.
   - **Fix:** The owner says which is true. Never write "tested" unless it was.

7. **`api/waitlist.js` + `main.js`: anyone can check whether an email is on the waitlist**
   - **Problem:** A POST with someone's email returns `status: "already"`, and the page says "You're already on the list".
   - **Failure scenario:** Someone learns that a person they know signed up. This is a small privacy leak.
   - **Fix:**
     - Show the same message for both.
     - For a duplicate, return `added` without a key, so the optional questions are skipped.
     - **What's left:** a script can still notice the missing key. That's acceptable for a waitlist.

8. **`api/waitlist-answers.js`: answers can bring back a deleted signup**
   - **Problem:** It reads the record, then rewrites it with `allowOverwrite: true`.
   - **Failure scenario:** The owner deletes a signup on request while that visitor's tab is still on the questions. Submitting the answers writes the whole record back, email included.
   - **Fix:** Write only if the blob is unchanged since it was read: the `ifMatch` etag option, if this `@vercel/blob` version has it (not checked). Otherwise check again just before the write and refuse when it's gone. The second option still leaves a short window.

9. **`api/*`: no rate limits**
   - **Problem:** Two endpoints have no rate limit:
     - `waitlist`: the honeypot only stops simple bots.
     - The admin Basic auth: no lockout.
   - **Failure scenario:**
     - Scripted signups fill the Blob store and the CSV.
     - The admin password can be guessed online at function speed.
   - **Fix:** A Vercel Firewall rate-limit rule on `/api/` (dashboard). Document that the admin password must be long and random.

10. **`index.html` footer: "No cookies, no cross-site tracking" while Google Fonts loads before consent**
    - **Problem:** Fonts come from `fonts.googleapis.com` / `fonts.gstatic.com` on every visit, which sends the visitor's IP to Google. The README already lists self-hosting as an owner item.
    - **Fix:** Until the fonts are self-hosted (after licence review) or replaced by system fonts, limit the footer to Vercel Analytics: "Vercel Web Analytics sets no cookies."

11. **`site/` has no tests**
    - **Problem:** The waitlist, answers, export and admin functions have no tests. That includes the key check, the CSV escaping, the duplicate race and the auth.
    - **Fix:** `node --test` with a stubbed `@vercel/blob`, covering:
      - a signup is added, then reported as already there;
      - the honeypot;
      - a cross-origin POST is refused;
      - a wrong key is refused;
      - CSV formula escaping;
      - unauthorised admin access.

      Add the run to `scripts/ci.sh`.

### Decisions for the owner (not defects)

- **Character art:** the page uses the v1.3 SVG poses (`site/assets/poses/`). Since 2026-10-11, new work must use only the `DODDY-Numbered-Video-Assets-v01` pack. The page predates that rule. Any change that touches the poses should replace them from the pack.
- **Contact address and privacy policy (README "Needs the owner" 2-3):**
  - The form promises deletion on request, but the page gives no way to ask.
  - The site collects emails and free-text answers from an EU audience without a privacy policy that names who is responsible.
  - Both need the owner's details.

## Top fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | Correct the privacy and voice claims: what leaves the phone, Hey Doddy, every voice provider | 1-3 | S | Low; wording only |
| 2 | Ignored Build Step on all three Vercel projects | 4 | S | Low; unverified against the limit |
| 3 | Bring the "not built yet" lines in line with the blog | 5 | S | Low |
| 4 | Waitlist: same reply for a duplicate; no resurrection on answers | 7, 8 | S | Low |
| 5 | Tests for `api/` | 11 | M | Low |

## Constitution evidence log

- **DOD-11 (privacy):**
  - **Waitlist:** stores email, page, consent version, time and optional answers. It keeps no IP or user agent, logs only error names, and its storage is private (code).
  - **Google Analytics:** gated on consent (code).
  - **Gaps:** findings 1-3 (claims), 7, 9 and 10. There is no privacy policy or contact address.
- **Claims:**
  - **CLAUDE.md:** "never label … unbuilt native app … as implemented". The page under-claims (finding 5) and labels its screens as design previews.
  - **Accuracy:** its privacy claims are now too broad (findings 1-3).
- **Claims to limit:** nothing here was run in a browser or deployed. The CSP and hash checks are static.

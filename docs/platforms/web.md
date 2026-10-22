# Doddy Web (browser)

**State (22 Oct 2026):** built and tested on branch `claude/exciting-carson-08x2pk`, which is also what the Render service `doddy` serves at https://doddy-yaci.onrender.com (its page and asset file names match that branch's build; checked 22 Oct). Not merged to the default branch. Since 22 Oct 21:39 UTC the service runs commit `d03562ae` from `claude/friendly-faraday-8juosh` (the live branch was fast-forwarded to it with the owner's say-so), so it is restyled in the website's design (ADR-594) and has Logbook (ADR-593) with its server routes. Decisions: ADR-585 (sign-in and sessions), ADR-586 (stack and hosting). Why and what's next: `docs/architecture/WEB_AND_SHARED_PLATFORM.md`.

## What it is
A signed-in workspace in the browser for the same account the iPhone uses on Doddy's server (`backend/`). Today it shows:
- **Documents** Doddy made from the phone: decks, Word, Excel, PDF, text. Their status is real, and they can be downloaded. The server keeps them 7 days.
- **Connected apps**, read-only.
- **Activity:** the server's receipts.
- **Signed-in browsers**, each with Sign out.
- A **language** switch: Polish by default, or English.
- **Logbook** (ADR-593, `docs/product/WEB_LOGBOOK.md`): how a person uses Doddy, in two tabs, At a glance (the week as a receipt) and Closer look (7, 30 or 90 days). The server keeps and serves the days the iPhone sends (`backend/src/web/logbook.ts`, `/v1/web/logbook*`, off until the iPhone turns it on), but **the iPhone can't send any yet** (not built), so the page opens on "Logbook is off" and shows made-up example numbers only when asked, marked Example; the menu keeps its Example marker until `IPHONE_SENDS_LOGBOOK` is flipped. `LOGBOOK_ENABLED` in `web/src/logbook/config.ts` hides the page.

It does not have chat, memory, tasks or projects. Home says so instead of showing empty versions of them.

## Design (ADR-594)
Doddy Web follows the website's design (owner, 22 Oct): the cream canvas, a sticky header with the wordmark, the sections in one row and Sign out (a Menu sheet on small screens), paper cards with a soft lift, ink buttons with the orange underline, ruled notebook panels for Home and sign-in, Doddy's handwritten line. Dark mode stays (the website is light-only), using the same palette file's dark values.
- **Colours** come from `CandidateTokens.swift`, the file the website's `tools/gen_site_tokens.py` reads, through `tools/gen_web_assets.py`. Before 22 Oct they came from `UploadedTokens.swift` (orange `#EC803F`); the website's orange is `#FF6A00`.
- **Fonts:** the website uses Bricolage Grotesque and Caveat from Google Fonts. This server's content security policy allows no outside fonts and no font files are bundled (`CLAUDE.md`), so `app.css` names them first and falls back to Avenir Next, Segoe UI, Bradley Hand and Segoe Print. Matching the website exactly is an owner decision (`WEB_LOGBOOK.md`, decision 2).
- **Poses:** Doddy's poses are the app's `WholeDoddy_*` images, copied by `gen_web_assets.py` (`crosslegged`, `belly_reading`, `shush`, `wave`, `kneeling_inspect`).

## How signing in works (ADR-585)
1. On the iPhone: Settings › Doddy on the web › Get a sign-in code. The phone shows eight letters and digits and the web address to type them at.
2. In the browser, at that address: type the code. It works once, for five minutes.
3. The browser gets an HttpOnly, SameSite=Strict cookie for the same server account. It lasts 30 days, or until 14 days unused.

The phone can list and sign out every browser. A browser can sign itself or others out.

## Folders
| Folder | What |
|---|---|
| `web/` | The app: Vite 7, React 19, React Router 7, TypeScript 5.9, zod 3. `src/api` (client + schemas), `src/auth`, `src/i18n`, `src/pages`, `src/styles` |
| `backend/src/web/` | Server side: codes, cookie sessions, CSRF checks, web routes, serving `web/dist` |
| `contracts/web/` | Real server replies, written by `npm run fixtures:web` in `backend/`; read by the web and Swift tests |
| `Packages/DoddyCore/.../WebLinkClient.swift`, `WebSignInModel.swift` | The iPhone's client and screen state (tested on Linux) |
| `DoddyApp/Features/Web/WebSignInView.swift` | The iPhone screen (compiled only by the hosted Mac build) |
| `web/src/logbook/`, `web/src/pages/LogbookPage.tsx` | Logbook: the summary contract (`schema.ts`, zod), the catalog of tools and categories, seeded example days, adding days up and filling gaps, CSV, formats, and the hand-built SVG charts |
| `tools/gen_web_assets.py` | Copies the website's colours (`CandidateTokens.swift`, light and dark), the app's metrics, wordmark, five `WholeDoddy_*` poses and the favicon into `web/`; `--check` runs in CI |

## Run it locally
```sh
cd backend && npm ci && npm run build
DODDY_MODE=mock DODDY_AUTH_MODE=signed DODDY_DEVICE_SIGNUP=first-device \
DODDY_SESSION_SIGNING_KEY=$(node -e 'console.log(require("crypto").randomBytes(32).toString("base64"))') \
DODDY_DB_PATH=:memory: DODDY_WEB_ORIGIN=http://127.0.0.1:5173 node dist/src/server.js
# second terminal
cd web && npm ci && npm run dev        # http://127.0.0.1:5173, /v1 is forwarded to :8787
```
Mock mode uses demo data, and every page shows a "Demo server" banner. To get a code without an iPhone, play the phone with curl:
```sh
TOKEN=$(curl -s -X POST localhost:8787/v1/session/device -H 'content-type: application/json' \
  -d '{"deviceId":"6f1c2c4e-8b1d-4c39-9a7e-2a4b5c6d7e8f"}' | node -pe 'JSON.parse(require("fs").readFileSync(0)).token')
curl -s -X POST localhost:8787/v1/web/link-codes -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' -d '{}'
```

## Test
| Command | What |
|---|---|
| `npm test` in `backend/` | All backend tests; `test/web.test.ts` is the web part (sign-in, isolation, CSRF, expiry, revocation, documents, pages, logs) |
| `npm run typecheck && npm test` in `web/` | Type-check and unit tests (Vitest, jsdom) against the server's fixtures; 76 tests, about 50 of them for Logbook |
| `npm run build` in `backend/` and `web/`, then `npm run e2e` in `web/` | Playwright: the real backend (mock providers, in-memory database) serving the built app, Chromium at desktop and phone width |
| `DODDY_SCREENS=<folder> npx playwright test e2e/screens.spec.ts` in `web/` | Screenshots in light and dark, for a person to look at |
| `scripts/ci.sh --core-only` | All of the above. The end-to-end run is SKIPPED (not PASS) where there's no Playwright Chromium, as in the hosted Linux job |

## Deploy (owner steps; nothing here has been done)
The web app is served by the existing Render service `doddy`, so there's no new host and no new monthly cost.
1. **Build command** of the hand-made Render service `doddy` (Settings › Build & Deploy): `npm ci && npm run build && npm ci --prefix ../web && npm run build --prefix ../web`. The same line is in `render.yaml`. Render runs it in `backend/` (the root directory). That the rest of the repository is checked out next to it is expected, but unverified; if not, set the root directory to the repository and prefix the backend commands with `--prefix backend`.
2. **Environment** of `doddy`:
   - `DODDY_WEB_ORIGIN=https://app.doddy.lol`, once that name points at the service as a Render custom domain (owner decision 8). This is recommended: the phone's signed document links stay on `DODDY_PUBLIC_BASE_URL` (the Render address), a different origin from the web session. `https://doddy-yaci.onrender.com` also works for a first try; then those links share the web app's origin (see the audit's security section).
   - `DODDY_TRUST_PROXY=1`.
   - Optional: `DODDY_WEB_SIGNIN_TRIES_PER_CLIENT` (default 10 per quarter hour; raise it for an office behind one address).
   - Nothing secret is added. `DODDY_SESSION_SIGNING_KEY` and the database are already there.
3. **Deploy** the branch or main (autoDeploy is off). Check:
   - `GET /v1/health` answers;
   - `GET /` shows the sign-in page, not "isn't built";
   - the response headers include `content-security-policy`.
4. **Phone:** a build with this branch (the hosted Mac CI is its first compile), then Settings › Doddy on the web › Get a sign-in code, and sign in from a computer.

**Rollback:** unset `DODDY_WEB_ORIGIN` and redeploy. The web routes and pages disappear (404), and the phone's API is untouched. Browser sessions stay in the `web_sessions` table until pruned. To end them at once:
```sql
UPDATE doddy_backend.web_sessions SET revoked_at = (extract(epoch from now()) * 1000)::bigint WHERE revoked_at IS NULL;
```

## Not verified
- Never deployed, never run against the live server, never opened on a real phone.
- The SwiftUI screen is uncompiled here; the PR's hosted Mac job compiles it.
- Whether Render's proxy appends exactly one `X-Forwarded-For` hop (the per-client sign-in limit depends on it; the server-wide one doesn't).
- The Polish was written by the agent, not a native speaker. The other eight app languages show the new phone strings in English (`l10n/REVIEW_NOTES.md`).
- Screen readers were not tried. The structure (landmarks, one `h1` per page, labels, focus moving to the heading after navigation, a skip link) is tested in the e2e run; contrast follows the app's tokens.

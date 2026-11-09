# Doddy Web (browser)

**State (7 Nov 2026):** on the default branch (`main`) since 23 Oct (the web line's merge, #133); the chat since 28 Oct (ADR-657; ADR-604 on its branch). **Live** on the Render service `doddy` at https://doddy-yaci.onrender.com, recorded in `STATUS.md` as running `360c99f` (4 Nov), deployed 5 Nov 05:49 UTC. Since then #184 (generic app tools), #186 (Google and Apple sign-in, ADR-818), #192 (payments, off) and #195 (two more tool names in Logbook's list, `follow_news` and `control_home`) changed `backend/` and `web/` (all merged 7 Nov), and none is deployed yet (`STATUS.md`). Tested in Chromium against the real backend in mock mode. Signed-in use of the live site and the chat with the real model aren't recorded as tried. Decisions: ADR-600 (sign-in and sessions), ADR-601 (stack and hosting), ADR-602 (Logbook), ADR-603 (kept memory), ADR-594 (the website's design), ADR-657 (the chat). Why and what's next: `docs/architecture/WEB_AND_SHARED_PLATFORM.md`.

History: built on `claude/exciting-carson-08x2pk`; the service ran `d03562ae` from `claude/friendly-faraday-8juosh` from 22 Oct 21:39 UTC (the website's design and Logbook), then `69762f6` (the chat) from 24 Oct 11:08 UTC, then the default branch.

## What it is
A signed-in workspace in the browser for the same account the iPhone uses on Doddy's server (`backend/`). Today it shows:
- **Documents** Doddy made from the phone: decks, Word, Excel, PDF, text. Their status is real, and they can be downloaded. The server keeps them 7 days.
- **Connected apps**, read-only.
- **Activity:** the server's receipts.
- **Signed-in browsers**, each with Sign out.
- A **language** switch: Polish by default, or English.
- **Logbook** (ADR-602, `docs/product/WEB_LOGBOOK.md`): how a person uses Doddy, in two tabs, At a glance (the week as a receipt) and Closer look (7, 30, 90 days or a year; kept 1 year). The server keeps and serves the days the iPhone sends (`backend/src/web/logbook.ts`, `/v1/web/logbook*`). Since 9 Nov the iPhone sends them, **on by default** (decision `2026-11-09-usage-counts-on-by-default`), and `IPHONE_SENDS_LOGBOOK` is true. `LOGBOOK_ENABLED` in `web/src/logbook/config.ts` hides the page.
- **Owner panel** (`/owner`, decision `2026-11-09-usage-counts-on-by-default`): for the accounts in `DODDY_OWNER_ACCOUNTS` only; anyone else gets "not found" and has no menu entry.
  - **What it shows:** totals of every account's Logbook days (accounts, how they sign in, Logbook on or off, conversations, minutes, notes, list items, tasks, every tool with done, no, not sure and didn't work); each account with its email, sign-in method and dates, and that account's own days.
  - **Where the data comes from:** emails and sign-in dates from Supabase's admin API with `SUPABASE_SECRET_KEY`; without it, the panel says so and shows Logbook's counts only.
  - **Code and tests:** `backend/src/web/owner.ts`, `/v1/web/owner*`; `web/src/pages/OwnerPage.tsx`, `web/src/owner/`. Fixtures come from `npm run fixtures:owner` in `backend/`.

- **Memory** (ADR-603, `docs/product/CLOUD_MEMORY.md`): the notes and conversations a person chose to keep on Doddy's server, as text, kept for a year, encrypted with a server-held key; read, searched, downloaded and deleted from the browser, and the chat (below), where Claude (`DODDY_CHAT_MODEL`, default `claude-haiku-5-5`) answers from them and cites its sources. **The iPhone's sending is written and compiles in the hosted Mac job, but hasn't run on a device**, so the page opens on "nothing is kept" and is marked Soon in the menu (`IPHONE_SYNCS_MEMORY` in `web/src/memory/config.ts`). The server needs `DODDY_MEMORY_KEY`, or it says "not set up".

- **Chat** (ADR-657, numbered 604 on its branch; `docs/product/WEB_CHAT.md`): `/chat`, laid out like ChatGPT in Doddy's colours (the list of chats, the conversation, a round message box, suggested questions, sources under each answer, "What I can see"). It replaces Ask Doddy (`/ask` opens it). Claude answers from the kept notes and conversations **and the account**: Logbook's counts added up per period, counts over kept conversations, connected apps, the documents Doddy made and his receipts, all as cited data. So it already answers about apps, documents and activity; notes, conversations and usage counts follow when the iPhone sends them. The list of chats is kept **in this browser only** and deleted at Sign out. Tested with the demo model only. **Live on Render since 24 Oct 11:08 UTC** (first `69762f6`, now `main`'s `360c99f`; signed-in use with the real model not checked yet).

- **Messages** (`docs/implementation/MESSAGES_WEB_SYNC.md`, `web/src/pages/MessagesPage.tsx`): a read-only copy of the iPhone's Messages thread, which the iPhone sends encrypted and without photos to `PUT /v1/web/messages` (table `message_threads`, needs `DODDY_MEMORY_KEY`). The menu says Soon (`IPHONE_SENDS_MESSAGES = false`) until an iPhone build that sends it is installed.

It does not have tasks or projects. Home says so instead of showing empty versions of them.

## Design (ADR-594)
Doddy Web follows the website's design (owner, 22 Oct): the cream canvas, a sticky header with the wordmark, the sections in one row and Sign out (a Menu sheet on small screens), paper cards with a soft lift, ink buttons with the orange underline, ruled notebook panels for Home and sign-in, Doddy's handwritten line. Dark mode stays (the website is light-only), using the same palette file's dark values.
- **Colours** come from `CandidateTokens.swift`, the file the website's `tools/gen_site_tokens.py` reads, through `tools/gen_web_assets.py`. Before 22 Oct they came from `UploadedTokens.swift` (orange `#EC803F`); the website's orange is `#FF6A00`.
- **Fonts:** the website uses Bricolage Grotesque and Caveat from Google Fonts. This server's content security policy allows no outside fonts and no font files are bundled (`CLAUDE.md`), so `app.css` names them first and falls back to Avenir Next, Segoe UI, Bradley Hand and Segoe Print. Matching the website exactly is an owner decision (`WEB_LOGBOOK.md`, decision 2).
- **Poses:** Doddy's poses are the app's `WholeDoddy_*` images, copied by `gen_web_assets.py` (`crosslegged`, `belly_reading`, `shush`, `wave`, `kneeling_inspect`).

## How signing in works (ADR-600)
1. On the iPhone: Settings › Doddy on the web › Get a sign-in code. The phone shows eight letters and digits and the web address to type them at.
2. In the browser, at that address: type the code. It works once, for five minutes.
3. The browser gets an HttpOnly, SameSite=Strict cookie for the same server account. It lasts 30 days, or until 14 days unused.

The phone can list and sign out every browser. A browser can sign itself or others out.

## Google and Apple (ADR-818, branch `claude/web-google-apple-signin`)
The code still works. Next to it, the sign-in page shows "Continue with Google" and "Continue with Apple" once the server has `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. They open a person's own Doddy account only after they have linked Google or Apple to it once:
- **On the iPhone:** Settings › Doddy on the web › Link Google (or Apple). The phone opens the system sign-in sheet with a one-time ticket from the server.
- **In a browser signed in with a code:** Settings › Sign-in methods › Link.

Linking from the iPhone takes effect only when that iPhone confirms it with its own session, so a ticket forwarded to someone else can't link their account to the sender's. A browser can link or unlink only within 15 minutes of signing in with a code. A Google or Apple account that isn't linked to any Doddy account can make a new one (owner, 3 Nov 2026): the sign-in page asks "Make a Doddy account with Google?", and only "Create my Doddy account" makes it (`POST /v1/web/signup`); `DODDY_WEB_SIGNUP=off` stops that. A web-made account starts empty, works with the web workspace and the chat, and is deleted in Settings › Delete account (an iPhone's account is still deleted on the iPhone). The iPhone app can sign in to it too: Settings › Doddy on the web › Your account from the web › Sign in with Google (ADR-819). One that is linked to another Doddy account is refused, and nothing is merged. Both sides list and unlink. The server runs the sign-in itself (OAuth with PKCE through Supabase Auth, `backend/src/web/social.ts`), so the browser never holds a Supabase token. The owner's setup steps (Google and Apple in Supabase, the redirect address, Render's two variables) are in `docs/integrations/DEPLOY_RENDER.md`, "Google and Apple on the web". **Not tried against the real Supabase, Google or Apple, and the iPhone part hasn't been compiled yet** (the hosted Mac job is its first build).


## Doddy accounts on the server (decision `2026-11-08-required-account`)
Every user is getting a Doddy account: a Supabase user made with Apple, Google or a code sent by email. The iPhone talks to Supabase itself; this server only checks the token (ADR-526, `DODDY_AUTH_MODE=supabase`).
- **Email counts now.** The token check accepts `apple`, `google` and `email`. It refuses any session whose `amr` names a password (`madeWithPassword`, `src/auth.ts`), even if password sign-in were left on in the project.
- **Linking an iPhone's earlier data:** `POST /v1/account/link-device`. The account goes in the Authorization header, and `{ "deviceToken": "<the iPhone's ds1 token>" }` in the body, as proof.
  - It writes one row of `account_links`, mapping the account to the device's user id. From then on the account works on that data, and the device token is refused, so `POST /v1/session/device` for that iPhone answers 409 `account_conflict`.
  - A repeat answers the same way, so the iPhone can safely try again after a lost answer.
  - Accounts are never merged, so the route refuses with 409 `account_conflict` when the account already has data of its own, when it already took over another iPhone's data, or when another account took over this iPhone's data.
  - Limit: 10 tries per account per hour. Without a Supabase project the route answers 503 `live_not_configured`.
  - Code: `src/accountLinks.ts`, `Store.linkAccount`.
- **Deleting the account** (`DELETE /v1/account` with the account's token):
  - erases the linked data;
  - queues the Supabase user for removal (`supabase_auth` cleanup; it needs `SUPABASE_SECRET_KEY`, as for ADR-818);
  - ends that account's earlier tokens at once, through its cut-off second.
- **Tests:** `backend/test/account-links.test.ts` builds the real app from its config (supabase mode, device sign-in on, a local ES256 key in place of the project's). `auth-supabase.test.ts` covers email and passwords.
- **To turn it on, live:** `DODDY_AUTH_MODE=supabase` and `SUPABASE_URL` on Render `doddy`. Keep `DODDY_SESSION_SIGNING_KEY` while phones move over: old device tokens and the link proof need it. Render runs `DODDY_ENV=development`, where that is allowed.

## Folders
| Folder | What |
|---|---|
| `web/` | The app: Vite 7, React 19, React Router 7, TypeScript 5.9, zod 3. `src/api` (client + schemas), `src/auth`, `src/components`, `src/i18n`, `src/pages`, `src/styles` |
| `backend/src/web/` | Server side: codes, cookie sessions, CSRF checks, web routes, serving `web/dist` |
| `contracts/web/` | Real server replies, written by `npm run fixtures:web` in `backend/`; read by the web and Swift tests |
| `Packages/DoddyCore/.../WebLinkClient.swift`, `WebSignInModel.swift` | The iPhone's client and screen state (tested on Linux) |
| `DoddyApp/Features/Web/WebSignInView.swift` | The iPhone screen (compiled only by the hosted Mac build) |
| `web/src/logbook/`, `web/src/pages/LogbookPage.tsx` | Logbook: the summary contract (`schema.ts`, zod), the catalog of tools and categories, seeded example days, adding days up and filling gaps, CSV, formats, and the hand-built SVG charts |
| `web/src/memory/`, `web/src/pages/MemoryPage.tsx` | Memory: the schemas of what the server answers (chat's too), the flags, the page |
| `web/src/pages/ChatPage.tsx`, `web/src/chat/`, `src/styles/chat.css` | The chat (ADR-657): the page, the list of chats kept in this browser (`threads.ts`), the answer's light formatting (`RichText.tsx`), the suggested questions |
| `backend/src/web/chatContext.ts`, `logbookDigest.ts` | What the chat reads about the account, and Logbook's days added up for it |
| `backend/src/memory/` | Kept notes and conversations: the cipher, the contract, search, the service, chat and its routes |
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
| `npm run typecheck && npm test` in `web/` | Type-check and unit tests (Vitest, jsdom) against the server's fixtures; 149 tests (9 Nov 2026, with the owner panel; the type-check passes too) |
| `npm run build` in `backend/` and `web/`, then `npm run e2e` in `web/` | Playwright: the real backend (mock providers, in-memory database) serving the built app, Chromium at desktop and phone width |
| `DODDY_SCREENS=<folder> npx playwright test e2e/screens.spec.ts` in `web/` | Screenshots in light and dark, for a person to look at |
| `scripts/ci.sh --core-only`, or `--only backend,node` | All of the above (the web steps are in the `node` group). The end-to-end run is SKIPPED (not PASS) where there's no Playwright Chromium (`PLAYWRIGHT_BROWSERS_PATH`), as in the hosted Linux `node` job |

## Deploy
The web app is served by the existing Render service `doddy`, so there's no new host and no new monthly cost. **This has been done** (live since 22 Oct, see State); the steps below are for a rebuild or a new service. Whether `DODDY_WEB_ORIGIN` is `https://app.doddy.lol` or the Render address isn't recorded here.
1. **Build command** of the hand-made Render service `doddy` (Settings › Build & Deploy): `npm ci && npm run build && npm ci --prefix ../web && npm run build --prefix ../web`. The same line is in `render.yaml`. Render runs it in `backend/` (the root directory). That the rest of the repository is checked out next to it is expected, but unverified; if not, set the root directory to the repository and prefix the backend commands with `--prefix backend`.
2. **Environment** of `doddy`:
   - `DODDY_WEB_ORIGIN=https://app.doddy.lol`, once that name points at the service as a Render custom domain (owner decision 8). This is recommended: the phone's signed document links stay on `DODDY_PUBLIC_BASE_URL` (the Render address), a different origin from the web session. `https://doddy-yaci.onrender.com` also works for a first try; then those links share the web app's origin (see the audit's security section).
   - `DODDY_TRUST_PROXY=1`.
   - Optional: `DODDY_WEB_SIGNIN_TRIES_PER_CLIENT` (default 10 per quarter hour; raise it for an office behind one address).
   - Signing in with a code and the pages add nothing secret (Google and Apple sign-in need `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, above). `DODDY_SESSION_SIGNING_KEY` and the database are already there.
   - Memory and Messages need one secret, `DODDY_MEMORY_KEY` (base64 of 32 random bytes); without it they say "not set up". It isn't in `render.yaml` or `secrets/manifest.json` (the 7 Nov audit asks for it).
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
- Signed-in use of the live site, and the chat with the real model, aren't recorded as tried. Never opened on a real phone.
- The iPhone's sign-in screen compiles in the hosted Mac job; it hasn't been run on a device.
- Whether Render's proxy appends exactly one `X-Forwarded-For` hop (the per-client sign-in limit depends on it; the server-wide one doesn't).
- The Polish was written by the agent, not a native speaker. The other eight app languages show the new phone strings in English (`l10n/REVIEW_NOTES.md`).
- Screen readers were not tried. The structure (landmarks, one `h1` per page, labels, focus moving to the heading after navigation, a skip link) is tested in the e2e run; contrast follows the app's tokens.

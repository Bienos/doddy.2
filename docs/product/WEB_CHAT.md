# Chat with Doddy on the web (ADR-604)

Owner, 24 Oct 2026 (translated from Polish): "Make an imitation of ChatGPT in the Doddy portal on the website, where the analytics are… access to a chat where you can talk with Doddy's memory about all this context, so he knows about you and is connected to the same things as you are in the app… and you can ask him analytical things, connected to your account's analytics… how much, how he talks… Make it look like ChatGPT, but in Doddy's colours."

## What it is

`/chat` in Doddy Web (the portal the Render service `doddy` serves). It replaces the Ask Doddy page (`/ask` now opens `/chat`) and is second in the menu.

- **Looks like ChatGPT, in Doddy's colours:** the list of chats on the left (New chat, Today / Yesterday / Previous 7 days…, delete one or all), the conversation in a centred column, the person's messages as quiet bubbles on the right, Doddy's answers beside his face (the app icon), and a round message box at the bottom with an ink send button and the orange underline. A new chat opens with Doddy waving, "What can I help with?", the box in the middle and suggested questions under it. On a phone the list is a drawer. Light and dark. Colours come only from the website's tokens.
- **Answers show their sources** ("Sources (2) · Logbook · Connected apps"); a note or conversation opens in place, an account part links to its page (`/logbook`, `/apps`, `/documents`, `/activity`, `/memory`). Copy, Answer again, Stop, Try again.
- **"What I can see"** (where ChatGPT has its model picker): each part the chat can read and its state in words, from `GET /v1/web/chat/context`.
- **Light formatting:** paragraphs, `- ` and `1. ` lists, `**bold**`. Built as React elements, never HTML (tested with markup and links in an answer).

## What Doddy reads for each message (`backend/src/web/chatContext.ts`)

The same account the iPhone uses on Doddy's server, read fresh for each message, for the caller's own user id only. Each part goes to Claude as JSON **data** under its own id, and the answer can cite only those ids.

| Part | What | When it has something |
|---|---|---|
| Notes `n1…`, conversations `c1…` | The best-matching kept notes (6) and conversation excerpts (3), as before (ADR-603) | Only when the iPhone keeps them on the server. The iPhone can't send them yet (`IPHONE_SYNCS_MEMORY`). |
| `logbook` | Logbook's days added up (`logbookDigest.ts`): last 7 days, last 30 days, everything kept, and the last 14 days with a summary: conversations, minutes, average length, lengths, endings, languages, ways in, busiest local hours, weekdays, the 15 most used tools with how each run ended, notes saved, lists, errands, translator. Counts only. | Only when the iPhone has Logbook on and has sent days. It can't send any yet (`IPHONE_SENDS_LOGBOOK`). |
| `talk` | Counts over kept conversations from their plain columns (how many, turns, minutes, averages, first, last, last 7 and 30 days). Nothing is decrypted. | Only when conversations are kept. |
| `apps` | Each online account: name, status, connected since, how many of Doddy's tools are on | Always (from the server's own records). |
| `documents` | The 15 newest documents Doddy made: name, kind, status, when | Always; documents are kept 7 days. |
| `activity` | Doddy's 20 newest receipts: what, when, which account, outcome, the server's own short summary | Always. |

Also sent: today's date and weekday in the browser's time zone (`timeZone`, validated as an IANA name), the page's language and up to ten earlier turns of the thread.

**So today, on the live server, the chat answers about connected apps, documents and activity.** Notes, conversations and usage counts ("how much did we talk", "how do you talk with me") answer "that part is off" until the iPhone sends them; the page says so in "What I can see" and only suggests questions it can answer.

## Rules the code enforces

- **Data, not instructions:** everything above is in the user message as JSON, labelled as data; the instructions (`CHAT_SYSTEM`) hold none of it (tested with planted strings).
- **No invented facts or numbers:** the answer schema lists only this request's ids; an answer citing anything else is discarded as `malformed_provider_result` (tested). The instructions tell the model to use the exact counts, say which period, and say which part is off instead of guessing.
- **Only answers:** no tools. It never claims to have saved, sent, connected or changed anything.
- **Caller's own data only:** every read is keyed by the session's user id (tested with a second person's apps, documents, receipts and Logbook days).
- **Cost:** the same daily caps as Ask Doddy (50 per person, 500 for the server), taken before anything is read. A server without a chat model answers `ready: false` and the page offers no box.
- **Logs:** counts and tokens only, plus whether the account was read (tested: no document name, receipt summary, Logbook number or question). When Claude says no, the log line also carries `providerStatus`, `providerError` (Anthropic's own error type, e.g. `authentication_error`) and `providerHint` from a fixed list (`credit_balance`, `api_key`, `model`, `output_config`, `schema`, `max_tokens`, `workspace`). Anthropic's message text is never kept, since an invalid-request message can quote what was sent. The same fields are on Ask Doddy, `ask_claude` and document failures. The person still sees only the plain error.

## The list of chats is kept in this browser only (`web/src/chat/threads.ts`)

ChatGPT keeps chats on its servers. Here they are kept **only in the browser's localStorage**, never on Doddy's server:
- tied to the browser sign-in (the session id): another sign-in's chats are deleted, never shown; Sign out and an ended session delete them;
- up to 40 chats of 80 turns; when storage is full the oldest go; when storage is blocked the page says chats last until the page is closed;
- "Delete all chats" (with a confirmation) and a delete button per chat.

What this means: the questions, answers and the cited note texts sit in this browser's storage until signed out. Anyone using the same browser profile while signed in could read them, as they could read the pages. Keeping chats on the server (so they follow the person to another browser) is a decision for the owner (below).

## Data that is new to Anthropic

Before ADR-604 the web chat sent Claude only the best-matching notes and excerpts. Now each message also sends the account parts above: **document names, receipt summaries, account names and statuses, and Logbook's counts**. No email, event or file content: the server doesn't keep any. The privacy policy draft (5.13) is updated; it still needs legal review, and Anthropic's terms are still marked [CONFIRM].

## Decisions for the owner

1. **Where chats are kept.** Now: this browser only (recommended for a first version: no new server data). Alternative: on Doddy's server, encrypted like kept conversations, so they follow you; needs a retention and a delete.
2. **Send all parts every time, or only the ones a question needs.** Now: all, compact (a few KB). Choosing per question would send less but needs either keyword rules (fragile in Polish) or a second model call.
3. **Polish wording** is the agent's draft, like the rest of Doddy Web.

## Not done or not verified

- **Deployed 24 Oct 2026, 11:08 UTC** (owner's yes): Render service `doddy`, deploy `dep-dbe92nhsrm7s73bbpsu0`, commit `69762f6` (the live branch `claude/exciting-carson-08x2pk` was fast-forwarded to it; between the old live commit and this one only comments changed besides the chat). Checked: `/v1/health` 200 in live mode, the page's script file is the one tested here, `GET /v1/web/chat/context` answers 401 without a session (the route exists). **Not checked:** a signed-in chat on the live server, and whether it has an Anthropic key (without one, the page says the chat isn't switched on). Rollback: redeploy the previous deploy (`dep-dbdjmpeq1p3s738rsof0`, commit `1b83bea`) from the Render dashboard.
- Never run against the real Claude model: the tests use the demo model. Answer quality (Polish, counts, "how do you talk with me") is unchecked.
- No streaming: the answer arrives whole and unrolls (a CSS reveal; reduced motion shows it at once).
- Screen readers not tried. Structure is tested: one `h1`, focus on it after navigation, labelled box and buttons, a live list of turns.

## Tests

- `backend/test/chat.test.ts` (13): the account part, isolation, the digest, the time zone, citations, logs, the context route. `backend/test/memory.test.ts`: the earlier chat tests, updated (nothing kept now still answers; ten earlier turns; a bad time zone is refused).
- `web/test/chatPage.test.tsx` (25): the page, sources, formatting as text, history of ten, errors, Stop, Answer again, the list of chats and its storage, sign-out, Polish.
- `web/e2e/workspace.spec.ts`: the real server and Chromium, desktop and phone width, nothing kept and Logbook days in: "What I can see", a suggested usage question, the source link, the list after a reload, no sideways scroll.

## Constitution evidence log

| Rule | Enforcing code | Tests | Gaps | Claims to limit |
|---|---|---|---|---|
| Model output is a proposal, typed code validates | `readAnswer` + per-request alias enum (`chat.ts`) | citation of an unknown part discarded | none known | — |
| Tool, document and account content is data | JSON blocks in the user message, none in `CHAT_SYSTEM` | planted strings never in the instructions | — | — |
| Never invent memory or numbers | counts computed in code (`logbookDigest.ts`, `memoryConversationStats`); instructions forbid guessing | digest totals; part states "off" | the model's wording is unverified with the real model | don't say the chat "knows everything about you" |
| Never claim saved without a verified storage operation | chats saved only in localStorage, and the page says so; "not kept" shown when storage fails | storage full and blocked | — | "saved in this browser", never "saved" |
| No external writes from the chat | no tools | — | — | — |
| Content-free logs | `memory_chat` log line: counts, tokens, `account: true` | planted document name, receipt and question | — | — |
| Cross-user isolation | every read keyed by the session's user id | another person's apps, documents, receipts, Logbook | concurrency not exercised (PGlite) | — |

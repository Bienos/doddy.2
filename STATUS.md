# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-18 (PR #85, BLIK transfers, with the fixes that let hosted CI build the app again).

## Known-good build
- **Main branch:** `claude/loving-dirac-uuxoux`.
- **Last build seen working on a device:** head `ce02763` (PR #60, the learning loop).
- **Hosted CI:** since `c8aff7ae` (#69 with #70), every target compiles on Xcode 26.6 and the unit and 26 UI tests pass on the simulator. That build has not been run on a device.
- **Since then on main:** OpenAI Realtime is the default voice, with a model picker on Home (ADR-442), and the first-use screens landed (#76: ADR-324 to 327, ADR-443).
- **Also on main (PR #80, 14 Oct):** the iPhone app and the landing page in ten languages, as machine-translated drafts (ADR-458 to 460). The landing page is live at https://www.doddy.lol in all ten. CI built the app and passed the unit and UI tests with these changes; the language picker and the translated screens have not been seen on a device, and no native speaker has read any of it (`l10n/REVIEW_NOTES.md`).
- **Hosted CI on 18 Oct:** jobs start again after the owner fixed the account's GitHub billing. The first Mac build since 14 Oct showed that no branch had compiled since 754e5d6 (`VoiceAccessGate.swift` used `VoiceProvider` without `import DoddyCore`), and that two app unit tests had never run: the profile intro test from 754e5d6 and the translator test that ASK-01 made stale. PR #85 fixes all three. Its run 39138962699 built the app and passed the 29 UI tests, with only those two tests failing.
- **Also on main (PR #85, 18 Oct):** BLIK transfers by voice (ADR-510). "Send Ania 50 zł" shows a card to send in the bank app; Doddy never sends money. The `draft_blik_transfer` tool is behind an off-by-default switch and has been on the live ElevenLabs agent since 18 Oct (live `agtvrsn_2801m57etpkkfhfbjvqt95nptfha`). Compiled in hosted CI; not yet seen on a device. Details: `docs/implementation/BLIK_TRANSFER_STATUS.md`.
- **Evidence:**
  - The live voice agent worked from this code on 2026-10-11 at 22:35 Warsaw time: a 139 s conversation that used `search_memories`, `save_memory` and `web_search`.
  - The variables the app sent to ElevenLabs match this branch, and not the unmerged `-all` branch.
- **To get back to a build that works,** build this branch: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`.
- **Voice agent:** ElevenLabs agent `agent_0501m4et27vyeawrwqfdxxfszfa6`, live version `agtvrsn_5201m4p132brf30th15nggeqarf0`. It was unchanged between the last working call and this update. Its spec is `voice-agent/`.

## Platforms
Each platform has its own project spec, so one platform's code can't break another's build. See `docs/platforms/README.md`.

| Platform | Code | Spec → project, scheme | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/` | `project.yml` → `Doddy`; `project-iphone.yml` (no Watch app) → `Doddy` | Built and used by the owner on device. The voice agent was seen working on 2026-10-11. | `docs/platforms/iphone.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project.yml` → `DoddyWatch` (embedded in the iPhone app) | Compiles in hosted CI since #69; never run | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` → `DoddyMac` | Prototype on PR #61; never compiled | `docs/platforms/mac.md` |
| Shared core | `Packages/DoddyCore/` | Swift package, used by every platform | Tests run on Linux, 934 passing | `docs/platforms/README.md` |

## Not merged yet: what each branch would change
Merge one at a time, then rebuild and talk to Doddy before the next.

| Branch / PR | What it changes | Risk to voice |
|---|---|---|
| `claude/trusting-sagan-7lky84` | ASK-01: every tool asks first (server gate, app ask cards, agent spec); Gmail, Google Calendar, Outlook, Todoist, Notion, Drive and Monid tools behind cards (ADR-483 to 489). App code not built; live agent not synced. Runbook: `docs/integrations/LIVE_GMAIL_TEST_RUNBOOK.md` | High: every tool call now waits for an answer; needs the live agent synced too |
| `claude/admiring-curie-bsuwv9-all` (PR #67) | Quick start, the first-use fixes, Home's first visit and the shorter intro merged on 13 Oct (#76). Still open: "Hey Doddy" with one tap, the guided first conversation, Quick start shortcuts and "Ask me about it" (#53, #56, #57, #58). | High for what's left: the wake word and the first conversation |
| `claude/trusting-dirac-o8ajzc` | Voice screen shows Doddy with a sound wave; the transcript is one tap away; the wave follows loudness | Medium: adds audio level meters to the live session |
| `claude/affectionate-mayer-aovol9` | Island compact view draws a pre-cut round face | Low |
| `claude/dismiss-ended-card` | Nothing: its changes were reverted | None |
| PR #44 `claude/peaceful-hopper-v3gx75` | Action status, session recovery, Stop listening, unfinished notes, "Listen until I finish" | High: changes the voice session |
| PR #61 `claude/fervent-hamilton-cv19sj` | iPad sidebar and fixes, Watch "New note" and Smart Stack, Mac menu bar app, widget and window, per-platform projects | Low for voice: no voice-agent changes |
| `claude/payments-apple-pay-blik` (ADR-490) | Paying by voice: Buy card with Apple Pay or BLIK (Stripe **test mode** only), the shop's own checkout in Safari's view, Settings › Connections › Payments (off by default), `/v1/purchases` on the backend, `prepare_purchase` in the agent spec. Also fixes a compile error on main (a removed `.translator` card still listed in `changesSomething`). `docs/implementation/PAYMENTS_STATUS.md` | Medium: a new tool and card in the voice session; the live ElevenLabs agent needs `prepare_purchase` synced before it can call it |

## Known problems
- **Voice sessions sometimes start twice.** ElevenLabs logs from 2026-10-09 to 10-11 show:
  - two sessions starting in the same second;
  - a "ghost" session that connects but never sends its start data and stays silent for 30 s;
  - a session that can't hear the user.

  Not fixed yet. It needs a device log to confirm the cause.
- **Vercel:** the `doddy` project (team `doddyyyy`) built and published the site from the default branch on 2026-10-14 (www.doddy.lol); the earlier "account blocked" failures did not recur on that build. The daily deployment limit still applies, so `site/vercel.json` builds only when something under `site/` changed. GitHub Actions has run again since 2026-10-12.

## Waiting on the owner
- A native review of the eight new app languages and of all nine landing-page translations, which are live as drafts (`l10n/REVIEW_NOTES.md`).
- "Hey Doddy" cannot work until the keyword file and a Picovoice key are in place (`docs/implementation/HEY_DODDY_STATUS.md`, "What is missing").
- Whether notes sync between the Mac and the iPhone (today they never do).
- The kitchen timer Live Activity.
- A Pencil drawing canvas.
- The Mac minimum macOS version.
- The final icons.

## How agents should read this repo
1. This page, then **only** the page for the platform you are working on, under `docs/platforms/`.
2. That page lists the folders and the status doc for each feature. Open those, not the whole tree.
3. **Don't read `DECISIONS.md` (about 770 lines) whole.** Search it for an ADR number: `grep -n "| 452 |" DECISIONS.md`.
4. Ignore `reference/`, which is historical.
5. Run `scripts/ci.sh --core-only` on Linux. App code needs a Mac with Xcode.

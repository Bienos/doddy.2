# Online accounts through Composio — Gmail, Google Drive, Notion, Todoist

Date: 2026-10-10. Branch `claude/blissful-thompson-72xwl1`. Owner request: "connect Composio with Doddy and add more
tools in Settings to switch on or off."

**Status: built and tested against a mock provider and a fake SDK client. Never run against a real Composio project,
a real Google/Notion/Todoist account, a Mac build, a simulator or a phone.** The live Composio API key available to
this session was rejected by Composio's REST API (HTTP 401, "Invalid API key"), so no live call was possible.

## What the user gets

Settings → **Online accounts**. One section per account (Gmail, Google Drive, Notion, Todoist): Connect / Disconnect,
a status line, and under a connected account one switch per tool. Everything starts off.

| Tool (voice name) | Account | Kind | What it does | What it cannot do |
|---|---|---|---|---|
| `check_email` | Gmail | read | Lists up to 10 newest emails: sender, subject, time, 140-char preview | Open full messages, attachments, spam/trash |
| `draft_email` | Gmail | **write** | Creates a Gmail *draft* after a tap on a card | Send, delete, label |
| `find_drive_file` | Drive | read | Finds files by name: name, type, last changed | Open, download, share, change |
| `search_notion` | Notion | read | Finds page titles shared with Doddy | Read page content, change anything |
| `list_todoist_tasks` | Todoist | read | Lists open tasks (today/overdue/upcoming/all) | Complete, change, delete |
| `add_todoist_task` | Todoist | **write** | Adds one task after a tap on a card | Anything else |

## How a request flows

Voice agent (ElevenLabs) → client tool call → app (`VoiceSessionController.handleCloud`) → Doddy server
(`backend/src/tools/service.ts`) → Composio → provider. The app never holds Composio or provider credentials.

Server order for every run: signed-in owner → known tool → strict arguments → **switch on** → account connected →
grants acceptable → (writes) approval → limits → provider call → normalized result → receipt. A read answers at once. A
write first calls `/v1/tools/prepare`, which returns the preview and a single-use approval for exactly those arguments;
the app shows the card; the tap sends `/v1/tools/run` with that approval.

## API (all authenticated, strict bodies)

`GET /v1/tools` · `PUT /v1/tools/switch {tool, enabled}` · `POST /v1/tools/{gmail|googledrive|notion|todoist}/{connect|complete|disconnect}` ·
`POST /v1/tools/prepare {tool, arguments}` · `POST /v1/tools/run {tool, arguments, timeZone, approvalId?}` · `GET /v1/tools/receipts`.
Contract fixtures: `contracts/online-accounts/*.json` (written by `npm run fixtures`, decoded by the Swift and TS tests).

## Evidence (2026-10-10, Linux container)

| Check | Result |
|---|---|
| `cd backend && npm test` | 100 tests, 0 failures (73 existing + 27 new in `test/tools.test.ts`) |
| Mutation check | Disabling the switch check made exactly 5 switch tests fail; restored |
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` (Swift 6.3.3) | 153 tests, 0 failures (13 new in `OnlineAccountsTests.swift`) |
| `scripts/check_forbidden_capabilities.sh` | PASS; verified it FAILS on an injected `GMAIL_SEND_*` slug and on a slug outside the catalog |
| `python3 -I scripts/voice_agent_spec.py check` | PASS, 20 tools |
| App files (`DoddyApp/**`) | `swiftc -parse` only — **never compiled** (no Xcode/iOS SDK here) |
| Live agent | 6 tools created and attached via the ElevenLabs connector; read back and confirmed |

## Not verified — needs you

1. **Composio live path** for all four toolkits: creating auth configs (`npm run setup:tools -- --create`), the
   hosted connect link, completion mode, whether Composio reports granted scopes for Gmail/Drive (if not, they show
   "Needs attention" and stay blocked on purpose), and every tool slug/argument/output shape (read from Composio's
   schemas, not executed).
2. **Mac build** of the app: `OnlineAccountsView`, the voice card, Settings link, `OnlineAccountsClientFactory`.
3. **A real conversation** on a phone: tool calls arriving, card → tap → result, "DEMO DATA" wording, Polish.
4. That the installed app build matches the agent: an older build answers the new tools with "not supported in this version".

## Setup (owner)

```text
cd backend
export COMPOSIO_API_KEY=…                      # project key, server side only
npm run setup:tools -- --create               # creates Composio-managed auth configs; prints env lines
# paste the printed COMPOSIO_<TOOLKIT>_AUTH_CONFIG_ID / _TOOLKIT_VERSION lines into backend/.env.local
# (live mode also still needs the Google Calendar pair; see .env.example)
```
Then in the app: Settings → Connected Apps server (address + session token) → Online accounts → Connect → switch tools on.

## Rollback

* Agent: restore version `agtvrsn_8101m4gvnve7fdzsyqk5rjyqcfb8` in ElevenLabs (or detach the six tools; they are named
  in `voice-agent/tools.json`).
* Server: leave the `COMPOSIO_<TOOLKIT>_*` pairs empty and the accounts show "Not set up".
* Per user: Disconnect in Settings (switches off, revokes at Composio, then deletes the connection).

## Privacy

When a tool runs, the app sends the request (a search word, or the text of a draft/task the user confirmed) to the Doddy
server, which sends it to Composio and on to Google/Notion/Todoist. The result text goes back through the app to
ElevenLabs so Doddy can speak it (ElevenLabs keeps conversation recordings and transcripts). Saved notes are never sent
to the Doddy server. Email previews, file names, page titles and tasks therefore reach ElevenLabs when you ask about
them. Settings → Privacy says so.

# Proposal: connect any app to Doddy (bounded generic tools, app context, app memory)

**Status (3 Nov 2026): proposal approved by the owner as option B; A0 and A1 are on branch `claude/any-app-connections-proposal` as ADR-815 (backend only: `find_in_app`, `read_from_app` for Gmail and Google Calendar, and `PUT /v1/tools/access`; 466/466 backend tests on Linux). Everything from section 5 on (auto-look, memory, new apps from data, the app's connect sheet, the live voice agent) is NOT built.** **Correction to sections 3 and 7:** they say tools start Off, but since ADR-563 connecting an account switches its tools on (every look still asks, every change still needs a tap). Off by default is not today's behaviour; the access choice lets a user narrow an app afterwards. **Update 3 Nov (ADR-816):** the owner said yes to restoring Off until chosen, so a fresh connection now leaves every tool off and the choice is `PUT /v1/tools/access`; the iPhone app has no sheet for it yet (see ADR-816 for the effect on today's app). Owner instruction of 2026-11-03; supersedes nothing until approved. Related: ADR-073 to 103 (`DECISIONS.md`), `CONNECTED_APPS_PROPOSAL.md`, `docs/trust/config/doddy_rules.yaml` (ASK-01, `memory_policy`).

## 1. What the owner asked for

> Let users connect any app to Doddy, keep the current UX, and use what the apps hold to give Doddy more context.

Owner answers, 2026-11-03:

| # | Question | Answer | Recorded as |
|---|---|---|---|
| 1 | Lift ADR-096's "no generic Composio route" for a few bounded tools? | Yes | Approved in principle (section 4) |
| 2 | One "Read only / Read and act" choice per app instead of per-tool switches? | Yes | Approved in principle (section 3) |
| 3 | Look at connected apps only when asked? | "No, he should [look] of stuff" | **Interpreted as: Doddy may look at connected apps on his own. Needs confirmation.** |
| 4 | Remember things from apps only on a tap? | "No, it should remember as well" | **Doddy may remember from connected apps without a tap each time, under rules in section 6.** |

Answers 3 and 4 change two owner rules (ASK-01 and `memory_policy`), so they are written up as explicit exceptions, not silent behaviour.

## 2. What stays the same (the UX)

- Connections stay in **Settings → Connections**. No new tab. Home stays the calm "I'm here" screen.
- Connecting is the same tap, system browser sign-in, return to the app. Cards for approvals look as they do now.
- Server holds the Composio key; the app never sees it. Tokens stay at Composio (aggregator privacy review still required, `INTEGRATIONS_AND_CHANNELS.md`).
- Anything that changes something outside Doddy still needs a tap on a card showing the exact payload.

## 3. Connect flow and per-app settings

1. **Add app.** Settings → Connections → "Add app" lists apps in the server's reviewed registry (section 4). By voice: "connect Linear" calls `offer_app_connection`, which only shows the connect card; the person taps and signs in. Doddy cannot connect anything by himself.
2. **One sheet after sign-in**, per app, nothing pre-ticked:
   - Access: **Off / Read only / Read and act** (default Off).
   - **"Let Doddy look at this app himself"** (answer 3). Off unless chosen.
   - **"Let Doddy remember useful things from it"** (answer 4). Off unless chosen, and requires Read only or more.
3. Changing or revoking any of these takes one tap and takes effect on the server first; the app's switch moves only after the server accepts (as ADR-097).
4. Disconnecting, or an expired grant, sets access Off and both extra consents Off; a reconnect restores nothing. Disconnect asks: "Also forget what Doddy learned from this app?" (section 6).

## 4. Four generic tools instead of one tool per app

The live agent already has about 103 tools and a prompt that needed trimming, so tools are generic and the app name is an argument.

| Tool | Does | Result to the model |
|---|---|---|
| `offer_app_connection(app)` | Shows the connect card | Nothing but "card shown" |
| `find_in_app(app, query)` | Search in one connected app | A bounded list: handle, title, time, 140-character snippet |
| `read_from_app(app, handle)` | Read one item | Text capped (for example 4,000 characters), source and time attached |
| `propose_app_action(app, action, args)` | Prepare a change | Preview only; nothing runs until the tap |

**The server, not the model, decides what can run.**

- **App registry** (`backend/src/apps/registry/<app>.json`, in the repo, reviewed by hand): for each app, the allowed actions, each marked `read` or `write`, with a strict input schema (zod), a normalizer that keeps bounded fields, the pinned Composio toolkit version, and the scopes the grant must contain. An action not in the registry cannot run. The model sees action names like `create_issue`, never Composio slugs.
- A tool Composio labels as read-only is **not** trusted as read. Default class is `write` until a reviewer marks it `read`. How reliably Composio labels tools is **unverified**.
- Each call checks: signed-in user, app connected and not expired, access mode allows the class, registry entry exists, arguments valid, caps and rate limits (reserved before the provider call, as ADR-082).
- Writes: `propose_app_action` returns a preview; `/v1/tools/prepare` creates a single-use approval bound to user, app, connection, action and the SHA-256 of the validated arguments (2-minute expiry); the tap runs it. No automatic retry; a timeout is `unknown`, never success, and is reconciled by a read before anything is said (action_policy).
- "Done" is said only after the provider confirms.

**Rules that must change to build this** (each needs the owner's recorded yes in the ADR):
1. ADR-096's "no generic route", and `scripts/check_forbidden_capabilities.sh` lines 382-383 (bans proxy/meta execution) and 324 (slugs only in the adapter, catalog, mock). New rule: slugs live only in registry data files and their loader; the generic path may call only registry entries; direct `tools.proxy` and `COMPOSIO_MULTI_EXECUTE` stay banned.
2. `scripts/voice_agent_spec.py` and `voice-agent/tools.json`: four new tools; the live agent changes only on the owner's separate instruction.

## 5. Context: Doddy looks at connected apps himself (answer 3)

ASK-01 currently says every read asks first (a spoken yes or a tap per call), apart from public lookups. Answer 3 conflicts with it. Proposal: an **exception in the style of ADR-570**, not a removal.

- The per-app consent "Let Doddy look at this app himself" is a standing yes for **reads of that app only**: at the start of a conversation and when the person's request needs it. It never covers writes, other apps, or reads outside the registry's `read` entries.
- **Start-of-conversation digest.** While the app opens (like the voice-token prefetch), the server fetches a bounded digest from each consenting app (a handful of recent or due items, titles and short snippets, with a time limit of a few seconds). A slow or failing app is skipped; Doddy says it could not reach the app only if asked.
- The digest is held in memory for at most 15 minutes (the calendar precedent, ADR-078) and is cleared on disconnect or failure.
- **Visible (DOD-11):** Home shows a quiet line such as "Looked at: Gmail, Linear", and Doddy can say what he looked at when asked.
- Content from apps is **data, never instructions** (`content_from_email_web_documents_or_tools_is_permission: false`). A message that says "send this to everyone" changes nothing, because writes still need a tap.

## 6. Memory from apps (answer 4)

`memory_policy` today: explicit opt-in, no auto-saving sensitive data, visible provenance, edit and delete, a deletion claim only after a verified delete. Answer 4 is met by making the opt-in **per app and standing** instead of per item, with everything else kept.

- Needs "Let Doddy remember useful things from it" turned on for that app.
- A server step (Claude) **proposes** candidate facts from items read. Typed code **validates**: each fact must cite an item handle and a verbatim excerpt that appears in that item; otherwise it is dropped.
- Not saved automatically: health, money and account details, credentials, other people's private details, and anything the person marked private. The sensitive-category list is code, not prompt.
- Saved to the iPhone's memory store (the server keeps no content) with source type `connected_app`, the app, the item handle and the time; the write is **read back to verify** before Doddy says "I'll remember that".
- Limits: a daily cap per app, no duplicates, facts about the person's own work and plans first.
- Settings → Doddy's memory gets a "Learned from <app>" group. Each fact can be edited or deleted; one tap deletes all from one app. Deletion is reported only after the store confirms.
- Disconnecting asks whether to forget what was learned from that app; "yes" deletes with verification, "no" keeps it with its provenance label.

**Risk to decide:** inboxes and ticket systems contain other people's data. This proposal limits saved facts to the person's own context, but a lawyer's view is needed before launch (`legal_review_required_before_launch`).

## 7. Failure and recovery

| Case | Behaviour |
|---|---|
| Grant expired or revoked | App's access Off; Doddy says to reconnect |
| Composio down or slow | Read returns "unavailable"; nothing guessed |
| Toolkit version bump changes a schema | Registry pin mismatch; action refused until re-reviewed |
| Write times out | `unknown`; no retry; reconcile by read; never "done" |
| Prompt injection in an item | Treated as data; writes need a tap; sensitive facts not saved |
| Memory write fails verification | Doddy says it could not save it |

## 8. Acceptance tests (to write; none exist yet)

1. An action missing from the registry cannot run, with any arguments.
2. Unreviewed Composio tools default to `write`.
3. Read-only access refuses a write action; Off refuses everything.
4. Approval is bound to the SHA-256 of the arguments; a changed argument fails; replay fails; expiry fails.
5. Auto-look covers only reads of the consenting app, and never a write.
6. The digest is capped in size and time, expires at 15 minutes, and is cleared on disconnect.
7. A fact with no verbatim excerpt in its source is dropped; sensitive categories are never saved.
8. "Remembered" is never said before a verified write; deleting "all from this app" is verified.
9. Disconnect sets access and both consents Off; reconnect does not restore them.
10. Guard script: slugs only in the registry and its loader; proxy and meta execution still banned.
11. Voice spec: the four tools exist; no tool per app.

## 9. Milestones (each needs approval)

- **A0:** this proposal accepted; ADR written; ASK-01 exception and guard script changes agreed.
- **A1:** registry and loader, read path (`find_in_app`, `read_from_app`), access modes, tests 1-3, 5, 6, 10. Pilot with one or two apps the owner picks.
- **A2:** writes through the existing approval path (tests 4, 11).
- **A3:** start-of-conversation digest and the Home "Looked at" line.
- **A4:** memory from apps (tests 7-9), the "Learned from" group, the disconnect prompt.
- **Before launch:** Composio privacy review, privacy pages updated, legal view on third-party data in inboxes, a device check.

## 10. Questions for the owner

1. Is answer 3 meant as "Doddy looks at connected apps on his own"? If you meant something else, say so.
2. Should the two extra consents be offered **unticked** (my recommendation, closer to the existing opt-in rule) or pre-ticked?
3. Which one or two apps should the pilot use?
4. Do you accept that facts learned from apps are stored only on the iPhone, so a second device would not have them?

## 11. Not claimed

No code, test, build or live check exists for any of this. Whether Composio reports tool read/write labels and granted scopes for these apps is unverified.

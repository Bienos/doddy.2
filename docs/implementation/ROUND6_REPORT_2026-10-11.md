# Round 6 report (2026-10-11, owner: "do all of them, skip the camera one")

Branch `claude/hopeful-fermat-1a63x0`, ADR-330 and ADR-332 to ADR-339 (`DECISIONS.md`, Round 6). The default branch took ADR-331 (hide character art) while this round was being built and is merged in. Camera document scanning was skipped, as asked; ADR-224 stands. **Nothing in this round has been compiled with Xcode.** There is no Xcode in this container, and GitHub Actions still doesn't start jobs.

## What was built

| # | Item | ADR | Where |
|---|---|---|---|
| 1 | Notes and lists in iPhone search (Spotlight), off by default | 330 | `SpotlightIndex.swift`, `Features/Spotlight/SpotlightSync.swift`, the Settings switch |
| 2 | "When am I free?" | 332 | `FreeTime.swift`, `find_free_time`, the controller |
| 3 | Tags in notes (#word) | 333 | `NoteTags.swift`, the tag row and filter in `MemoriesView`, `#tag` search by voice |
| 4 | List templates | 334 | `ListTemplates.swift`, `ListTemplateStore.swift`, "Save as template", "Start from a template", `create_list` `template` |
| 5 | "Remind me when to leave" | 335 | `LeaveBy.swift`, `Infrastructure/Connections/TravelTime.swift`, `Features/LeaveBy/LeaveByScheduler.swift`, the card |
| 6 | Outlook (Microsoft 365 and Outlook.com) | 336 | `backend/src/tools/catalog.ts` and the mock, `CloudToolName`, Online accounts, the guard |
| 7 | iPad | 337 | `project.yml` (device family 1,2), one readable column in `RootView`, Back Tap hidden |
| 8 | Rules for Doddy in the car (CarPlay groundwork) | 338 | `CarProfile.swift` |
| 9 | Quick actions on the app icon | 339 | `QuickActions.swift`, `Features/QuickActions/QuickActions.swift`, the scene delegate |

The live voice agent has the six new tools, the updated `search_memories` and `create_list`, and the round 6 prompt lines. It is version `agtvrsn_9901m4nydc9qegk8npkv8jvprm90` (57 tools). The stored prompt and tool list were read back from the save (`voice-agent/README.md`).

## Tests actually run (Linux, this container)

`scripts/ci.sh --core-only`: **PASS for core-only scope**.
- DoddyCore: **791 tests, 0 failures** (Swift 6.2.1), 21 more than round 5. New this round:
  - `NoteTagsTests`, `ListTemplatesTests`, `FreeTimeTests`, `LeaveByTests`
  - `SpotlightIndexTests` (private notes never indexed, nothing when off)
  - `CarProfileTests` and `QuickActionTests`
  - updated: `OnlineAccountsTests` (Outlook toolkit, five accounts, the draft as a write), `ActivityTextTests`, `DataFlowTests`
- Backend: **188 of 188** (20 new in `outlook-tools.test.ts`, mock provider and fake Composio only).
- App-logic type-check: 19 files, now including `ListTemplateStore.swift`.
- Every changed SwiftUI file parses (`swiftc -parse`).
- Capability guard (now with the Outlook rule, tried with planted cases), voice agent spec (57 tools) and Polish catalog (1193 of 1223 strings) pass.
- **Skipped:** messaging server DB tests (no `TEST_DATABASE_URL`).
- **NOT RUN:** the iOS app, iPad layout, widget, share extension and watch builds.

## Manual checks still needed (device or Mac)

- **Spotlight (ADR-330):** turn it on, find a note and a list from Home Screen search, tap a result; make a note private and check it disappears; turn it off and check everything goes.
- **Free time (ADR-332):** a day with overlapping events, an all-day event, a week; English and Polish replies.
- **Tags (ADR-333):** the tag row and filter; "show my #car notes" by voice.
- **Templates (ADR-334):** save, replace, start a list from one by tap and by voice.
- **Leave-by (ADR-335):**
  - Location "While Using" asked once, approximate location allowed;
  - a real place by car, on foot and by public transport (transit ETAs aren't available everywhere);
  - the notification fires at the time on the card and says traffic may have changed;
  - "too late", "no route" and location off.
- **Outlook (ADR-336):** a real Microsoft 365 account and an Outlook.com account through Composio.
  - Do `OUTLOOK_LIST_MESSAGES`, `OUTLOOK_CREATE_DRAFT` and `OUTLOOK_GET_CALENDAR_VIEW` return the fields the mock assumes?
  - Which scopes does Composio's Outlook auth config actually ask for?
- **iPad (ADR-337):** iPad portrait and landscape, Split View, Slide Over; no Back Tap card or rows; the share extension and widgets on iPad.
- **Quick actions (ADR-339):** each one from a cold start and from the background; "Where I parked" shows only with a saved spot.
- **Car rules (ADR-338):** nothing to try until a CarPlay screen exists; the rules are tested in core only.

## Constitution evidence log

| Rule | Enforced by | Tests | Gap / claim to limit |
|---|---|---|---|
| External writes: an exact payload, explicit approval bound to it | **Outlook draft:** a card with the exact `to`, subject and body; approval is bound to those arguments. Only `OUTLOOK_CREATE_DRAFT` may write, and the guard fails the build for any other Outlook write slug. **Leave-by:** the card shows the place Apple Maps found, the travel time and the leave time; the notification is scheduled only after Set reminder. **Templates:** a template is used through the `create_list` card. | backend `outlook-tools.test.ts`; guard with planted cases; `LeaveByTests`, `ListTemplatesTests` | Outlook not run against a real account. The leave-by card isn't run on a device. |
| "Unknown" is never success and never blindly retried | An Outlook draft answer without an id, or with `isDraft:false`, gives `outcome_unknown`. The leave-by notification is read back from iOS after scheduling; if it isn't there, the reply is "failed". | backend tests; `LeaveByTests` | `UNUserNotificationCenter` read-back is not run on a device. |
| A change is said to happen only when verified | Template save is read back from storage before the screen says saved or replaced. Spotlight is rebuilt from a signature, so the index matches what's stored. | `ListTemplatesTests`, `SpotlightIndexTests` | UserDefaults read-back and Core Spotlight indexing aren't run on a device. |
| Never claim memory saved without storage | Tags are read from the saved text; no tag is stored or invented. Free time and Spotlight save nothing. | `NoteTagsTests` | |
| Tool, web, email and document content is data | Outlook message text is cleaned, cut and framed as information. Calendar titles in free time are data. | backend Outlook tests | The model's behaviour isn't testable here. |
| Driving | `CarProfile.decision` is exhaustive over every voice request: look-ups run; a note or list item needs a spoken "yes" to an exact read-back (owner, 2026-10-11); everything else that changes something, and every online-account write, is refused while driving. | `CarProfileTests` | No CarPlay screen yet; the entitlement request is still with the owner. |
| Privacy | See below. The privacy paragraph (EN/PL) and data-flow rows are updated. | `DataFlowTests`, `SpotlightIndexTests` | |
| No proprietary assets or fonts | None added. Quick actions and the iPad layout use SF Symbols. | | |
| Character | No new Doddy art. | | |

Don't say "implemented", "tested" or "privacy guaranteed" about any of this. It is built and checked on Linux only.

## Privacy, in plain words

- **Spotlight (ADR-330):** off until the user turns it on. When on, note and list text (shortened) goes into iOS's own on-device search index, so it can show in Home Screen search, including on the Lock Screen if the user's iOS settings allow search there. Private notes are never indexed. Turning it off deletes Doddy's whole domain from the index.
- **Leave-by (ADR-335):** for each request, the iPhone's position (once, While Using; approximate is enough) and the destination go to Apple Maps for the place search and travel time. Nothing goes to Doddy's server. The notification text holds the place name and times.
- **Outlook (ADR-336):** like Gmail, through Doddy's server and Composio. **Mock-only so far.** The draft needs `Mail.ReadWrite`, which Microsoft grants as read *and* write over the whole mailbox. Doddy only ever creates drafts, and the guard enforces that in code, but the grant itself is wider than drafts. Anything wider still (e.g. `Mail.Send`) blocks every Outlook tool.
- **Tags, templates, free time, quick actions, iPad, car rules:** nothing leaves the iPhone.

## Security and privacy risks

- **Spotlight on a shared or unlocked iPhone:** anyone who can open search can see note text. That's why it is off by default and the switch says so.
- **Leave-by timing:** the travel time is worked out once, when the card is made. Traffic can change; the card, the reply and the notification say so. It is not a live traffic alert.
- **Outlook scope:** see above. If Composio's Outlook auth config asks for more than the three scopes, the backend refuses all Outlook tools rather than running with them.
- **iPad:** layout is untested; a broken layout is a usability risk, not a data one.

## Decisions needed from the owner

1. **Outlook:** create a Composio Outlook auth config and try it with your own Microsoft account. Until then it is demo data only.
2. **CarPlay:** the entitlement request in `CARPLAY_PLAN.md` still needs sending; the rules (ADR-338) are ready for it.
3. **"Unlock as you go" (ADR-324, branch `claude/lucid-johnson-pmwwg4`):** that session already put two of its lines into the live prompt, and round 6 kept them. Its app code isn't on this line yet. Until it's merged, an app from this line says "switched off, see Settings" while the agent expects a card. Merge it, or tell me to take those two lines out of the live prompt.

## Next recommended step

The first real build on a Mac (Way B in `FIRST_BUILD_GUIDE.md`). Six rounds of SwiftUI haven't been compiled; the round 6 risk list is in that guide.

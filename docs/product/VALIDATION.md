# Beta validation: what we measure (M5)

**Status:** definitions for the 2-week private beta, written 19 Oct 2026 for the sprawa direction (ADR-540). **Proposed; nothing in the "events" table is logged today** except capability gaps, which stay on the iPhone. Phase 5 checks each one against the code and adds what's missing. The owner sets the thresholds before the beta starts (go-live checklist C10).

**What this replaces:** the recall metrics in `docs/quality/VALIDATION_AND_METRICS.md` (first capture, later-day retrieval) and the 17 Oct strategy's North Star, "weekly recalling users". That file stays as history; its privacy rules still apply.

## The beta
- **Who:** 20 adults in Poland with an iPhone, screened with the two questions in `docs/strategy/STRATEGY.md` §4. No more than 20% from the founder's own circle. [ASSUMPTION: carried over]
- **How long:** 2 weeks, private TestFlight. [OWNER]
- **Languages:** Polish and English.
- **Consent:** each tester agrees, before install, to the content-free metrics below and to a short call at the end of week one. The wording goes with the privacy policy (Phase 3).

## The four metrics the owner named

| Metric | Definition | Reported as |
|---|---|---|
| **Day-0 activation** | The tester saves their first sprawa on the same local calendar day as their first app open. | Activated testers ÷ testers who opened the app. Also the median minutes from first open to first sprawa. |
| **Sprawa completed** | The user marks a sprawa Gotowe (from the notification, the card or by voice). A Gotowe undone within 24 h doesn't count; undos are reported separately. | Completed sprawy per tester. Completion rate: sprawy done ÷ sprawy whose reminder time has passed. |
| **Active days in week two** | Distinct local calendar days, from day 8 to day 14 after first open, on which the tester opened the app or acted on a Doddy notification. | Distribution per tester, and the share of testers with 3 or more. |
| **Capability-gap events by category** | The user asked for something no tool covers, and agreed to note it: under ASK-01, `note_capability_gap` shows a card ("Note that Doddy couldn't do this?") and records only after **Note it** (`AskFirst.swift`, ADR-483). A category only, never the words. Gaps the user declines to note aren't counted; Phase 5 decides whether to count the cards shown too. Categories today: `send_message`, `payment`, `music`, `smart_home`, `other_app_control`, `web_action`, `unknown` (`CapabilityGapCategory`, `DoddyCore/Learning/LearningTypes.swift`). | Events and distinct testers per category, per week. |

## North Star: weekly closers
Testers who, in a given week, mark at least one sprawa Gotowe **after Doddy brought it back**, and don't undo it within 24 h. "Brought back" means the sprawa's reminder time had passed and its notification was scheduled at that time. iOS doesn't tell an app when a local notification is shown, so this is worked out from the scheduled time, not observed.

## Events needed (content-free)

| Event | Properties (fixed values only) | Exists today? |
|---|---|---|
| `first_open` | — | No |
| `sprawa_saved` | `input`: voice, text or share · `with_time`: yes or no | No |
| `sprawa_time_set` | `how`: proposed and accepted, chosen from buttons, typed | No |
| `notification_permission` | `result`: granted or refused · `when`: first sprawa or later | No |
| `sprawa_opened_from_notification` | — | No |
| `sprawa_snoozed` | `by`: hour, tomorrow or other | No (the actions exist; nothing records them) |
| `sprawa_done` | `via`: notification, card or voice · `after_bring_back`: yes or no | No. Today Done on a one-off reminder deletes it (`sprawa-loop.md`). |
| `sprawa_done_undone` | — | No |
| `sprawa_deleted` | — | No |
| `capability_gap` | `category` | **Yes, on the iPhone only, after the user taps Note it:** `LearningService.recordGap` writes an outcome event (`DoddyCore/Learning/LearningService.swift`). V1 scope hides the learning loop; Phase 5 checks the event is still written then. |
| `active_day` | — (one per local day at most) | No |
| `ask_card` | `level`: read or change (money once Phase 2 adds it) · `result`: approved, declined or timed out | Partly, on the iPhone only: the learning loop's `OutcomeRecorder` already logs per tool whether it was done, declined or left unanswered. Not shaped or reported as a beta metric. |

**Never in an event:** the sprawa's words, names, times, the time zone, note or memory IDs, search text, audio, transcripts, provider responses, contacts, or the device name. Same rule as `docs/quality/VALIDATION_AND_METRICS.md`. Times are reported as the relative day (day 0, day 1…) only.

**How events reach the owner: undecided.** Two options, for the owner with Phase 3:
- **(a) They stay on the iPhone.** The tester shares a file from Settings at the end of each week. Nothing new leaves the phone, but testers can forget.
- **(b) The app sends them to Doddy's own server** with a random beta ID. Reliable and weekly, but it is personal data under GDPR: the privacy policy names it, with a retention period. The constitution's DOD-11 applies: Settings shows exactly what is sent.

The weekly report script (Phase 5) reads whichever is chosen.

## Proposed thresholds [ASSUMPTION; owner sets them before the beta]
- **Day-0 activation ≥ 80%.** The first screen is the question; less means it doesn't land.
- **≥ 50% of activated testers complete a sprawa after a bring-back** in week one.
- **≥ 40% of testers active on 3 or more days** in week two.
- **Undo after Gotowe ≤ 10%** of completions.

## Guardrails (any breach stops the beta until fixed)
- A "saved" or "done" without a verified store write, or without the provider's confirmation for a provider action.
- An action without the user's approval at its ASK-01 level. Today's code has two levels: a read takes a spoken yes or a tap; a change takes a tap on a card showing the exact payload. Money is a hand-off to the bank app; the owner's tap-plus-Face ID level comes in Phase 2.
- A sprawa shown with words the user didn't say, without a label saying Doddy wrote them.
- A deleted sprawa that comes back.
- Two voice sessions started for one request (Phase 2's session log shows this).

## What we also collect (with consent, not as metrics)
- **The end-of-week-one call (15 minutes):** the last sprawa that slipped, whether the bring-back came at the right moment, what they'd have used instead.
- **Every "Doddy couldn't" and every wrong bring-back** becomes an eval case for Phase 4's skills.

## What this beta can't tell us
- Retention beyond two weeks.
- Willingness to pay (the beta is free).
- Anything about the eight other languages, iPad, Watch or Mac.
- Statistical significance: 20 people show direction, not proof.

## How this beta differs from M5 as written
`docs/implementation/MILESTONES.md` (locked, so unchanged) describes M5 differently from the owner's 19 Oct plan. The owner's plan is followed here; these differences need the owner's yes (strategy, open decision 7):

| M5 as written | This beta |
|---|---|
| 20–24 adults who aren't friends | 20 Polish iPhone users, at most 20% from the founder's own circle |
| A comparison with each person's real substitute (Notes, Reminders, Siri) | Only asked in the week-one call ("what would you have used?") |
| A character-light control group | None: a second build variant would be a new feature under the freeze |
| Spontaneous later retrieval of a memory | Sprawy closed after a bring-back |
| Paid intent versus actual payment | Not measured (free beta); at most one question in the call |

## After the beta: the M5 decision
Continue, narrow, pivot or stop, recorded as an ADR with these numbers and their denominators (`docs/implementation/MILESTONES.md`, M5).

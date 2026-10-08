# First hello → your corner

Design revision 1.1 · 8 October 2026. The user's requested direction: introduce Doddy through conversation, gather useful personalization, then show a different main screen with what Doddy is doing.

## Experience

**First visit:** “Hey. Let’s talk.” Three clear routes: get to know each other, see what Doddy can do, or start without the chat. No account or permissions are required for this introduction.

**Conversation:** One question at a time, with choice chips and free text. Every question has a skip action. Review & finish is available before completing all questions. Replies are a temporary draft, not automatically committed personal memory.

**Review:** Editable summary of the proposed preferences, with a remove action on each field. “Save these preferences” is the explicit approval step. Continuing without saving remains available. Raw introductory chat is discarded after approval/skip in the prototype.

**Returning Home:** A greeting from the approved name, reply-style cue, current focus if shared, useful details and an activity feed. The feed shows real demo outcomes and user-requested drafts; it does not manufacture tasks to make Doddy look busy. The lack of a profile never blocks access to the app.

## What the first conversation asks

| Field | Why it is useful | Optional answer format |
|---|---|---|
| Name or nickname | A familiar greeting | Up to 60 characters; does not verify identity |
| Desired help | More relevant starting points | Choice or own words, up to 240 characters |
| Answer style | Length/shape of future replies | Short, detailed, conversational, or own words |
| Language | Language of future replies | Follow the user, English, Polish, or own words |
| Humor | Optional personality | Subtle humor or straight to the task |
| Current focus | Suggestions relevant to a project/hobby/routine | Optional free text, up to 400 characters |

This is a starting conversation, not the maximum size of a future profile. Learn more over time when a task supplies useful context. For example, asking for a reminder can justify a timezone/date clarification; asking for study help can justify a learning goal. Propose saving a relevant preference, explain the effect, and let the user approve/edit/decline. Avoid a long first-run interrogation or unrelated requests for private details.

## Activity is distinct from suggestions

| Presentation | Authoritative basis | Prototype behavior |
|---|---|---|
| Nothing running | No active operation | Default Home after intro; no invented completion |
| Pending work | Accepted operation still pending | A simulated save is reported pending if Home is previewed during it |
| Ready for review | A prepared draft, not an executed action | User requests a small next step; scripted draft appears in activity |
| Saved in demo | Confirmed temporary page-memory commit | Successful capture creates a memory-linked activity entry |
| Updated in demo | Confirmed revision update | Correction creates an entry linked to the actual demo memory |
| Suggested next step | Approved context or explicit interest | Labeled invitation; not claimed as completed work |

No email, reminder, calendar event or external action is executed. A prepared step can be kept as a detail only through the same explicit capture/save flow. Deleting a memory removes its linked activity entries. Forgetting personalization removes personalized pending drafts but leaves separately saved memories intact; the confirmation states that distinction.

## Prototype vs future native app

The introduction is deterministic and scripted. It does not parse arbitrary free text into extra inferred attributes, run an AI model, use a microphone or inspect phone/account/contact information. Free text remains the exact user answer to the current field, bounded and escaped for display. New screens are mainly English; recorded language preference is a future reply setting, not a claim that all UI is translated.

Data lasts only for this page session. Browser localStorage/sessionStorage and network services are not used. In revision 1.2, reload/reset returns to optional guided setup, then first hello. The static screen gallery uses a clearly labeled fictional Alex profile; the interactive prototype starts empty.

## Native state/storage handoff proposal

- Separate `onboardingCompleted` from having any profile fields. After an explicit skip, do not force the introduction again; Settings can reopen it.
- Keep a draft separately from approved preferences. Draft extraction from future AI must use an allowlisted schema; the model cannot self-authorize persistence.
- Store only the reviewed fields, with `source = explicit_user_review`, revision and approval timestamp. Native storage commit, rather than this script, determines completion.
- Read approved preferences at the conversation boundary for relevant style/language/context. These preferences cannot override factual accuracy, user instructions or permission/tool boundaries.
- Allow view/edit/remove/forget in Settings. An abandoned edit leaves existing approved preferences unchanged. Clearing personalization does not silently delete separately saved memories.
- Keep actual operation state separate from activity history and suggestions. Use stable operation and memory IDs, receipt-backed transitions and explicit unknown outcomes.
- Do not copy page-memory code into the SQLite store or treat this prototype as an implemented P08 milestone. Integrate with the NEW repository only under the separately requested native implementation phase.

## Evidence and remaining review

The conversational format and personal Home are design proposals based on the supplied Character Bible and this user request. Optional, task-oriented introduction is consistent with [Apple onboarding guidance](https://developer.apple.com/design/human-interface-guidelines/onboarding?changes=_7). Reviewable preferences, clear uses and an opt-out are consistent with [Apple generative AI guidance](https://developer.apple.com/design/human-interface-guidelines/generative-ai?changes=lat__5). Both sources were reviewed on 8 October 2026; neither establishes that this particular flow improves retention or usability.

Require user review, observed task completion, bilingual review and native/physical-device checks. The design does not establish phone-owner identity, production personalization quality, market demand or a deployed backend.

## First-first setup insertion (revision 1.2)

The guided Back Tap/voice choice now precedes this introduction. Setup can be deferred. End the old setup audio session before a new explicitly requested conversation, with no setup transcript copied into profile drafts. See GUIDED-BACK-TAP-AND-VOICE-SETUP.md. All review-before-save and usable-without-profile rules above remain in effect.

# Doddy remembers what was discussed after a conversation: a recap, without the transcript

- **Date:** 2026-11-09
- **Decided by:** owner, in Polish:
  - "co do recap to tak chcę, żeby Doddy pamiętał, zrobić recap po rozmowie z kimś bez transkryptu ale co zostało omówione"
  - then four answers in one session: all four kinds of conversation; the recap is written by "Oba" (Apple on the iPhone where it can, otherwise Claude on Doddy's server after a yes); saving is "Raz włączam, potem samo"
- **Status:** accepted. Applied in steps, one pull request each (see "Order of work"). Step 1 is this decision and the shared rules in DoddyCore.
- **Replaces:** for Recordings only, the part of ADR-588 that says a recording's words never leave the iPhone. They still never leave without a yes (below). ADR-591 is answered: (c) on-device first, (a) the server after a yes.

## Why
- **What the owner asked for:** after a conversation, Doddy should remember what was discussed, not the words.
- **What exists today:**
  - The one recap Doddy has is the text file for a call Doddy made for the person (`CallRecap`, Files). It is not kept in memory.
  - Nothing in the app or on the servers summarises a conversation. `RecordingIntelligence` has no provider, and ADR-591 was still open.
  - Conversations with Doddy are kept as raw lines: 10 at most in `ConversationLogStore`. "Logs never become memory records."

## Decision
**The four conversations:**

| Kind (`ConversationRecapKind`) | Where it comes from | Who writes the recap |
|---|---|---|
| `voice_conversation` | a conversation with Doddy in the app | Apple on the iPhone, or Doddy's server after a yes |
| `recording` | a conversation with someone, recorded in Recordings (iOS gives no app the audio of an ordinary phone call) | Apple on the iPhone, or Doddy's server after a yes |
| `phone_line` | a call to or from Doddy's phone line (`call me now`, `call_me_later`) | Doddy's server, which has the call. It keeps no transcript: the recap goes to the iPhone like a call note, then the server deletes it |
| `call_for_you` | a call Doddy made for the person (CallCases) | the rules, from the brief and the answer card. No model and no transcript |

**What a recap is:**
- Three short lists: what was discussed, what was agreed, what is left to do.
- A title: who it was with and when.
- What wrote it: `on_device`, `server` or `rules`.

**What a recap is not:** the transcript. Code enforces this, not a prompt (`RecapRules` in DoddyCore):
- At most 6 points per list, at most 240 characters per point, one line each.
- At least one point in all.
- Refused if any point copies 10 or more words in a row from the conversation.
- The recap's text has to fit in a note (5,000 characters).
- If the model's output breaks a rule, the recap is refused and nothing is saved. It is never cut down to fit.

**Remembering ("Raz włączam, potem samo"):**
- **The switch:** Settings › Conversations, "Remember what we talked about" (`RecapSettings.rememberKey`). It is **off** until the person turns it on, per `memory_policy.explicit_long_term_memory_opt_in_default`. The switch is the explicit act DOD-06 asks for.
- **After that:** each recap is saved as a note with source `conversation_recap` and no tap. The app says "Saved" only after the store read the note back (DOD-08, `MemoryStore.save`). The note can be opened, corrected and deleted like any note.
- **Never:**
  - for a Private conversation (ADR-310 private mode);
  - for a conversation too short to have content (fewer than 30 words from the person);
  - while the switch is off;
  - in the car profile without a screen (none of these flows has one).
- **Turning the switch off** stops new recaps. Recaps already saved stay notes until the person deletes them, like any note.

**Who writes it ("Oba"):**
- **Apple on the iPhone first:** Apple's Foundation Models, on the device, where the iPhone has it. Nothing leaves the phone.
- **Otherwise Doddy's server**, only after a separate yes (`RecapSettings.serverWriterKey`, off until the person agrees on a card that says the words go to Doddy's server and to Anthropic, are not stored there, and what comes back). Without that yes, and without Apple's model, there is no recap, and the app says why once.
- **A Recordings recording** goes to the server only with that same yes. ADR-588's guard (no networking in `DoddyApp/Features/Recordings`) stays. The upload is made by the recap writer outside that folder, from text the person's yes released.

## Order of work (one pull request each)
1. This decision. DoddyCore: `ConversationRecap`, `RecapRules`, `RecapPolicy`, `RecapSettings`, `RecapMemoryText`, the model input and output (`RecapModelIO`), the call-for-you recap (`CallCaseRecap`), the `conversation_recap` source (schema, both servers' lists, Doddy Web). No screen yet.
2. The switch in Settings, and `call_for_you` saving its recap when an answer card arrives. Waits for #284, which has `SettingsScreens.swift`.
3. The writers: Apple's Foundation Models on the iPhone; `POST /v1/recaps` on the messaging server (Claude Haiku, no storage, daily caps); the yes card. `voice_conversation` at the end of a conversation. Waits for #281, which changes `VoiceSessionController.swift`.
4. `recording`: a "Recap" button on a recording, and after a recording stops when the switch is on.
5. `phone_line`: the post-call webhook for the phone agent, the recap made on the server, sent to the iPhone like a call note and then deleted on the server.

## Consequences
- **Notes about conversations without the words:** the person keeps the content, not the transcript. Raw lines still follow their own rules (ADR-603, `ConversationLogStore`).
- **Cost:** a server recap is one Claude Haiku call. It is capped per person and per day on the server (step 3).
- **Privacy:**
  - With the server yes, the text of a conversation leaves the iPhone for a few seconds to be summarised.
  - For a Recordings recording that is new, so the privacy policy draft and the App Store privacy answers need a line before outside testers (owner queue, step 3).
  - Apple's on-device model needs a recent iPhone. Its Polish may be weaker than Claude's.
- **Risk:** a summary can be wrong. It is labelled with what wrote it, shown in full when saved, and editable.

## Evidence
Step 1:
- `make test-core`: the new `ConversationRecapTests`.
- The servers' tests compare their source lists with `schemas/memory.schema.json` (#291).
- Nothing on a device yet.

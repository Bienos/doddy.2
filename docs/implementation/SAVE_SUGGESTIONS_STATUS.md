# Save suggestions after a conversation — status

Date: 2026-10-10. Owner request: "build the end-of-conversation save suggestions next". Decision: `DECISIONS.md` ADR-247.

## What the user gets
| Where | Behaviour |
|---|---|
| Talk screen, after End | A **Worth keeping?** card with up to 3 things the user said, in their words, e.g. "Marta's birthday is on the 12th of May", "The plumber Adam comes on Tuesday morning". **Nothing is ticked.** Each line is a tick box and an editable text field (editing ticks it). **Save N notes** saves the ticked ones; **Not now** closes the card for this conversation |
| After Save | "What was saved": a tick for each note that was saved and read back, a warning with the reason for one that wasn't, a dash for those left out, then OK. Saved notes appear in Memories with source "voice" |
| Settings → What Doddy knows | **Suggest notes after a conversation** (on unless turned off) with what it does |
| Settings → What leaves this iPhone | New "stays on this iPhone" line |

Not offered: a Private conversation, a conversation that failed, when notes can't be saved, when the switch is off.

## How sentences are chosen (`Packages/DoddyCore/Sources/DoddyCore/SaveSuggestions.swift`)
Fixed rules, on the iPhone, no model:
1. **Input:** only the user's transcribed lines from this conversation. Doddy's replies and anything a tool returned
   (weather, web, email, calendar) are never input; they are data, not the user's words.
2. **Sentences:** split at `. ! ? … ;` followed by a space, and at line breaks ("12.05" stays whole).
3. **Light trimming only:** leading fillers ("oh", "so", "by the way", "słuchaj", "no więc" …), a "remember (that)" /
   "zapamiętaj (że)" prefix, trailing "by the way" / "btw"; first letter capitalised. No other change.
4. **Never offered:** questions (ending "?" or starting with a question word, English or Polish); requests to Doddy
   ("remind…", "set…", "przypomnij…" …); small talk ("thanks", "dzięki" …); under 4 or over 40 words; secrets
   (password, hasło, card/bank PIN, card or account number, PESEL, IBAN, CVV, any run of 11+ digits).
5. **Worth keeping** needs 3 points: asked to remember 5; a digit 2; a weekday or month 2; birthday / anniversary /
   urodziny 3; recommendation (recommend, worth, poleciła, warto) 3; "my/our/mój …" or a name's 's 2, otherwise a
   family word (mum, boss, mama, szef …) 1; plan phrase (I need to, comes on, muszę, przychodzi …) 2; preference
   (likes, allergic, lubi, uczulony …) 2; a capitalised name 1.
6. **Nothing twice:** not if Doddy already put it on a save card or plan in this conversation (saved or declined), or
   a saved note already has all its numbers and 80% of its other words ("My gate code is 4821" vs a saved "Gate code
   4821"); a different number ("…is 5555") is still offered. The same sentence said twice is offered once.
7. **At most 3**, highest score first, shown in the order they were said.

## Privacy
- Runs on the phone over lines the voice screen already holds; nothing new is sent anywhere. The conversation itself
  still goes to ElevenLabs as before.
- Nothing is saved without a tick and a tap; each save is the normal validated, read-back save. Suggestions are not
  kept: closing the card or the app forgets them.
- Constitution: explicit opt-in memory (unticked by default, DOD-06), no claimed save without storage confirmation
  (DOD-08), tool content is data (only the user's lines are used), no secrets suggested.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/SaveSuggestions.swift` | `SaveSuggestions.suggest` (rules), `SaveSuggestionCard` (ticks, edits, saving, results) |
| `DoddyApp/Features/Voice/VoiceSessionController.swift` | Tracks note texts proposed in the conversation; offers once at the end; save/dismiss |
| `DoddyApp/Features/Voice/VoiceView.swift` | The card |
| `DoddyApp/Features/Settings/SettingsView.swift`, `DoddyApp/App/RootView.swift` | Switch and preference key |
| `Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift` | "Stays on this iPhone" line |

## Verified (Linux, Swift 6.1.2)
- `SaveSuggestionsTests` (15) on synthetic English and Polish transcripts: what is offered and in what words, what is
  never offered (questions, requests, small talk, secrets, vague chatter, length), no duplicates against proposed and
  saved notes, unticked start, edits, save results, no double save. `scripts/ci.sh --core-only`: PASS for core-only
  scope, 417 DoddyCore package tests, 0 failures (402 before).
- The controller's new methods (copied verbatim into a harness) type-check in Swift 6 against the real `MemoryStore`
  and DoddyCore. The rest of `VoiceSessionController.swift` and `VoiceView.swift` only syntax-parse here.

## Not verified (needs the Mac and an iPhone)
- App compile of the voice screen and controller; the card's look with Dynamic Type and VoiceOver.
- **Real transcripts:** how ElevenLabs' speech recognition punctuates and capitalises Polish and English. The rules
  lean on sentence ends and capitalised names; if transcripts come without punctuation, whole turns become one
  "sentence" (still under the 40-word cap, or not offered). Checklist V8–V10 in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`.
- How often suggestions are useful versus noise. Rules are a first cut; adjust the word lists from real use.

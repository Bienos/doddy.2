# Settings › Phone calls is a short hub with three pages, not one list of eight sections

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026: "rozmowy telefoniczne … design" (in the review request: the phone-call screens look bad) and "zrób teraz rozmowy telefoniczne".
- **Status:** applied in the pull request that adds this file. Compiled only in hosted CI; not run on a device.
- **Replaces:** the layout of one long Form in `CallsSettingsView` (ADR-753, ADR-754 added sections to it).

## Why
The screen had grown to eight sections in one scroll: setup notices, verify, notes, PIN, calling Doddy, memory on calls, calls for you (one row), Doddy calls you, booked calls, texts, history, recent calls. The review (`docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md`, section 4, in #352) found:
- A person who only wants to call Doddy scrolls past memory, texts and an export to find the number.
- "Call me now" answered at the bottom of the page, far from the button (`model.message` is the page's last section).
- Words a person has no use for: "Placed: Twilio accepted the call.", "Copied to the server", "Doddy messaging server" in a status line.
- "1 memories": the count was `"\(n) memories"`, never a plural.
- The PIN state, the number's state and two answers to "Call me now" were never translated: `StatusRow` and `Label` show a `String` as it is.
- The confirmation before Doddy calls someone said the call could be ended "from the Lock Screen". There is no Lock Screen Live Activity for these calls (owner, 5 Nov 2026: one small mark on Home).
- Calls for you showed a cost table (four decimals of USD) between the list of calls and the export.

## Decision
1. **The screen is a hub.** Notes waiting for you stay at the top (they are something to decide). Then one group of three rows with the orange tiles the first page of Settings uses (`SettingsRow`), each with what the server reported as its value ("On", "Off" or "Needs setup"): **Call Doddy**, **Doddy calls you**, **Calls for you**. Then one row, **Memory, texts and history**. Recent calls last.
2. **Three pages share the hub's `CallsModel`** (`CallsPages.swift`), so a change on one shows on the others without another request:
   - **Call Doddy:** Doddy's number and the Call button first; "So Doddy knows it's you" (number verified, with Verify my number when not; Answer calls from my number); Your PIN.
   - **Doddy calls you:** the consent switch with its text as the section's footer; Call me now with the server's answer right under it; calls you booked, with the quiet-hours sentence as their footer.
   - **Memory, texts and history:** memory on calls (the not-end-to-end text unchanged, as the footer), texts to Doddy, the export.
3. **Nothing is removed and nothing is weakened.** Every switch, button, consent text and privacy sentence stays, in the same words, except: "Placed: Twilio accepted the call." → "Placed: the phone service accepted the call."; "Copied to the server" → "Memories kept for calls" (a number, not "N memories"); "Phone calls need a Doddy messaging server…" → "Phone calls aren't available in this version of Doddy yet."; the section headers "Calling Doddy" and "Doddy calls for you" are gone (the row and page titles say it); the Calls for you footer is now one sentence about all three rows; "Doddy calls you" says the phone line isn't set up when the server reports outbound calls as unavailable, where before the page showed the switch and nothing else. The accessibility identifiers (`calls.inbound`, `calls.outbound`, `calls.callMeNow`, `calls.pin`, `calls.memoryCopy`, `texts.inbound`, `texts.export`, `calls.callCases`, `calls.message`) are unchanged.
4. **Values the app shows come from the server's answer only (DOD-02).** "On" and "Off" are `inboundEnabled` and `outboundConsent`; "Needs setup" is `!available.…` or `!phoneVerified`. Nothing says calls work.
5. **Translated:** the PIN and number states and the two answers to "Call me now" now go through `NSLocalizedString`.
6. **Calls for you:** the cost table is a collapsed "Cost" group under the list; the figures are unchanged. The confirmation says the call can be taken over or ended "from this screen", and that a small phone mark on Home brings you back to it while it runs (`ActiveCallBadge`).
7. **Left as it was:** the line in Calls for you that Doddy says it's an AI calling on your behalf (the disclosure at the start of the call stays on purpose), the notes inbox and its Save to memories rule (DOD-06), every server call.

## Consequences
- One more tap to reach PIN, memory, texts or the export; one fewer screen of scrolling to reach anything else. The Home sheet (Home › ••• › Phone calls) and Settings open the same hub.
- The Cost figures are two taps away instead of one scroll.
- **Not in this change:** the brief editor for Calls for you (about four screens and eight fields, the review's "one field: who and why, Doddy fills in the rest"). That is a change to what the model proposes and what the card shows for approval (DOD-07, the approval is bound to the exact payload), so it is its own pull request. The review also proposed hiding the cost figures from the user altogether; they are collapsed here, not removed, until the owner says.
- `docs/platforms/iphone.md` still says where the screen is opened from; it is not edited here, so it doesn't conflict with the Settings pull request that moves Phone calls to the first page.

## Evidence
- Ran: `swiftc -parse` on every changed file; `python3 -I tools/build_strings_catalog.py --check`; `make test-core`; `scripts/ci.sh --only checks`.
- Not run: the SwiftUI views were **not compiled** (no Xcode here); the hosted `ios-build` job is the first compile. Not seen on a device or on an iPad.

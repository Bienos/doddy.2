# No "Doddy is listening · Stop listening" pill above the screens

- **Date:** 2026-11-09
- **Decided by:** owner, in Polish: "usuń ten mikrofon i chmurkę z napisem Doddy słucha przestań słuchać, usuń całkowicie … bo przeszkadza"; asked whether everywhere or only on Home: "Usuń wszędzie".
- **Status:** accepted
- **Replaces:** the indicator part of ADR-361 (OP-024): the pill in its own window above every screen and sheet

## Why
The pill sat over Home's header during every conversation (screenshot of 9 Nov 2026: "Doddy słucha · Przestań słuchać" under the island and "Zapis rozmowy"), and the owner found it in the way.

## Decision
- `ListeningIndicatorWindow` and `ListeningIndicatorPill` are deleted, and RootView no longer installs the window. No screen shows the pill.
- Still there: iOS's own orange microphone dot; the conversation's own End; Siri's "Stop listening in Doddy" (`StopListeningIntent`), which stops the conversation, a voice memo and a recording and says what it stopped; `ListeningStop.stopAll` and its rules in DoddyCore (`ListeningPrivacy.swift`).

## Consequences
- On screens other than the conversation (Settings, a note), nothing of Doddy's own says the microphone is open; iOS's orange dot does. The privacy signal is weaker than ADR-361 designed, by the owner's choice.
- Muted conversations no longer say "Microphone muted" above other screens.

## Evidence
No test covered the pill (no UI test used `listening.indicator` or `listening.stop`). Not compiled here; the hosted Mac job compiles it.

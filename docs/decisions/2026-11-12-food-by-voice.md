# Doddy helps pick food by voice and opens the delivery app; the person orders there

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026: "yes build option 1", after being told that Uber's consumer ordering API needs an approval the intake form didn't let them ask for, and that Wolt, Glovo and Bolt publish only merchant and business-pays courier APIs, no ordering on a person's own account. Then "A build it now", knowing seven open pull requests also edit the voice files.
- **Status:** applied in the pull request that adds this file; the live voice agent gets the tool only on the owner's separate word (OWNER_QUEUE).
- **Replaces:** the "No voice tool" line of `2026-11-11-food-button`.

## Why
The owner wants to say "find me sushi and open Wolt". No delivery company lets an app order on a person's own account in Poland today (Uber's Consumer Delivery API is early access by approval; Wolt Drive, Glovo On-Demand and Bolt's partner APIs are for merchants). Helping choose and then handing over to the person's own app works now, needs nobody's approval, and costs nothing.

## Decision
1. **Voice tool `open_food_app`** (`app`: Uber Eats, Wolt, Glovo, Bolt Food or Pyszne.pl; `search`: optional, one line, at most 80 characters). The agent may first suggest a place with `find_places` or `web_search`.
2. **A tap first (ASK-01):** `AskFirst.tapFirst` shows "Open Wolt?" with "Search there for: …" and "You choose, pay and order in Wolt. Doddy doesn't see or place the order." Only the tap opens the app's https front page (its app when installed, the website otherwise). Not while driving (it needs a tap); stopped by Pause all (it reaches another app).
3. **Nothing is ordered, read or sent.** The search words are shown and said, not put in the link (the providers publish no search addresses). The agent hears `opened: … Nothing was ordered`, with the search in a data block; it never says it ordered, paid or booked, and never states a price, menu or time no tool gave it.
4. **Bolt Food** joins the Food button and the tool (`https://food.bolt.eu`).
5. Unknown app names are refused with the list, never guessed; a search that isn't one short line is refused, not cut.

## Consequences
- Works today with all five apps. It can't see whether the person ordered.
- The live agent needs the tool added (owner's word): until then voice can't open the apps, though the Food button can.
- One more tool pushed the backend's Logbook worst-case day (117 tools, pretty-printed) past its 16 KB cap: the cap is 24 KB now, the same as other routes. Real days from the iPhone are about 7 KB.
- If a provider ever offers ordering on the person's own account, it replaces the handoff behind the same tool, with an exact order card (DOD-07).

## Evidence
See the pull request: DoddyCore tests (`FoodHandoffTests`, `FoodAppsTests`, the activity and scope tests), the voice spec check, the backend logbook list. Not compiled here: `VoiceSessionController.swift` (no Xcode); not tried by voice.

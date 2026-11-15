# plan_trip: the Trips planner by voice in one call

- **What:** a new voice tool, `plan_trip`, on Doddy's server (`backend/src/flights/planTrip.ts`). It takes everything the user has said about a trip. If one thing is missing (where to, or a date that's past), it returns `ask:` with that one question. Otherwise it returns three Kiwi.com options with the assumptions it made. It reuses the Trips screen's planner (`understandTrip`, `searchTrip`). The app shows Kiwi.com buttons for the flights; stays links aren't shown in voice yet, because the voice screen's link card is for flights only.
- **Why:** the owner picked "Zaplanuj wyjazd" on 14 Nov 2026. A trip used to take three or four tool calls in a row; now it takes one.
- **Rules:** it runs at once as a public look-up (`AskFirst.publicLookups`, `doddy_rules.yaml`, `ASK_FIRST.md`), and the server's single-use approval is bound to the words. Results are web content. Links in the user's words are cut to their site before the model sees them. Failures say which step failed and never "no flights". Doddy books nothing.
- **Limits and timing:** no new setting. It follows `FLIGHT_SEARCH_ENABLED` and `ANTHROPIC_API_KEY` and the Trips planner's daily limits. The server deadline is 30 s; the app waits 40 s.
- **Ships with:** a `doddy` deploy (owner, with rows 113 and 115). After a TestFlight build from this merge, the live agent gets the tool (owner queue 116).
- **Also fixed:** "What Doddy did" put flight rows under Calendar; they now go under the web.
- **For STATUS.md:** `plan_trip` is merged and not live. Swift is compiled only in CI. Not seen on a device.

# Radar alerts by voice

Date: 2026-11-11. Owner: "Zrób alerty głosem i posprzątaj resztę".

**Decision.** `follow_news` takes three optional arguments, used only when the person asked to be told: `alert_words`, `tell_me` (`instant`, `daily`, `app`) and `daily_time` (HH:MM). Words alone mean "as it happens"; a time alone means one summary a day. It also sets an alert on something already followed.

**Enforced in code.** `NewsFollowAlertAsk.parse` (DoddyCore) refuses what the radar sheet refuses (`RadarAlert.problem`): a whole topic "as it happens" without words, a bad time, more than 10 words, words outside 2 to 40 characters. The agent hears `invalid` with the reason. The alert goes through the same `FollowingModel.apply` as the sheet.

**Honest result.** The reply says `alert kept` only when the radar's own check passes (for a server check, Doddy's server lists it); otherwise `alert not on the server` with the reason, and it shows in Following on this iPhone only. Push delivery still needs the Apple APNs keys (`docs/OWNER_QUEUE.md` 8), so the reply never promises a time.

**Not done.** SwiftUI app file not compiled here (hosted Mac job first); not run on a device. The live agent's `follow_news` tool gets the three parameters on the owner's instruction (this request); see `voice-agent/README.md`.

**For the owner (not in `docs/OWNER_QUEUE.md`, to keep this pull request out of that busy file):** the hosted privacy page (doddy.lol/privacy, not in this repository) should say that Doddy's server fetches Wikipedia and Wikimedia Commons text and pictures when it makes a document or presentation, sending only the search phrases it chose and no account data (decision `2026-11-10-better-presentations`). Legal wording on the live site is the owner's; whoever next edits the queue can add it as a row.


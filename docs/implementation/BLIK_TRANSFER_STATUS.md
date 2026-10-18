# BLIK transfers by voice: status (ADR-483)

Last updated 2026-10-18. Branch `claude/dreamy-cannon-gc33dj`, not merged.

## What it is
"Send Ania 50 zł for the pizza" shows a card with the person, their phone number (from Contacts, when iOS allows it), the amount in złoty and the title. The user sends the transfer themselves in their bank app, with BLIK's phone transfer ("przelew na telefon"). **Doddy never sends, pays or moves money**, and it can't see whether the user sent it.

Why not more: BLIK has no public interface that lets an app send money. Phone transfers exist only inside each bank's app; developers can only take BLIK payments as a shop, through a payment provider (Stripe, Tpay, PayU and others). The owner chose this hand-off over the two other options: taking BLIK for Doddy Pro (a new milestone with Stripe and App Store rules) or Doddy sending money itself (needs a bank or payment-company partner, or a KNF licence).

## How it works
| Step | What happens | Where |
|---|---|---|
| Switch | Settings › Connections › Money › **BLIK transfers**, off by default. Off: the agent hears "BLIK transfers isn't connected". No iOS permission. | `VoiceConnection.blik`, `ConnectionsView.swift` |
| The agent asks | `draft_blik_transfer` with `to`, `amount` (złoty), optional `title`, optional `currency` | `voice-agent/tools.json`, `instructions.md` |
| Typed checks | Amount kept in grosze, never rounded. Refused, so the agent asks again: more than two decimals, zero or less, not a number, another currency, more than 10,000 zł (Doddy's own ceiling, `BlikTransferLimits.maxGrosze`). Name and title bounded like every other tool argument. | `BlikTransfer.swift` |
| The person | Contacts read only if iOS allows it. One match: their numbers, each once. Several matches: no card, the agent asks which person. No match or no permission: the card shows the name as said and says to pick them in the bank app. | `BlikRecipient.resolve`, `VoiceSessionController` |
| The card | "A BLIK transfer for you to send": amount in the iPhone's language ("50,00 zł"), "To …", each number with **Copy**, the title with **Copy**, and the line "Doddy doesn't send money and can't see your bank…". Buttons: **I'll send it myself** / **Not now**. | `VoiceView.swift` |
| After the tap | Nothing runs. The same details stay on screen ("Send it in your bank app", with ✕) until dismissed or the next conversation, so the amount is there while the user opens the bank app. In memory only. | `VoiceSessionController.blikCard` |
| What the agent hears | `shown:` … "Nothing was sent: Doddy can't send money and can't see whether they send it. Never say it was sent, paid or done." Names and title as data (`<<<DATA`). Declined: `declined:` … "Nothing was sent". | `VoiceToolReply.blikShown` |
| What Doddy did | "Prepare a BLIK transfer · to Ania", result **Shown for you to send**, note "Doddy didn't send any money. You send it in your bank app." The 30-day log keeps the name, not the amount or title. No action status (Doddy did nothing to track). | `ActivityLog.swift`, `ActivityText.swift` |
| Never | In a plan card; while driving (CarProfile refuses); with Pause all on; in translator mode. | `Plan.swift`, `CarProfile.swift`, `ConnectionPause.swift` |
| Copy | Numbers as digits (a +48 or 0048 number as its nine digits; another country keeps its +); this iPhone only, no Universal Clipboard, gone after 10 minutes. The amount is never copied. | `BlikPhone.forCopy`, `copyForBlik` |

## Evidence
- `swift test --package-path Packages/DoddyCore` on Linux (Swift 6.2): 1,110 tests, 2 failures. The 15 new `BlikTransferTests` pass. The 2 failures (`OpenAIRealtimeTests.testOpenAIGrantParsing`, `VoiceTokenTests.testWakeWordKeyFromTheTokenServer`: `busy` where `serverNotConfigured` is expected) fail the same way on this branch before the BLIK change, so they aren't from it.
- `python3 -I scripts/voice_agent_spec.py check`: PASS, 59 tools.
- `python3 -I tools/build_strings_catalog.py --check`: PASS. Polish has lines for the 11 new screen strings; other languages show them in English. "To …" and the quoted title are built at run time and stay English, as the message card's are.
- `scripts/ci.sh --core-only` (Linux, Swift 6.2, Node 22): every step passes except three that fail the same way on this branch without the BLIK change: the forbidden-capability guard (networking and AuthenticationServices in `VoiceAuthSession.swift` and `VoiceAccessGate.swift`), the non-UI app type-check (6 errors in `VoiceConfig.swift`, `URL` not in scope), and the 2 DoddyCore tests above. All three come from commit `754e5d6`. The iOS build is NOT RUN (`--core-only`).

## Not done or not verified
- **The app code has not been compiled.** No Mac here; `VoiceView`, `VoiceSessionController`, `ConnectionsView`, `DeviceConnections` and `ActivityView` changes are unbuilt. Hosted CI builds only on a pull request or a manual run.
- **Not seen on a device:** the card, the Copy buttons, the Money group in Connections, "50,00 zł" formatting, Dynamic Type at AX5, VoiceOver labels ("Copy phone number", "Copy title").
- **Live ElevenLabs agent:** the tool is `not_synced`. Until the owner adds it (`voice_agent_spec.py elevenlabs`, then attach it to `agent_0501m4et27vyeawrwqfdxxfszfa6` and merge the prompt lines), ElevenLabs conversations can't use it. OpenAI Realtime (the default voice) gets it with the next app build, because the app bundles `voice-agent/`.
- **Whether bank apps accept the pasted number** (nine digits) has not been tried in any bank app.
- **Polish wording** is mine, not a native review (`l10n/REVIEW_NOTES.md` applies).

## Privacy
- The person's name, the amount and the title are spoken, so they are part of the conversation sent to OpenAI or ElevenLabs, like any other request. The reply adds the contact's name as Contacts has it. Phone numbers never go to the agent.
- No bank, BLIK or payment service is contacted. No new network request, permission, server or key.

## Decisions for the owner
1. Keep the 10,000 zł ceiling, or change it.
2. Add the tool to the live ElevenLabs agent.
3. Whether to try opening the user's bank app from the card. iOS opens another app only through its own link scheme; Polish banks' schemes aren't documented, so this would need testing with real bank apps, or a "Doddy Bank" Shortcut the user makes (as for the camera, ADR-291).

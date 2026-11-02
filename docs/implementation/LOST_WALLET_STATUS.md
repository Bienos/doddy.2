# Lost wallet by voice: status (ADR-686)

Owner, 2 Nov 2026: "Continue", to "Shall I start on the lost-wallet flow?" (the mObywatel review of 1 Nov
ranked "I lost my wallet / ID by voice" first, because it needs no API and nothing from the owner).

## What it does

The person says "zgubiłem portfel" or "ukradli mi dowód". The voice agent asks, if it doesn't know, what was
in the wallet, then calls `lost_wallet` with only three facts: what is gone (`id_card`, `bank_cards`,
`driving_licence`, `passport`), whether it was stolen, and whether the person is abroad. The voice screen shows
a checklist, most urgent first:

1. **Block the bank cards:** the bank's app or helpline, or the shared line +48 828 828 828 (button: call).
2. **Report the ID card lost:** mObywatel, gov.pl or a municipal office; the ID is cancelled for good (button: gov.pl).
3. **Reserve the PESEL number:** mObywatel or gov.pl (button: gov.pl).
4. **Report the theft to the police:** only when stolen; no button (112 only in danger).
5. **Report the passport lost**, and abroad **contact a Polish consulate** (buttons: gov.pl).
6. **Report the driving licence lost** (button: gov.pl).
7. **Apply for a new ID card** (button: gov.pl).

Only the steps that fit are shown. The agent hears the same steps in English and walks the person through them
one at a time.

## The rules, as code (`Packages/DoddyCore/Sources/DoddyCore/LostWallet.swift`)

| Rule | Where | Test |
|---|---|---|
| The model sends only what was lost, stolen, abroad; never a step, link or number | `parseLostWallet`, `LostWalletText` | `LostWalletTests.testRefusesWhatItCantUse`, `testAnUnknownItemIsRefusedNotDropped` |
| A button opens only https on `www.gov.pl`, or dials only +48 828 828 828 | `LostWalletPlan.isAllowed`, checked again in the app before opening | `testEveryButtonIsAnAllowedPageOrNumber`, `testRefusesAnyOtherPageOrNumber` |
| Cards first whenever they were lost; theft only when stolen; each step once | `LostWalletPlan.steps` | `testCardsComeFirstWheneverTheyWereLost`, `testTheftIsReportedOnlyWhenStolen`, `testEveryStepAppearsOnce` |
| Nothing is ever marked done for the person; the tick is theirs | `VoiceSessionController.toggleLostWalletStep` (app) | not covered on Linux |
| The agent is told never to say a card is blocked or a document cancelled, never to ask for or repeat card numbers, PESEL, ID numbers, PINs or passwords, and to send the person to 112 if in danger | `VoiceToolReply.lostWalletShown`, the tool's description | `testTheReplyListsTheStepsAndWhatTheAgentMustNeverSay` |
| ASK-01: the checklist is its own card; each page or number opens only on a tap | `AskFirst` (`.ownPayloadCard`), `ToolCatalog` (`.handoff`, `.card`) | `testItIsItsOwnCardAndNeverRunsWithoutOne`, `ToolCatalogTests` |
| Nothing kept: no row in What Doddy did, the card is in memory only and goes at the next conversation | `ActivityLog` (nil), `VoiceSessionController.lostWalletCard` | `ActivityTextTests` |

Broken on purpose and caught by a test, then restored: allowing any host or scheme (3 failures), and dropping an
unknown item instead of refusing it (1 failure).

## Not done

- **Not on the live voice agent.** `tools.json` says `not_synced`. Adding the tool to the ElevenLabs agent
  changes what the live agent can call, so it waits for the owner's yes. Until then the live agent doesn't know
  the tool, and an app built from this branch never receives the call.
- **No device test.** The SwiftUI card and the controller were syntax-checked here, not compiled: the hosted Mac
  job is the first compile.
- **No links into mObywatel itself.** No documented link opens a specific mObywatel screen, so the buttons open
  the gov.pl pages, which offer the same services after signing in.
- The card is in memory only: if iOS closes Doddy while the person is in their bank's app, the card is gone and
  the person asks again.
- Residence cards and other documents aren't covered.

## Device test

1. Say "zgubiłem portfel, były w nim karty i dowód". The agent asks nothing more, says one short line, and the
   card shows: block the cards, report the ID, reserve the PESEL, apply for a new ID.
2. Tap "Zadzwoń: 828 828 828": the phone app offers the call; cancel it.
3. Tap each "Otwórz gov.pl": Safari opens the right page.
4. Tick a step, then untick it. Close the card with ×.
5. Say "ukradli mi paszport, jestem w Berlinie": the card adds the police and consulate steps.
6. Check the ElevenLabs conversation log: the call's arguments hold only `lost`, `stolen`, `abroad`.

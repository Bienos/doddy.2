# Lost wallet by voice: status (ADR-692)

Owner, 2 Nov 2026: "Continue", to "Shall I start on the lost-wallet flow?" (the mObywatel review of 1 Nov
ranked "I lost my wallet / ID by voice" first, because it needs no API and nothing from the owner).

## What it does

The person says "zgubiłem portfel" or "ukradli mi dowód". The voice agent asks, if it doesn't know, what was
in the wallet, then calls `lost_wallet` with only three facts: what is gone (`id_card`, `bank_cards`,
`driving_licence`, `passport`), whether it was stolen, and whether the person is abroad. The voice screen shows
a checklist, most urgent first:

1. **Block the bank cards:** a permanent block (zastrzeżenie) in the bank's app or helpline, or the shared line
   +48 828 828 828 (24/7, from abroad too; you say the bank's name; one call covers one bank) (button: call).
2. **Report the ID card lost:** mObywatel, gov.pl or any gmina office; immediate and permanent; a police report alone
   cancels a stolen one (button: gov.pl).
3. **Check that the PESEL is reserved:** a lost-ID report reserves it for adults, but whether a police-only report does
   isn't stated, so the card says to check (button: gov.pl).
4. **Report the documents to Dokumenty Zastrzeżone** (ID card and passport): the banks' shared database, still
   recommended by gov.pl (button: the ZBP page).
5. **Report the theft to the police:** only when stolen; no button (112 only in danger).
6. **Report the passport lost**, and abroad **contact a Polish consulate** (buttons: gov.pl).
7. **Report the driving licence lost**, within 30 days (button: gov.pl).
8. **Apply for a new ID card**, after the old one is cancelled (button: gov.pl).

Only the steps that fit are shown. The agent hears the same steps in English and walks the person through them
one at a time.

## The rules, as code (`Packages/DoddyCore/Sources/DoddyCore/LostWallet.swift`)

| Rule | Where | Test |
|---|---|---|
| The model sends only what was lost, stolen, abroad; never a step, link or number | `parseLostWallet`, `LostWalletText` | `LostWalletTests.testRefusesWhatItCantUse`, `testAnUnknownItemIsRefusedNotDropped` |
| A button opens only https on `www.gov.pl` or `dokumentyzastrzezone.pl`, or dials only +48 828 828 828 | `LostWalletPlan.isAllowed`, checked again in the app before opening | `testEveryButtonIsAnAllowedPageOrNumber`, `testRefusesAnyOtherPageOrNumber`, `testLinksAreTheOnesReadOnTheOfficialPages` (pins all seven addresses) |
| Cards first whenever they were lost; theft only when stolen; the PESEL check and the new ID only with an ID card, cancellation before the new ID; each step once | `LostWalletPlan.steps` | `testCardsComeFirstWheneverTheyWereLost`, `testTheftIsReportedOnlyWhenStolen`, `testWhichItemsBringWhichSteps`, `testTheNewIdCardComesLastAndTheCancellationBeforeIt`, `testEveryStepAppearsOnce` |
| Nothing is ever marked done for the person; the tick is theirs | `VoiceSessionController.toggleLostWalletStep` (app) | not covered on Linux |
| The agent is told never to say a card is blocked or a document cancelled, never to ask for or repeat card numbers, PESEL, ID numbers, PINs or passwords, and to send the person to 112 if in danger | `VoiceToolReply.lostWalletShown`, the tool's description | `testTheReplyListsTheStepsAndWhatTheAgentMustNeverSay` |
| ASK-01: the checklist is its own card; each page or number opens only on a tap | `AskFirst` (`.ownPayloadCard`), `ToolCatalog` (`.handoff`, `.card`) | `testItIsItsOwnCardAndNeverRunsWithoutOne`, `ToolCatalogTests` |
| Nothing kept: no row in What Doddy did, the card is in memory only and goes at the next conversation | `ActivityLog` (nil), `VoiceSessionController.lostWalletCard` | `ActivityTextTests` |

Broken on purpose and caught by a test, then restored (on the first version): allowing any host or scheme (3 failures),
and dropping an unknown item instead of refusing it (1 failure).

## Where the words and links come from

`docs/research/2026-11-02/lost_wallet_pl.md`: official gov.pl pages, the statutes and the banks' own pages, read on
2 Nov 2026. **The first push of this branch (`67e4e4f`) had four gov.pl addresses I had written from memory (ID card,
PESEL, passport, driving licence) and a code comment saying they were checked; they weren't.** The follow-up commit
replaced them with the addresses on the official pages; each of the seven was fetched again by hand and its own page
title read. A test now pins them.

## Not done

- **Not on the live voice agent.** `tools.json` says `not_synced`. Adding the tool to the ElevenLabs agent
  changes what the live agent can call, so it waits for the owner's yes. Until then the live agent doesn't know
  the tool, and an app built from this branch never receives the call.
- **No device test.** The SwiftUI card and the controller were syntax-checked here, not compiled: the hosted Mac
  job is the first compile.
- **Left out because the official pages don't say it plainly:** whether mDowód stays valid after the ID card is
  cancelled; whether a police-only report reserves the PESEL; whether the app notifies when the new ID is ready; a
  national online police form; whether mPrawo jazdy is accepted abroad; whether "Zastrzeż dokument" in the app covers
  the driving licence (sources disagree, so the card names only the ID card and passport).
- **The app's button names differ between official documents** ("Załatw sprawę" and "Złóż wniosek"). The card
  names only "Unieważnij swój dowód", "Usługi", "Zastrzeż PESEL" and "Zastrzeż dokument", as the ministry's pages
  and the mObywatel rules give them. Check them on a phone.
- **No links into mObywatel itself.** No universal link is registered for any government domain and no URL scheme
  is documented, so the buttons open web pages.
- **Not covered:** a lost phone (the mObywatel certificate is revoked on +48 42 253 54 74), foreigners' residence
  cards, SIM cards.
- The card is in memory only: if iOS closes Doddy while the person is in their bank's app, the card is gone and
  the person asks again.

## Device test

1. Say "zgubiłem portfel, były w nim karty i dowód". The agent asks nothing more, says one short line, and the
   card shows: block the cards, report the ID, check the PESEL, Dokumenty Zastrzeżone, apply for a new ID.
2. Tap "Zadzwoń: 828 828 828": the phone app offers the call; cancel it.
3. Tap each "Otwórz gov.pl" and "Otwórz Dokumenty Zastrzeżone": Safari opens the right page, not a "page not found".
4. Tick a step, then untick it. Close the card with ×.
5. Say "ukradli mi paszport, jestem w Berlinie": the card adds the police and consulate steps.
6. Check the ElevenLabs conversation log: the call's arguments hold only `lost`, `stolen`, `abroad`.

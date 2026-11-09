# Messages (Ask Doddy) is on by default

- **Date:** 2026-11-09
- **Decided by:** owner, 9 Nov 2026: "messages should work on by default and not that I have to change it in settings" (said in Polish: "uwazam ze messages powinny dzialac on by default a nie ze ja se musze w ustawieniach je robic zmioen to").
- **Status:** accepted; ships with the pull request that adds this file.
- **Replaces:** ADR-587's "Off by default" for `PreferenceKey.assistantConsent`, and the "Turn on Ask Doddy" dialog as a gate before the first question. ADR-585's "Opt-in like before" in `MessagesView`.

## Why
Opening Messages on a fresh install showed "Turn on Ask Doddy in Settings first" and nothing worked until the person found Settings › Connections › Ask Doddy. The owner wants Messages to work from the first tap.

## Decision
1. **A missing value means on.** `PreferenceKey.assistantConsentDefault = true` is the default for `MessagesView`, Settings › Connections, Settings › Ask Doddy and "What leaves this iPhone". A value the person saved, on or off, always wins, so nobody who turned it off is switched back on.
2. **The switch stays.** Settings › Ask Doddy › "Turn on Ask Doddy" is still there. Turning it off stops sending at once (`policy.consentGranted` is false, so `MessagesModel` and `AssistantService` refuse before any network call); turning it on again still shows the disclosure dialog.
3. **What the person is told** is unchanged and always visible: the Messages screen shows "Doddy is an AI, not a person…" with what is sent to Doddy's server and Anthropic, and "What leaves this iPhone" lists the row as active. Nothing is sent until the person sends a message.
4. **Not touched:** "Use relevant saved notes" (still on by default as before; private notes are never sent, ADR-310), "Texts from Doddy" and "Text with Doddy" (SMS, their own consents), and the per-conversation server copy for Doddy Web.

## Consequences
- Every iPhone that never saved a choice now sends typed questions to Doddy's server and Anthropic when the person sends a message. That is a change of consent model from opt-in to opt-out, so the privacy policy and App Store privacy answers have to say it (owner rewrites them at the end, as in `2026-11-09-usage-counts-on-by-default`; OWNER_QUEUE 26). `legal_review_required_before_launch` in `doddy_rules.yaml` still applies.
- Opening Messages with the switch on now asks Doddy's server for the list of files Doddy made (`MadeDocumentsModel.refresh`), without a question being sent.
- Constitution: DOD privacy and consent rules still hold because nothing is sent without the person's own send action; the claim "Doddy asked first" is no longer true for this feature and must not be made.

## Evidence
- Changed: `DoddyApp/App/RootView.swift`, `Features/Messages/MessagesView.swift`, `Features/Settings/SettingsHubs.swift`, `Features/Settings/SettingsScreens.swift`, `Features/Privacy/DataFlowView.swift`; UI tests in `DoddyUITests/LaunchSmokeTests.swift` updated to the new default.
- Not run here: the app build and the UI tests (no Xcode in this session); the pull request's `ios-build` job is the first compile. Not seen on a device.

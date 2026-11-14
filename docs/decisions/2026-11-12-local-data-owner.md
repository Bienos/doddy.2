# Local data belongs to the Doddy account that made it; a sign-out stops uploads

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending (account data review, 12 Nov 2026)
- **Status:** proposed, applied in the pull request that adds this file
- **Replaces:** nothing; narrows how the uploads of decision `2026-11-08-required-account` work

## Why
- Notes, lists and the Messages thread live on the iPhone, and a sign-out kept them (the sign-out dialog says so). Some of them are also copied to the signed-in account on Doddy's servers: the Messages copy for Doddy Web (`ServerThreadSync`), Memory on calls (`MemoryCopySync`), notes and conversations kept on the server (`WebMemoryModel`, ADR-603) and Logbook's counts (`LogbookModel`, ADR-602).
- None of those asked whose data it was. After one account signed out and another signed in on the same iPhone, the next send went to the second account.
- A sign-out also left those switches on and left the older voice session from Sign in with Apple in place, so voice could still start.
- The voice token client used a plain URLSession, which follows redirects with the request's token, unlike the messaging server's transport.

## Decision
1. **An owner is recorded.** `LocalDataOwner` (DoddyCore) keeps the account id the iPhone's data belongs to (UserDefaults `localData.ownerAccountID`, which goes with the app). The first account signed in takes it over; so does the first launch of this version for whoever is signed in. Another account takes it over only when the iPhone has no notes, lists or messages (a store that can't be read counts as not empty). Checked after every sign-in and at launch.
2. **One gate for every upload.** The Messages copy, Memory on calls, kept notes and conversations, and Logbook each ask `LocalDataOwner.upload(for: signedInAccountID)` first: `allowed` only for the owner; `waiting` (send nothing, say nothing) while nobody is signed in or no owner is recorded yet; `otherAccount` (send nothing, and the web switches and Logbook say "This iPhone holds Doddy data from another account, so nothing from it is sent to yours."). A build with no Doddy accounts configured keeps its uploads (it only has its own device sign-in). Deleting the Messages web copy is skipped while another account's thread is here (that copy isn't this thread's).
3. **A sign-out stops uploads.** Memory on calls and both "Keep on Doddy's server" switches go off on this iPhone (the server isn't asked; what the account keeps stays with the account until deleted from it). Logbook forgets the counts and send state of the account that left; its switch stays as the person set it, because "off" also means "delete the counts on the server", which must never reach the next account. The older voice session ends on this iPhone at once and then at the voice server.
4. **Per-server use flags stay.** `doddyAccount.backendUse.*` and `doddyAccount.messagingUse.*` record whether a server takes Doddy accounts, which is the server's property, re-checked at each sign-in. While signed out they are what stops the app falling back to a device session or an anonymous messaging account, so a sign-out keeps them.
5. **Voice requests stay on their server.** `VoiceTokenClient` and `VoiceAuthAPI` refuse redirects (the messaging transport's delegate) and read an answer only from the scheme, host and port they asked (`BearerHost`).

## Consequences
- **What the person sees:** after signing out and in again, Memory on calls and the web switches are off until turned on again. A second person signing in on an iPhone with someone else's notes sees them (as before) but nothing of them reaches their account; turning on a web switch says why.
- **Not yet:** an "Erase Doddy's data on this iPhone" button where the mismatch is found. The erase steps live in `SettingsScreens.swift` (Settings › Memories › Delete all), which open pull requests are changing; until then, erasing there and opening Doddy again hands the empty iPhone to the signed-in account. Marked as a TODO in `Features/Account/LocalDataOwnership.swift`.
- **Not covered here:** bringing an iPhone's earlier device data into an account at sign-in (`DoddyAccountServers.bringEarlierData`) doesn't ask the owner yet; that code is being changed by another open pull request.
- **Fresh install:** clearing the Doddy account and voice sessions left in the Keychain is decision `2026-11-12-deleted-files-stay-gone` (another pull request).
- Rules: DOD-06 (memory under the person's control), DOD-08 (no "sent" without a send), DOD-11 (where data goes is visible).

## Evidence
- DoddyCore on Linux (Swift 6.1.3): `LocalDataOwnerTests`, `BearerHostTests`, new cases in `WebMemoryModelTests` and `LogbookModelTests`; counts in the pull request.
- Not compiled here: the app files (`LocalDataOwnership.swift`, `DoddyAccountApp.swift`, `RootView.swift`, `MemoryCopySync.swift`, `ServerThreadSync.swift`, `WebMemory.swift`, `Logbook.swift`, `WebMemoryView.swift`, `LogbookSection.swift`, `VoiceAuthSession.swift`, `VoiceTokenClient.swift`, `ServerHTTPTransport.swift`); the hosted `ios-build` job is their first compile. Not run on a device.

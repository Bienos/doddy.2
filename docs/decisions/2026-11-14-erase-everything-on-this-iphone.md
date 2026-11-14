# "Erase everything on this iPhone" goes through every store and says "erased" only when each was read back as empty

- **Date:** 2026-11-14
- **Decided by:** proposal, owner approval pending (the owner approved editing `SettingsScreens.swift` and `DoddyAccountApp.swift` for this change)
- **Status:** proposed, applied in the pull request that adds this file
- **Replaces:** the Settings › Memories "Delete all memories" routine; carries out the "Not yet" in decision `2026-11-12-local-data-owner` (the erase where another account's data is found)

## Why
- "Delete all memories" removed notes and lists, what Doddy learned, calls, tasks, Messages, recordings, the parcel list, the inFakt key and the invoice draft. It left the remembered conversations (which are offered to the next voice conversation as context), the About you answers, the files Doddy made, the parking spot, the training log and plan, saved trips, the activity list, the widgets' snapshot, scheduled notifications and alarms, and the settings. Deleting a Doddy account left all of the local data.
- Nothing listed where the app keeps something about a person, so each store was a place a change could forget. A test of the notes' files and a check of the Keychain existed, nothing tied them to an erase.
- Backup rules differed between stores with no stated reason: the training log, recording audio and the invoice draft were out of backups, the transcripts of the last conversations, the activity list and the drafts (whose own comment said "never backed up") were in.
- The erase has to be able to say what it could not confirm (DOD-08), and it must not hand what is left to the next account (decision `2026-11-12-local-data-owner`).

## Decision
1. **One erase, one list.** `DeviceStoreID` (DoddyCore) lists every place; `docs/architecture/DEVICE_DATA_STORES.md` is its text version. A plan (`DeviceErasure`) has one step per store with an erase and a read-back, runs every step even after a failure, never reports a store with no step as erased, and is safe to run again. The result is "erased" only when every store was read back as empty; otherwise it names the stores not confirmed. Tests fail when a file starts keeping something in a persistent place without being registered, when the plan or the doc lacks a store, when a new `PreferenceKey` isn't classified, when a Keychain service isn't in the table, or when a backup rule stops matching the sources.
2. **Deny by default.** Preferences are erased key by key unless `DevicePreferences` keeps the key with a reason; the Keychain is erased service by service unless `DeviceKeychain` keeps it; the temporary folder, Caches and Documents are emptied whole. A new key or service is erased until someone decides otherwise.
3. **What is kept, on purpose** (the doc lists the keys): the signed-in account and what ties this iPhone to Doddy's servers (so the account can be deleted next, and so an account that finds another account's data can erase it and take the iPhone over), install markers (erased, the next launch would sign the person out), first-run flags and the Terms acceptance (erased, the first-run screens would cover the result), the language, development settings, deletion markers, the person's privacy choices (a switch that limits what is shown, read out, shared or sent keeps its position, so an erase can't loosen it), and the switches that mirror a copy on Doddy's server (on, the app's sync makes the server copy as empty as the iPhone). The confirmation says so.
4. **The Doddy account is a separate step.** After a confirmed erase a signed-in person is offered Delete my Doddy account, Sign out or Not now. "Delete my account and erase this iPhone" on the account page erases after every server confirmed the deletion and then also removes the sign-in items and server ties (`DeviceErasureScope.afterAccountDeleted`). After a deletion the welcome covers Settings until someone signs in, so the offer is made with the deletion, not after it.
5. **Safe to run.** It first stops a conversation, a voice memo or a recording through the call Siri's "Stop listening" uses, and refuses (nothing erased) while the microphone is in use or the screen is shared. The data owner is cleared, and the signed-in account made the owner of the empty iPhone, only after every store was read back as empty.
6. **No database change.** No migration; `DoddyDatabase.swift` is unchanged. Rows are deleted through the existing repository calls, each reading its tables back, and the connection is never closed or deleted under the running app.
7. **One backup rule.** What the person saved to keep is in backups; what Doddy fetched, recorded or drafted for its own work is not. The conversation transcript folder, the activity list, the unfinished-note drafts and the saved trips are now marked out of backups. The notes database holds the Messages thread, recordings' words, calls, tasks and what Doddy learned next to the notes in one file and can't be split without a new file, so they stay in with the notes (as the Memories footer says).
8. **Strings.** Every new string has a Polish line; the sentences that described the old routine left the catalogs.

## Consequences
- An iPhone restored from a backup made before this change can bring back the four files that are now out of backups.
- Copies on Doddy's servers other than Memory on calls (the Messages web copy, notes and conversations kept on the server, Logbook counts, Studio items, tasks and calls, voice conversations at the provider) stay until the account is deleted; a finished task not yet acknowledged can return to the iPhone when Doddy is opened. The confirmation says so.
- The text of the conversation just ended, and its "worth keeping?" cards, stay on the voice screen until Doddy is closed (`VoiceSessionController` was not changed here), and timers, stopwatch or focus sessions running in memory finish by themselves.
- Spotlight can't be read back; iOS's confirmation of the delete is what counts.
- Alarms and timers Doddy set are cancelled by the erase; the confirmation names them.
- The capability guard (`scripts/check_forbidden_capabilities.sh`) allows one more Keychain file, which may only list services and delete them (it may not read, add or change a value).
- Owner questions: `docs/OWNER_QUEUE.md` row 98.

## Evidence
- DoddyCore on Linux (Swift 6.1.3): `DeviceErasureTests`, `FolderErasureTests`, `DevicePreferencesErasureTests`, `DeviceStoreInventoryTests`, `LocalDataOwnerTests`; counts in the pull request.
- `scripts/typecheck_app_logic.sh` (47 app files, Swift 6): includes the changed `ConversationLogStore`, `ActivityLogStore`, `UnfinishedNoteStore`, `MessagesModel` and, added here, `LocalMadeFilesStore`.
- `scripts/ci.sh --only checks`.
- Not compiled here: the app files `EraseThisIPhone.swift`, `EraseThisIPhoneRow.swift`, `EraseThisIPhoneText.swift`, `DeviceKeychainEraser.swift`, `SettingsScreens.swift`, `DoddyAccountApp.swift`, `DoddyAccountSettings.swift`, `SpotlightSync.swift`, `SharedListsController.swift`, `MessagesView.swift`, `TrainingLogView.swift`; the hosted `ios-build` job is their first compile. Not run on a device: nothing here has been seen erasing a real iPhone, and the Keychain, AlarmKit, Live Activity, notification, Spotlight and iCloud steps are untested outside a compile.

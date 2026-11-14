# Where Doddy keeps something about a person on this iPhone

Platforms: iPhone and iPad (the app, its widgets, the share and screen extensions). The Watch and Mac apps are paused (ADR-572).

This is the list "Erase everything on this iPhone" works from, so a later change can't add a place and forget it. The list in code is `DeviceStoreID` (`Packages/DoddyCore/Sources/DoddyCore/DeviceErasure/`); the plan that erases and reads each place back is `DoddyApp/Features/Privacy/EraseThisIPhone.swift`. Tests (`DeviceStoreInventoryTests`, `DevicePreferencesErasureTests`, `DeviceErasureTests`) read the app's sources and fail when:

- a file starts keeping something in Application Support, Caches, Documents, the App Group folder, the Keychain, iCloud or the search index without being registered in `DeviceStoreInventory` with the store that erases it;
- the plan has no `case` for a store, or this page doesn't name one;
- a new `PreferenceKey` has not been classified (erased, or kept with a reason);
- a Keychain service the app uses is not in `DeviceKeychain.services`;
- a backup rule here stops matching what the sources do.

Counts (stores, keys, services) are read from those lists, not copied here.

## How "erased" is decided (DOD-08)

Each store has a step with an **erase** and a **read-back**. A store counts as erased only when the read-back shows nothing of the person's is left. Every step runs even when an earlier one failed, a store with no step is never reported erased, and running the plan again is harmless (`DeviceErasure`, tested on Linux with in-memory stores). The result is "erased" or "these stores weren't confirmed: …"; the rest was still erased.

Before the steps, anything still using the microphone is stopped through `ListeningStop.stopAll()`, the call Siri's "Stop listening" uses (a conversation ends, a voice memo stops, a recording is saved); if the microphone is still in use after that, or the screen is being shared with Doddy, nothing is erased and the person is told. The order is `DeviceStoreID.erasureOrder` (sharing is stopped while the lists still exist, the server copy is emptied while its switch is still on, models are erased through their own code before their folders are swept, preferences go last).

## The stores

"Read back" says how emptiness is checked. "Backup" is the rule below.

### The notes database, `Application Support/Memories/memories.sqlite`

No migration was added and `DoddyDatabase.swift` is unchanged: rows are deleted through the existing repository calls (each reads its tables back as empty, and the plan reads them again), and the SQLite connection is never closed or deleted under the running app. `secure_delete` is on, and the search index is rebuilt in the same transaction (ADR-584).

| Store | Holds | Erased by | Read back |
| --- | --- | --- | --- |
| `notesAndLists` | notes, lists and items, corrections, reminders on notes, list shares, photo and voice-memo rows, the search index | `MemoryStore.deleteAll()` | notes, list items, corrections, photos, voice memos all empty |
| `learnedFacts` | facts, routines, counts of corrections | `LearningStore.deleteAll()` | facts, procedures, outcome events empty |
| `profile` | the "About you" answers | `ProfileStore.forget()` | profile empty |
| `callCases` | calls Doddy made: cards, answers, transcripts | `callCaseRepository.deleteAll()` | list empty |
| `errands` | tasks handed to Doddy: words and results | `errandRepository.deleteAll()` | list empty |
| `messagesThread` | the typed conversation in Messages | `messageThreadRepository.deleteAll()`; the files Doddy made until now are not offered again; an open Messages screen empties its memory | no message |
| `recordings` | recordings' rows, words, search index | `recordingRepository.deleteAll()` | no recording id |
| `trainingLog` | the training logbook, its own file `Sport/training-log.sqlite` | the yes is taken back, sessions deleted (`TrainingLogModel`); not opened at all if the person never turned it on | sessions empty, consent not granted |

Not erased from the database: where the person is in the first-run steps (`onboarding_progress`), which is a flag (kept, below). The training log's file stays on disk, empty, with its "not granted" row: the model may hold it open, so the file is not deleted under it.

### Files in the app's own folders

| Store | Where | Erased by | Read back |
| --- | --- | --- | --- |
| `notePhotoFiles` | `Memories/NotePhotos` | folder emptied | folder empty |
| `noteAudioFiles` | `Memories/NoteAudio` | folder emptied | folder empty |
| `recordingFiles` | `Memories/Recordings` | `RecordingFiles.removeAll()` | folder gone |
| `conversationTranscripts` | `Conversations/recent.json`, the last voice conversations as text | `ConversationDeletion.clearAll` (drops recaps still being written), folder emptied | no conversation, folder empty |
| `activityList` | `Activity/activity.json`, "What Doddy did" | `ActivityLogStore.clear()`, folder emptied | no entry, folder empty |
| `unfinishedNotes` | `Drafts/unfinished-notes.json` | `UnfinishedNoteStore.removeAll()`, folder emptied | no draft, folder empty |
| `invoiceDraft` | `Invoices/invoice-draft.json` | folder emptied | folder empty |
| `madeFiles` | `MadeFiles/` (files Doddy made, kept a week) | `LocalMadeFilesStore.removeAll()`, folder emptied | no file, folder empty |
| `trips` | `Trips/trips-v1.json`, bookings found in email | folder emptied | folder empty |
| `trainingPlan` | `Sport/training-plan.json` | `TrainingPlanStore.delete()` | file read again: nothing kept |
| `studio` | Studio's topics and the items opened here (the items are also on Doddy's server) | `StudioModel.forgetLocal()` | no topics, no opened items |
| `workingFiles` | the temporary folder, `Library/Caches` (Studio's cache is here) and `Documents`: everything in them, whatever it is called, except iOS's own `com.apple.…` entries | folders emptied | folders empty |

Models that hold things in memory (the conversation list, the activity list, drafts, made files, the Messages screen, errands) are erased through their own code before the folder is swept, so one can't write its old state back; the folder check is on the file system, not on the model's word.

### The App Group folder (`DoddyAppGroup` in the Info.plists)

| Store | Holds | Erased by | Read back |
| --- | --- | --- | --- |
| `sharedContainer` | the widgets' snapshot (pinned notes, reminders, lists, parking spot), an item waiting from "Save to Doddy", the picture of the screen and its state | folder emptied (not `Library`, which iOS keeps) | folder empty |

The widgets read an empty snapshot afterwards (`WidgetSync` writes one with no notes, lists or reminders in it). No app-group preferences (`UserDefaults(suiteName:)`) are used.

### Preferences (`UserDefaults.standard`)

| Store | Holds | Erased by | Read back |
| --- | --- | --- | --- |
| `preferences` | settings and personal values kept as preferences: the parking spot, parcel numbers, delivery address, nickname, pinned and private note ids, shops, follows, Studio topics, consent records, counts | every key of the app's domain except the ones kept below (`DefaultsErasure`) | no erasable key left |

**Everything is erased unless `DevicePreferences` keeps it with a reason**, so a key nobody classified is erased, not leaked. iOS's own keys in the domain (`Apple…`, `NS…`, `com.apple.…`) are left alone. Kept on purpose:

| Reason | Keys | Why |
| --- | --- | --- |
| signed-in account | `doddyAccount.*` (how this iPhone uses each server for the account, whether Apple's sign-in was ended) | without them the app would treat a signed-in person as a device and start a new anonymous account on the server |
| server links | `deviceSession.expiresAt`, `voiceUserID` | they let the copies Doddy's servers hold for this iPhone be found and deleted with the account |
| install markers | `serverKeychainInstalled`, `assistantKeychainInstalled`, `accountKeysInstalled` | erased, the next launch would clear the Keychain and sign the person out |
| first-run flags | `welcomeSeen`, `firstRunAccessSeen`, `legalAcceptance`, `quickStartOffered`, `hadFirstConversation` | erased, the first-run screens and the Terms would cover the result of the erase the moment it finished |
| language | `appLanguage`, `appLanguage.polishDefaultApplied` | a display choice |
| development builds | `voiceTokenServer`, `connectedAppsServerURL`, `messagingServerURL`, `voiceAgentID`, `developer.directVoice`, `releaseScope.previewEverything`, `backTapSetupStatus` | endpoints and switches a shipped build ignores |
| deletion markers | `messages.conversationDeletedAt` (set to now by the erase), `recaps.links.v1` | files Doddy made before the conversation was deleted are not offered again; recaps of deleted conversations are not written |
| data owner | `localData.ownerAccountID` | cleared by the app only after every store was read back as empty (below) |
| privacy choices | `assistantConsent`, `logbook.on`, `rememberConversations`, `siriReadsNotes`, `widgetsShowContent`, `privacy.appLock`, `connections.pauseAll` | a switch that limits what Doddy shows, reads out, shares or sends keeps its position, so erasing can never loosen a choice (Ask Doddy, Logbook counts and remembered conversations are on unless turned off) |
| server copy switches | `memoryCopyOn`, `webMemory.notes`, `webMemory.conversations`, `logbook.serverOn`, `pushUpdatesOn`, `textsToDoddyOn` | on, the app's own sync makes the server copy as empty as the iPhone; turned off here, the copy would stay unreachable |

After the account was deleted and confirmed (`DeviceErasureScope.afterAccountDeleted`) the signed-in account, server links and server copy switches go too; markers, flags, language, development settings, deletion markers and privacy choices stay. The data owner is cleared by the app after a fully confirmed erase, and then the signed-in account (if any) takes the empty iPhone over (decision `2026-11-12-local-data-owner`). With anything unconfirmed the owner stays, so what is left is never handed to the next account.

### Keychain

Every item is a generic password under `com.bienos.doddy2.<name>`, marked "this device only" (not in backups, not synced; a test checks it). The plan lists what the Keychain holds for the app and decides per service (`DeviceKeychain`); a service the table doesn't know is erased.

| Service | Holds | Store | Erased |
| --- | --- | --- | --- |
| `com.bienos.doddy2.account-keys` | the inFakt API key the person pasted in | `keychainPersonalKeys` | always |
| `com.bienos.doddy2.gateway` | device id, invite code, token of the old assistant gateway (no build writes them) | `keychainPersonalKeys` | always |
| `com.bienos.doddy2.voice-access-code` | the old tester code (removed at launch) | `keychainPersonalKeys` | always |
| `com.bienos.doddy2.doddy-account` | the signed-in Doddy account's session | `keychainServerHandles` | with the account |
| `com.bienos.doddy2.voice-session` | the older voice account's session | `keychainServerHandles` | with the account |
| `com.bienos.doddy2.connected-apps` | the session token for Doddy's backend | `keychainServerHandles` | with the account |
| `com.bienos.doddy2.server` | the device token for the messaging server | `keychainServerHandles` | with the account |
| `com.bienos.doddy2.device` | this iPhone's device id, which mints backend sessions | `keychainServerHandles` | with the account |

**The default erase keeps the sign-in** (`DeviceErasureScope.keepSignIn`): the account stays signed in so that it can be deleted next (that deletion needs these items), and so that an account which finds another account's data on this iPhone can erase it and take the empty iPhone over. `keychainServerHandles` is then not part of the plan. Signing out and deleting the account are their own steps, offered right after the erase and with the account deletion. Items without a service name, other Keychain classes and other access groups: the app writes none.

### What iOS keeps for Doddy

| Store | Holds | Erased by | Read back |
| --- | --- | --- | --- |
| `notifications` | notifications waiting and delivered ones still in Notification Centre (note reminders, check-ins, leave-by, deal reminders, timers that are notifications) | remove all pending and delivered | both lists empty |
| `alarmsAndTimers` | AlarmKit alarms, timers and reminder rings Doddy set | each cancelled | AlarmKit's list read again; an unreadable list is never "nothing there" |
| `liveActivities` | the Voice, Call, Capture, Tool and Shopping Live Activities | each ended | none active |
| `spotlight` | Doddy's entries in iPhone search | `CSSearchableIndex.deleteAllSearchableItems` | iOS offers no read-back; the call finishing without an error is its confirmation |

### iCloud and servers

| Store | Holds | Erased by | Read back |
| --- | --- | --- | --- |
| `sharedListsInICloud` | lists shared through iCloud: the copy in the person's iCloud and the share with the people invited; lists joined from others (the person leaves) | `SharedListsController.stopEveryShare()` (each stop is read back from iCloud) | no share left on this iPhone |
| `memoryCopyOnServer` | "Memory on calls": the copy of the notes on Doddy's messaging server | an empty list is sent, as every change is | the server's own count is 0, or the switch is off, or this iPhone's notes were never sent to the signed-in account |

The only server step is this copy, because the person's own switch kept it equal to the iPhone's notes. Everything else Doddy's servers keep stays until the Doddy account is deleted: the Messages web copy, notes and conversations kept on the server, Logbook counts, Studio items, tasks and calls on the server (a finished task not yet acknowledged can come back to this iPhone when Doddy is opened), voice conversations at the provider, the messaging account. The erase says so.

## What is not Doddy's to erase from here

- What Doddy put into Apple's Calendar, Reminders, Contacts or Photos on request (those apps own it), and Health (Doddy reads it; iOS keeps the permission). Permission answers stay in iOS Settings.
- Copies the person made: exports, backup files, anything shared out, and older iPhone or iCloud backups.
- Things in memory of the running app that no store holds: the text of the conversation just ended and its "worth keeping?" cards stay on the voice screen until Doddy is closed (`VoiceSessionController` was not touched), and timers, stopwatch or focus sessions running in memory finish on their own. A new start of the app shows none of them.
- The Safari cookie jar and anything the system's sign-in sheets keep: Google's browser sign-in uses an ephemeral session (`SystemWebAuthenticator`), so it leaves nothing there.

## Backups (iPhone and iCloud)

One rule: **what the person saved to keep is in backups; what Doddy fetched, recorded or drafted for its own work is not.** Each store's rule is `DeviceStoreID.backup`, and a test reads the sources to see that a folder marked out of backups sets `isExcludedFromBackup` and one that is in doesn't.

- **In backups:** notes and lists and everything else in the notes database file (the Messages thread, recordings' words, calls, tasks and what Doddy learned live in the same SQLite file and can't be split without a new file, so they go with the notes: the Settings › Memories footer says "in your iPhone backups"), photos and voice memos on notes, files Doddy made (`MadeFiles`), and preferences (iOS always backs up the preferences file).
- **Out of backups:** the training log and plan (health data), recording audio, the invoice draft, the screen picture, and, from this change, `conversationTranscripts` (`Conversations`), `activityList` (`Activity`), `unfinishedNotes` (`Drafts`, which its own comment already said) and `trips` (`Trips`). The folder is marked, not the file, so a replaced file keeps the mark.
- **Not backed up by iOS anyway:** Caches, the temporary folder, Keychain items marked "this device only", the search index.
- Restoring an iPhone from a backup made before this change can bring those four back from the older backup; erasing doesn't touch backups.

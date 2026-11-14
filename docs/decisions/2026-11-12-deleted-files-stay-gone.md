# Files from before a reinstall or a deleted conversation don't come back, and a reinstall signs out

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026, after TestFlight: "Wylogowałem się z apki, usunąłem ją i zainstalowałem z powrotem z TestFlight, i wiadomości się usunęły, jakby pamiętało mojego iPhone'a: na ekranie logowania od razu, że jestem połączony. W wiadomościach losowo zostały pliki, ich nie powinno być. Jak klient usunie, my dalej je trzymamy, ale nie dajemy użytkownikowi z powrotem." ("I signed out, deleted the app and installed it again from TestFlight. The messages were gone, but it was as if it remembered my iPhone: the sign-in screen at once said I was connected. Files randomly stayed in Messages and shouldn't be there. When a customer deletes, we keep them, but we don't give them back to the user.")
- **Status:** applied in the pull request that adds this file
- **Replaces:** nothing; narrows what `ThreadAttachments` (Messages' file cards) and Files offer

## Why
- **Messages showed old files after a reinstall.** The thread's bubbles live on the iPhone and went with the app. The file cards, though, come from the server's list of the account's files (`GET /v1/web/documents`, kept a week, ADR-564). `ThreadAttachments.shown` offered every ready file the server still kept, so a fresh install showed files from the old conversation with nothing around them. The owner's screenshot shows three: "Darmowe atrakcje w Warszawie.docx", "Warszawa szybki przegląd.docx" and "Iława miasto nad Jeziorakiem.pptx".
- **The welcome remembered the account.** iOS keeps Keychain items after an app is deleted. The gateway, messaging-server, Connected Apps and account-key items are already cleared on a fresh install (`KeychainCredentialStore`, `ServerKeychainStore.clearLeftoversOnFreshInstall`, `AccountKeyStore`). The Doddy account's session (`com.bienos.doddy2.doddy-account`) and the voice account's session (`com.bienos.doddy2.voice-session`) were not. A reinstall therefore opened the welcome with the old account and "Continue".
  - Signing out of the Doddy account does delete its session (`DoddyAccountModel.forget`). This report either came from a sign-out somewhere else, such as the voice account, or from a reinstall alone.

## Decision
1. **Files are offered from a start moment.** On this iPhone, Messages' cards and the Files list show only the files Doddy made at or after the later of:
   - when this copy of the app was installed: the creation date of its Documents folder, which iOS makes at install and removes with the app, and an update keeps;
   - when the person last deleted the conversation: Messages › "Delete conversation", or Settings' delete-everything. Kept in UserDefaults as `messages.conversationDeletedAt`.

   The rule is `FilesShownSince` in DoddyCore. The server is not asked to delete or hide anything: it keeps each file until its own deletion date, as before. Files made on the iPhone in a voice conversation (`LocalMadeFilesStore`) follow the same start.
2. **A fresh install removes the Doddy account's and the voice account's sessions** left in the Keychain, in the same step and under the same rule as the other leftovers (`ServerKeychainStore.clearLeftoversOnFreshInstall`).
   - An install updating to this version keeps them: nobody is signed out by an update.
   - The device id (`com.bienos.doddy2.device`) stays. It is what the server knows this iPhone by, and changing it is a separate decision (see Consequences).

## Consequences
- **What the person sees:**
  - After a reinstall, the welcome asks to sign in.
  - After signing in again, Messages and Files start empty and fill only with what Doddy makes from then on.
  - After "Delete conversation", the cards of earlier files go too.
- **What the server keeps (DOD-11):** everything, for the same week; nothing more is stored and nothing is sent. Doddy Web (`/documents`) still lists the account's files, because the iPhone's start moment is not known to the server. If the owner wants the web to hide them as well, that is a server change, with its own decision.
- **Shared devices:** another person who installs the app on a phone where it was deleted no longer finds the last person signed in. The device id staying means the server still recognises the iPhone; a device id per install would need a decision on how existing data is linked to an account (open PR #383 changes linking).
- **No undo:** files hidden this way can't be shown again on this iPhone, though Doddy Web still lists them.

## Evidence
- DoddyCore: `FilesShownSinceTests` (6 tests: the start, hiding older server files, a file at the start, no start, files made on the iPhone, and the cards built from the visible list).
- App: `MessagesModelTests.testOnlyARealDeletionHidesTheFilesMadeUntilThen` (a refused deletion hides nothing; a real one records its moment). It runs on Linux through `scripts/test_messages_model.sh`, which now also copies `FilesShownSinceStore.swift`, and in Xcode as part of `DoddyTests`.
- Not compiled here: no Swift in this session. The hosted `swift` job is the first compile of the DoddyCore change and of `scripts/typecheck_app_logic.sh` with `FilesShownSinceStore.swift`; `ios-build` is the first build of the app files.
- Not run on a device: a reinstall from TestFlight, the welcome after it, Messages and Files after "Delete conversation".

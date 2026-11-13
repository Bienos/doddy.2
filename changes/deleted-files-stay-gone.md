iPhone (decision `2026-11-12-deleted-files-stay-gone`):
- **Files:** Messages' file cards and the Files list show only files Doddy made after this install and after the last "Delete conversation" (or Settings' delete-everything). Older files stay on the server until their own date but are not shown again on this iPhone (`FilesShownSince` in DoddyCore; Doddy Web still lists them).
- **Reinstall:** a fresh install also removes the Doddy account's and the voice account's sessions left in the Keychain, so the welcome asks to sign in again. An update signs nobody out. The device id stays.

Tests: `FilesShownSinceTests` (DoddyCore, 6) and `MessagesModelTests.testOnlyARealDeletionHidesTheFilesMadeUntilThen` (app; on Linux through `scripts/test_messages_model.sh`).
Ran: `scripts/ci.sh --only checks`. Not run: Swift (no toolchain here; the hosted `swift` job is the first compile of DoddyCore, these tests and the app-logic type-check), the app build (`ios-build`), anything on a device. No server change, no deploy.

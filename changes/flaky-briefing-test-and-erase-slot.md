# Two small fixes: a flaky test, and the messaging server's owed sign-out slot in the erase plan

- **Test:** `MorningCheckInTests.testAPrivateNotesWordsNeverReachTheBriefingOrThePrompt` and `CallsClientTests.testSnapshotRequestHasNoPrivateNote` built records with random ids and checked that the text "4417" was absent. A random id's hex digits can spell it, so they failed now and then. They use fixed ids now; every assertion is kept.
- **Erase plan:** `com.bienos.doddy2.server.pending-revocation` (the messaging server's owed sign-out, `ServerPendingRevocationStore`) is registered in `DeviceKeychain.services` as a server tie, like the voice and backend owed slots: kept by the default erase, erased with the account. Before, the plan erased it in every scope, so a sign-out still owed to the server could be dropped.
- **Inventory scan:** `DeviceStoreInventoryTests.testEveryKeychainServiceInTheSourcesIsClassified` now also matches service names with a dot after the first segment, so a slot like this one fails the test until it is registered.
- **Docs:** `docs/architecture/DEVICE_DATA_STORES.md` lists the service.
- **Not compiled:** no app file changed.

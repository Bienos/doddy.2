# Encrypted backup file status (ADR-222)
Date: 2026-10-10. Owner: "do all of them" (item 9), and "A file you keep (Recommended)": Doddy makes one passphrase-encrypted backup file; you save it to Files or iCloud Drive yourself and restore from it on a new phone. No new servers or accounts.

## What ships
**Settings › Encrypted backup**
- **Make a backup file:**
  - passphrase twice (at least 10 characters) and "Include photos" (on);
  - the file is locked, then **opened again with the same passphrase and compared** before the system "Save to Files" sheet appears;
  - "Saved as "Doddy backup 2026-10-10.doddybackup"" is shown only when that sheet reports success.
- **Restore from a backup file:**
  1. Choose the file and type the passphrase.
  2. A summary shows what would be added.
  3. Tap "Add to this iPhone". The receipt counts only what was read back:
     - notes and list items (`MemoryStore.restore`);
     - photos (`attachPhoto`, file and link read back);
     - reminders (scheduled through the usual coordinator, then found in the store);
     - About you answers (`ProfileStore.commit`).
- **Only adds, never overwrites.** Notes already here stay as they are, and their photos and reminders are not touched. The profile is restored only when this iPhone has none. Reminders that have passed are left out; repeating ones resume at their next occurrence.
- **What's in the file:**
  - the notes, lists and items exactly as the JSON export (`MemoryExport.json`);
  - photos;
  - time reminders (place reminders need that iPhone's location permission and stay behind);
  - About you answers by key.
  Personality, voice settings and conversation logs are not included.
- **Crypto:**
  - AES-256-GCM (CryptoKit).
  - The key comes from the passphrase, normalised to Unicode NFC, with PBKDF2-HMAC-SHA256: 600,000 rounds and a random 16-byte salt. It is built on CryptoKit's HMAC and checked against published vectors.
  - The header (format, version, KDF, rounds, salt, cipher) is authenticated, so changing it makes the file fail to open. Files asking for fewer than 100,000 rounds are refused.
  - The largest file is 200 MB; above that, the user is asked to make one without photos.
- **Privacy screen:** "What leaves this iPhone" has a row "Where you save a backup file".

## Voice memos in the file (ADR-234, 2026-10-11)
- **Make a backup file:** "Include voice memos" (on by default, like photos). Each note's recording goes in with its length and date.
- **Restore:** recordings come back only for notes the restore adds and only when their length is valid. Each one is written to a temporary file, then attached and read back like a new recording. The receipt counts only those read back.
- **Older backup files** have no recordings and still open (`testBackupsMadeBeforeVoiceMemosStillOpen`). The file format version is unchanged; the field is optional.
- **Not run on a device:** large recordings near the 200 MB file limit. If the file would be too large, the message now says to leave out photos or voice memos.

## Files
- **Core:** `EncryptedBackup.swift`, containing `BackupLimits`, `BackupContents`, `BackupError`, `EncryptedBackup` (encrypt, decrypt, PBKDF2) and `BackupRestorePlan`. `DataFlow.swift` has the backup row.
- **App:** `Features/Backup/BackupViews.swift`, containing `BackupSettingsSection`, `MakeBackupView`, `RestoreBackupView` and `BackupDocument`. Settings shows the section.
- **Package:** `swift-crypto` 3.15.1 (plus swift-asn1), linked **on Linux only** so CI tests the real AES-GCM and HMAC. The iPhone app uses Apple's CryptoKit. `DEPENDENCIES_AND_LICENSES.md` lists it.
- **CI:** on Linux the package tests now link with `-Xlinker --allow-shlib-undefined`. Swift 6.2.1's linker otherwise rejects `libswiftObservation.so`'s own undefined `swift::threading::fatal` once swift-crypto's C code is in the link. The flag is in `scripts/ci.sh`, `scripts/typecheck_app_logic.sh`, the `Makefile` and `BUILD_AND_TEST.md`.
- **Tests:** `EncryptedBackupTests` (5).

## Verified (Linux, Swift 6.2.1)
- 450 package tests pass. `EncryptedBackupTests` covers:
  - three published PBKDF2-HMAC-SHA256 vectors (1, 2 and 4,096 rounds);
  - the round trip, with nothing readable in the file;
  - NFC passphrases;
  - wrong passphrase;
  - short passphrase;
  - a low-round file refused by default;
  - a changed header, a flipped ciphertext bit and a newer version all refused;
  - a plain export refused;
  - the add-only plan on a fresh iPhone and on one that already has the note;
  - place reminders left out.
- `swiftc -parse` on `BackupViews.swift` and `SettingsView.swift`.

## NOT RUN / UNVERIFIED
- No Xcode build. No backup was made, saved to Files or iCloud Drive, or restored on a device.
- 600,000 rounds on an iPhone: the time to derive the key is not measured. It runs off the main thread.
- A large photo backup uses memory for the whole file twice: not measured.
- The restore receipt's reminder count depends on iOS notification permission. Without it, reminders are kept in the app only, as usual.

## Decisions for the owner
- Personality, voice and language settings in the file: owner undecided (ADR-224); left out, the profile export already has them.
- A passphrase hint, or a "check my passphrase" step, would need careful wording (DOD-11). Not built.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | The file is reopened and compared before saving; "Saved as" only on the sheet's success; restore counts only read-back writes | `testRoundTripAndWrongPassphrase`, `testRestoreOnlyAdds` | UI path not compiled |
| DOD-11 observable_privacy | No server, no account, passphrase never stored; the file can't be read without it; privacy row | `testRoundTripAndWrongPassphrase` (no plaintext in the file) | iCloud Drive keeps the file wherever the user saves it, encrypted |
| DOD-06 user_controlled_relevant_memory / DOD-09 correction_and_recovery | Restore adds only; never overwrites a note, photo, reminder or profile | `testRestoreOnlyAdds` | — |
| DOD-07 scoped_action_approval | A summary first; nothing is written until "Add to this iPhone" | — | — |

Don't claim: "military-grade", "unbreakable", "backed up automatically", or "tested on a device". A weak passphrase is still a weak passphrase.

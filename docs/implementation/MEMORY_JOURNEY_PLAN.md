# Approved memory journey — implementation scope, 10 October 2026

Owner request: “build”, following the nine-screen memory-journey mockup. This is a
local native UI/utility slice in `Bienos/doddy.2`, not a change to the older repository.
The working tree already contains native baseline work; preserve it. A before-change
source snapshot is in `outputs/Doddy-Memory-Journey-Build/native-before-memory-design.tar.gz`
in the parent workspace. No commit, push, merge, provider usage or release is authorized.

## Plan

1. Use the owner-selected cream/ink/orange appearance and numbered ZIP artwork.
   Add sibling native image sets; preserve older asset sets and reference packs.
2. Keep SQLite and the existing MemoryStore. Build Home, capture/committed receipt,
   browse/find with source links and honest miss, edit/original/delete, privacy summary.
   Use native Dynamic Type, dark appearance, character hiding and 44-point targets.
3. Keep existing voice/shortcut/Island controllers and provider disclosures. Do not
   add static Listening or simulated Island artwork to production UI. Do not run voice.
4. Build the app/widget, run package and native tests, and run isolated synthetic
   save → restart → find → edit → original → delete → restart UI checks.

## Safety and completion evidence

No new data store, migrations, accounts, permission requests or networking. No seeded
personal sample notes. Confirm only repository-acknowledged writes; retain failed drafts.
Use a separate simulator bundle and UUID-scoped test databases. Preserve the existing
red Island system-Unmute test as a known separate issue, not an all-green release claim.
Physical iPhone data protection, voice, TestFlight and production release remain untested.

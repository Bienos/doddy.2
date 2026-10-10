# Native simulator evidence — 10 October 2026

Unmodified screenshots from the verified Doddy memory journey, not browser mockups
or physical-device proof. All note text is explicitly synthetic and comes from
UUID-scoped test storage. Home uses an empty in-memory store.

- `home.jpg`: final standalone build/run, isolated bundle
  `com.bienos.doddy2.memoryjourney`, iPhone 18 Pro / iOS 27 simulator.
- `saved.png`, `find.png`, `detail.png`: retained screenshot attachments from
  `MemoryJourneyTests/testApprovedJourneyCorrectionRetainsOriginalAfterRestart`.
- `accessibility.png`: retained attachment from
  `MemoryJourneyTests/testDarkLargestTextKeepsTextRoutesUsable`.

Final scoped native suite passed 19/19; the separate known-failing Island system
Unmute scenario was excluded, not fixed or signed off. Package tests passed 51/51.
See [the implementation report](../../MEMORY_JOURNEY_REPORT.md) for exact result
bundle/log paths, changed files, earlier failures, limitations and next device checks.

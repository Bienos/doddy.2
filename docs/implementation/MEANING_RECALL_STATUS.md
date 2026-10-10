# Find by meaning — status

Date: 2026-10-10. Owner request: "build meaning-based recall first". Decision: `DECISIONS.md` ADR-228.

## What the user gets
| Where | Behaviour |
|---|---|
| Memories → Find | Word matches exactly as before. Below them, a **MAYBE RELATED** group: up to 3 notes that don't share the question's words but seem to be about the same thing, each marked "Related by meaning, not your words". If no note uses the words, the screen says "NO NOTE USES THESE WORDS" first. Each card opens the stored note |
| Voice (`search_memories`) | The reply to the agent lists word matches as "Found N saved notes" (unchanged), then meaning matches under a separate heading telling the agent to use one only if it clearly answers the question, to say it *might* be what the user means, and otherwise to say it found nothing. Meaning matches are never counted as found notes and never get "[may disagree]" |
| Ask Doddy (typed) | Unchanged. Meaning matches are never sent to the gateway (`GroundingSelector` takes word matches only), so this adds no data leaving the phone |
| Settings → Your memories | **Find by meaning** switch, on unless turned off. Off deletes every stored vector at once; notes are untouched. Greyed out with an explanation when the iPhone has no suitable model |
| Settings → What leaves this iPhone | New "stays on this iPhone" line for find by meaning |

## How it works
1. Word search runs first (`RepositoryRecallService`, unchanged).
2. If find by meaning is on, `MeaningIndex` makes sure every note has a vector of its **current** text (first
   1,000 characters). New or corrected notes are embedded, newest first, at most 200 per search; vectors are cached in
   the SQLite file (`memory_vectors`, migration `v5_memory_vectors`).
3. The question is embedded. Every note is scored by cosine similarity after subtracting the notes' average vector
   (general sentence vectors all point roughly the same way; centring removes that).
4. A note is offered only if it **stands out**: at least 1.5 standard deviations above the average note's score and
   at least 0.2 in absolute terms, at most 3, never one word search already found. With fewer than 8 notes, or a
   question of only filler words ("what was that?"), nothing is offered.
5. Any meaning-search failure (model missing, store unreadable) silently leaves word search's answer as it was.

Model: Apple `NLContextualEmbedding` for the Latin script (iOS 17+), one model for Polish and English, token vectors
averaged (`DoddyApp/Infrastructure/OnDeviceMeaningEmbedder.swift`). The model id and revision are stored with each
vector; a new model re-embeds everything instead of comparing different spaces.

## Privacy and deletion
- Note text is processed on the iPhone only. If iOS hasn't downloaded the model, the app asks iOS for it once
  (`requestAssets`): a download of the model from Apple; no note text is sent. A new guard rule keeps
  NaturalLanguage code in that one file.
- Vectors reference their note (`ON DELETE CASCADE`, `secure_delete` on): deleting a note or all notes deletes them.
  Correcting a note deletes its old vector in the same transaction. Turning the switch off deletes them all.
- Vectors are derived data: not in JSON/text/Markdown export, not restored, rebuilt on demand.
- Constitution DOD-06 ("don't surface unrelated memories"): the relative threshold, the cap of 3, the "may be related"
  wording on screen and to the agent, and the agent instruction to ignore notes that don't answer are the safeguards.
  They are **not yet measured** with the real model (see below).

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/MeaningRecall.swift` | `TextEmbedder`, `MemoryVectorStore`, `MeaningPolicy`, `MeaningRanking` (pure maths and rules), `MeaningIndex` (actor), `HybridRecallService` |
| `…/DoddyCore/Ports.swift` | `MemoryCandidate.meaningScore`, `isMeaningMatch` |
| `…/DoddyCore/VoiceTools.swift` | `VoiceToolReply.search` keeps meaning matches apart |
| `…/DoddyPersistence/SQLiteMemoryVectorStore.swift`, `DoddyDatabase.swift` (`v5_memory_vectors`), `SQLiteMemoryRepository.update` | Vector cache |
| `DoddyApp/Infrastructure/OnDeviceMeaningEmbedder.swift` | Apple model adapter |
| `DoddyApp/Infrastructure/AppEnvironment.swift`, `MemoryStore.swift` | Wiring; UI-test launches keep word search only |
| `DoddyApp/Features/Memories/FindMemoriesView.swift`, `DesignSystem/MemoryJourneyComponents.swift`, `Features/Settings/SettingsView.swift` | Screens |
| `DoddyTests/MeaningSearchCalibrationTests.swift` | Real-model calibration (Mac/iPhone only) |

## Verified (Linux, Swift 6.1.2)
- `scripts/ci.sh --core-only`: PASS for core-only scope; 402 DoddyCore package tests, 0 failures (375 before);
  new: `MeaningRecallTests` (19), `SQLiteMemoryVectorStoreTests` (7), one `VoiceToolsTests`, one `DataFlowTests` line.
  They use a **stand-in embedder** (word → topic counts), so they prove the plumbing, caching, deletion, thresholds,
  fallbacks and wording, **not** that Apple's model finds the right notes.
- `scripts/typecheck_app_logic.sh` (MemoryStore with the new member): PASS.
- `scripts/check_forbidden_capabilities.sh`: PASS, and FAIL when `import NaturalLanguage` was added to another file.

## Not verified (needs the Mac and an iPhone)
- **App compile**: `OnDeviceMeaningEmbedder` (NaturalLanguage API names, Swift 6 sendability of
  `NLContextualEmbedding` inside an actor, `requestAssets` callback), the Find and Settings screens.
- **Quality**: whether Apple's model ranks the right note first, in Polish and English and across them. The
  thresholds (1.5 SD, 0.2, 8 notes) are reasoned defaults, not measured. Run `MeaningSearchCalibrationTests` and
  checklist M12–M16 in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`; adjust `MeaningPolicy.standard` from the results.
- **Speed**: time to embed 200 notes on a real iPhone, and the model's behaviour with long notes (the adapter retries
  with the first 300 characters if the model refuses a long text).
- **Voice**: that the live agent follows the "may be related" wording. The tool reply carries the instruction, so no
  agent prompt change was made and nothing was synced to ElevenLabs.

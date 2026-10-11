# Find by meaning status (ADR-227)
Date: 2026-10-10. Owner: "do all of them" (item 4).

## What ships
- **Memories › Find gains a "Close in meaning" section** under the word results. It shows up to 5 saved notes the word search didn't find, whose meaning is close to what was typed. For example, "the place with good pierogi" can find "Zapiecek, great dumplings". The section says "Not the same words. Check it's the one you meant."
- **On this iPhone only.** Vectors come from Apple's contextual embedding model (`NLContextualEmbedding`): one model per writing system, averaged over the words.
  - The model may be downloaded from Apple once. No note or question text is sent anywhere.
  - Vectors are kept in memory only, never on disk, and recomputed when a note's words change.
- **Never an answer.** Only saved notes are ranked: no lists, no sample notes. A note must be at least 0.5 similar and stand 0.08 above the average of all notes, because these vectors sit close together even for unrelated text.
- Voice search (`search_memories`) is unchanged and still word-based.

## Files
- **Core:** `MeaningSearch.swift`, containing `MeaningEmbedder`, `MeaningSearch` (cosine, eligibility and ranking) and the `MeaningIndex` actor.
- **App:**
  - `Features/Meaning/OnDeviceEmbedder.swift`: the embedder and `MeaningService.index`;
  - `FindMemoriesView`: the `MeaningHitsView` section.
- **Guard:** `import NaturalLanguage` and the embedding classes are allowed only in `Features/Meaning`.
- **Tests:** `MeaningSearchTests` (5), using a fake embedder.

## Verified (Linux)
- `MeaningSearchTests` pass. They cover:
  - cosine, including vectors of different sizes;
  - the close note found and unrelated ones left out;
  - lists, samples and word-search hits excluded;
  - short or unreadable questions;
  - at most 5 hits.
- `swiftc -parse` on the embedder and Find. The capability guard passes.

## NOT RUN / UNVERIFIED
- No Xcode build. The `NLContextualEmbedding` API use (`requestAssets`, `embeddingResult`, `enumerateTokenVectors`) has not been compiled.
- **The thresholds are guesses.** Real similarity values from the model have never been seen. Tune `minimumSimilarity` and `marginOverAverage` on a device with real notes.
- Unchecked: speed with hundreds of notes (the first search embeds every note), and matching across Polish and English.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-06 user_controlled_relevant_memory / DOD-02 honesty | Only saved notes; labelled as a suggestion, never an answer | `testListsSamplesAndWordHitsAreLeftOut`, `testCloseInMeaningIsFoundAndUnrelatedIsNot` | Thresholds untuned |
| DOD-11 observable_privacy | On-device model; vectors in memory only; guard keeps NaturalLanguage in one folder | guard PASS | One-time model download from Apple |

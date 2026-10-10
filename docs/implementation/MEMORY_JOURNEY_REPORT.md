# Native Doddy memory journey — 10 October 2026

## Implemented

Local changes in `Bienos/doddy.2`, branch `codex/doddy2-native-baseline`, on top of
existing native baseline work. **Not** the old `Bienos/AI-AGENT-DODDY`. At completion
of build verification no commit, push, merge, live-provider session or release had
been performed. The owner subsequently requested "push to github": this authorizes
committing and pushing the tested slice and its supporting baseline changes to
`codex/doddy2-native-baseline`. It does not authorize merging, a public release or
paid voice usage; delivery is recorded in that branch's Git history.

The owner-selected cream/ink/orange design is now SwiftUI, using only five original
PNG drawings from the numbered ZIP. Home, capture, a repository-confirmed saved
receipt, saved-note browsing, local word search with source links, an honest no-match,
current/original note detail, correction, deletion and privacy summary are connected
to the existing local SQLite store. Production screens contain no seeded example notes.
All screenshots/tests use explicitly synthetic notes in isolated stores.

The existing storage, voice, shortcut and Island controllers are preserved. Voice
still has its separate provider behaviour: saved notes and recent conversation context
can be sent to ElevenLabs when a voice conversation is opened. The new local memory
interface does not make the overall voice app offline or device-only.

Native layout skills influenced the implementation: reusable paper/character/heading
components, model-driven capture sheets, one typed search/detail navigation path,
native text sizing and scrollable recovery states. Content follows full Dynamic Type;
the decorative wordmark and compact navigation labels are capped at XX Large to avoid
an inaccessible oversized bottom bar. Artwork can be hidden and adds no motion.

## Files changed for this slice

- `DoddyApp/App/RootView.swift`: approved pill navigation and Home-to-find request.
- `DoddyApp/DesignSystem/Theme.swift`, `Components.swift`, new
  `MemoryJourneyComponents.swift`: palette, original artwork, paper cards, source links.
- `DoddyApp/Features/Home/HomeView.swift` and `Capture/CaptureView.swift`:
  approved layout, real save receipt, duplicate-save guards, discard confirmation,
  failed draft retention and disabled editing/dismissal while saving.
- `DoddyApp/Features/Memories/MemoriesView.swift`, new `FindMemoriesView.swift`,
  `MemoryDetailView.swift`, `CorrectionView.swift`: native browsing, cancellation-safe
  debounced recall, source detail, correction/original and confirmed deletion.
- `DoddyApp/Features/Settings/SettingsView.swift`: privacy introduction, uploaded art
  and honest development-build status; existing export and provider disclosures remain.
- Five sibling `UploadedDoddy_*.imageset` sets; old images remain intact. See
  [exact ZIP paths and verified hashes](../design/UPLOADED_MEMORY_ASSETS.md).
- New `Packages/DoddyCore/Sources/DoddyDesignTokens/UploadedTokens.swift` and
  `Tests/DoddyDesignTokensTests/UploadedTokensTests.swift`: owner palette and readable
  text contrast on both paper surfaces in light/dark appearance.
- `DoddyUITests/LaunchSmokeTests.swift`, `MemoryBaselineTests.swift`, new
  `MemoryJourneyTests.swift`: native routes, real synthetic persistence and accessibility.
- `docs/design/CANONICAL_DESIGN_DIRECTION.md`, `UPLOADED_MEMORY_ASSETS.md`,
  `docs/implementation/MEMORY_JOURNEY_PLAN.md` and this report.

The working tree was already dirty. Existing `AppEnvironment`, `MemoryStore`,
`VoiceSessionController`, Shared Island, project configuration and baseline tests are
not new implementation claims. MemoryStore, VoiceSessionController, AppEnvironment,
Shared VoiceActivity attributes and project.yml were compared by SHA-256 against
the before-change archive; all five are unchanged by this slice.
Project generation/SwiftPM resolution may touch generated or resolver state.

## Verification environment and safety

Xcode 27.0 (`27A266a`), Swift 6.4, iPhone 18 Pro simulator / iOS 27.0,
simulator ID `C8DAE58A-37B0-4960-AB5A-BB03BEA50514`.
App/widget builds use unsigned simulator configuration.

Separate simulator app bundle: `com.bienos.doddy2.memoryjourney`. Persistent UI
tests use a fresh UUID `-memoryTestID`; other smoke tests use `-inMemoryStore`.
No test reads or deletes the owner's personal memory database. No microphone or
paid voice session was opened. Synced `sources/`, the older repository and supplied
archives were not edited. A pre-change source snapshot is saved in the parent
workspace at `outputs/Doddy-Memory-Journey-Build/native-before-memory-design.tar.gz`.

## Tests executed — final scoped rerun passed

| Check | Executed result |
| --- | --- |
| XcodeGen project generation | PASS |
| Native app and widget simulator build/install/launch | PASS |
| Swift package core, design and SQLite tests | 51 PASS, 0 failures (40 + 9 + 2) |
| Native unit tests | 11 PASS, 0 failures |
| Full updated UI suite | 8 PASS, 0 failures |
| Exact ZIP-to-native artwork hashes | 5/5 identical |
| `git diff --check` | PASS |
| Physical iPhone, VoiceOver, microphone/provider, TestFlight/release | NOT RUN |
| Known Island system-Unmute UI scenario | Excluded from this slice; previously red |

Package command:

```sh
swift test --package-path Packages/DoddyCore --scratch-path /private/tmp/doddy-memory-journey-core
```

The first sandboxed package attempt could not write Swift cache files; an approved
rerun completed all 51 tests. That initial infrastructure failure was not a failed
assertion. Native build/test ran via the configured Apple-platform build tool with
`DODDY_APP_BUNDLE_IDENTIFIER=com.bienos.doddy2.memoryjourney`,
`CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled NO`. Full suite excludes only
`DoddyUITests/MemoryBaselineTests/testNativeIslandOfflineFixtureCanStartMuteAndEnd`.

Final native suite: **19 passed, 0 failed** (11 unit + 8 UI), tool duration 277.2s.
Native tests used the actual UI and SQLite fixture: typed capture → committed receipt
→ receipt-to-detail → browse-to-detail → app restart → source-linked find → replace
text through native Select All → view exact original → restart and recheck correction
→ confirm deletion → no match → restart and empty store. Empty save never showed a
saved receipt. Dark appearance at Accessibility XXXL kept save/find/capture routes
usable; Back Tap defer/status and onboarding/tab smoke checks also passed.

Result bundle:

`/Users/popcorn/Library/Developer/XcodeBuildMCP/workspaces/g-p-6ac752264c9481919b0862f0903c0b9b-94afa6898ead/result-bundles/test_sim_2026-10-10T09-12-21-535Z_pid96286_5636204b.xcresult`

Native log:

`/Users/popcorn/Library/Developer/XcodeBuildMCP/workspaces/g-p-6ac752264c9481919b0862f0903c0b9b-94afa6898ead/logs/test_sim_2026-10-10T09-12-21-535Z_pid96286_e1f8eb7b.log`

Native screenshots were exported to the parent workspace's
`outputs/Doddy-Memory-Journey-Build/final-test-attachments/`, with a manifest mapping
each screenshot to the actual test. These are simulator captures, not browser mockups.

Final standalone build/install/launch also passed (26.7s), with the isolated app left
on light Home using an empty in-memory store and no voice agent launch. Build log:

`/Users/popcorn/Library/Developer/XcodeBuildMCP/workspaces/g-p-6ac752264c9481919b0862f0903c0b9b-94afa6898ead/logs/build_run_sim_2026-10-10T09-17-18-055Z_pid96286_ef765151.log`

Viewed native captures, copied unchanged into the repository for GitHub review:

- [Home](evidence/memory-journey/home.jpg)
- [Committed save receipt](evidence/memory-journey/saved.png)
- [Source-linked find](evidence/memory-journey/find.png)
- [Correction and immutable original](evidence/memory-journey/detail.png)
- [Dark accessibility-size capture](evidence/memory-journey/accessibility.png)

### Issues caught during verification

The first full native run passed all 11 unit tests and 5/8 UI tests, with three UI
failures. Do not erase these results or call the whole product fully verified.

- Search-result navigation reset the search instead of opening detail. Adding a
  local destination registration did not fix it. Using one typed path for search
  and note detail did; the next native run reached correction successfully.
- The Back Tap "Later" test tapped a partially visible button behind the pill bar.
  The harness now scrolls the whole button above navigation and waits for removal;
  the focused native Back Tap defer/status check passed. This does not verify an
  actual physical Back Tap trigger.
- The correction harness assumed the caret was at the end of TextEditor. It was at
  the start, so deletion did nothing and the result contained both texts. The harness
  now explicitly uses native Select All before typing; replacement then passed.
- A DisclosureGroup identifier propagated into its child Text, masking the original
  text's own identifier. The original wording was visible and correct in the native
  hierarchy; removing the parent identifier gives the original text its own stable ID.
- At the largest text size the harness reported an off-screen Home Save action as
  hittable. Home now selects one native action stack explicitly rather than building
  alternative copies in ViewThatFits. Test taps bring the complete button above
  navigation. The updated dark/accessibility-size native test passed.
- The next journey run confirmed replacement text and immutable original wording,
  including correction after a restart, but the final Delete tap hit navigation.
  Native hierarchy showed the last action behind the custom pill bar. The bar is now
  a sibling that reserves real viewport height instead of a TabView-level safe-area
  inset. The final all-scoped-test rerun passed, including confirmed deletion and
  an empty store after restart. Earlier failing runs are retained for traceability.
- Native keyboard presentation emitted an `Invalid frame dimension` warning in
  the UI runner. No assertion has established its cause; record it rather than
  claim a warning-free build. Apple's simulator also logged accessibility-bundle
  duplicate-class and debugger-version warnings.

## Known risks and owner decisions

This is a simulator-built local development slice, not a live service, signed device
build, TestFlight build or App Store release. The existing development app icon is
unchanged. Broader onboarding/voice visuals and animations were not reworked here.
Lexical recall finds saved words, not semantic AI answers or inferred personal facts.
The privacy Settings screen documents existing voice-provider sharing; changing its
consent/retention design needs a separate decision before public use.

No further owner decision is needed to review the local text-memory slice. Starting
paid live voice, changing provider/data sharing, enabling reminder permissions,
publishing or merging remains outside this approval.

## Next task

Review the native screenshots and run this text-memory journey on the owner's iPhone
with throwaway notes. Then address the existing Island Unmute issue and separately
agree the voice/provider-consent test scope. Do not start reminders or cloud accounts
as part of this slice.

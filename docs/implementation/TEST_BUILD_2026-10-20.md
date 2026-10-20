# Test build of 20 Oct 2026: today's open PRs together

Branch `claude/wizardly-cannon-k0u1mv`. **For testing on the owner's iPhone only. Don't merge this branch into main.** Merge the PRs one at a time, as `STATUS.md` says, and carry the three fixes below into whichever PR merges second.

## What it holds
On top of main at `f3bd10d6` (#106, the calm Home), merged in this order:

| PR | Branch | What |
|---|---|---|
| #108 | `claude/friendly-volta-3recsi` | ElevenLabs default voice, smaller app, start-up after the first screen, "What I can do" back, old design deleted, Hey Doddy and Picovoice removed, breathing removed, Debug builds talk without Apple sign-in (ADR-546 to 551 on that branch) |
| #111 (draft) | `claude/gracious-ptolemy-mybt3a` | Motion v2 on the calm Home: one persistent Doddy (includes #107's MV1 to MV6) |
| #110 | `claude/nice-shannon-9gxk6s` | Brand Guidelines V2.2: app icon, orange `#FF6A00`, how Doddy speaks, "Working on it…", "Doddy" casing |
| #112 | `claude/optimistic-mendel-df84oe` | Ways to open Doddy, one-screen Back Tap, card return, weekly reminder |
| #113 | `claude/zen-noether-nykqbb` | Calls by Doddy until 23:00 Warsaw time |
| — | `claude/ecstatic-allen-ptjm3u` | Docs only: the live agent runs Eleven Realtime Max |
| — | `claude/busy-volta-qgwgz3`, two commits only | `project-iphone.yml`: no entitlements (a free Personal team can sign it) and no generated string symbols |

**Left out:**
- #109 (Doddy's eyes): the owner chose motion v2 for this build. With motion v2 on, the eyes never show on an iPhone.
- #107: #111 replaces it.
- `claude/motion-mv7`: #109 replaces its eyes.
- `claude/sweet-newton-2z7asj`: no PR and never compiled. Its breathing removal duplicates #108.
- `claude/busy-volta-qgwgz3`'s three voice commits: #108's Debug switch (ADR-551) does the same job.

## Fixes made while merging (carry them over)
1. **#108 × #111:** `RootView` no longer reads `WakeWordListener` for motion v2's listening pose. Hey Doddy is gone, and the voice screen hides him.
2. **#108 × #111:** Home's "What I can do" sheet hides the persistent Doddy, like Home's other sheets.
3. **#108 × #112 (compile error without it):** `PreferenceKey.connectedConversations` and the counter in `VoiceSessionController` are kept. #108 removed them with the Hey Doddy card, but #112's card return and reminder use them.

Also: the `WakeGreeting` text changes from #110 were moved from the deleted `WakeWord.swift` into `WakeGreeting.swift` and its tests. The microphone prompt is #108's text after #110's first sentence, in all ten languages. `DECISIONS.md` keeps every PR's rows, so ADR-546 to 551 appear twice. Renumber them when the PRs merge.

## Checks run here (Linux, Swift 6.1.2)
- `scripts/ci.sh --core-only` on the merged tree: **PASS** for every step (DoddyCore 1,244 tests, 0 failures; app-logic type-check of 25 files; string catalogs; capability guard; agent specs; token server, backend, gateway, messaging server and site tests; secrets manifest).
- **SKIPPED:** the messaging server's database tests (no `TEST_DATABASE_URL`).
- Every Swift file in `DoddyApp`, `Shared`, `DoddyWidgets`, `DoddyShare`, `DoddyWatch`, `DoddyTests` and `DoddyUITests` passed `swiftc -parse`. **NOT RUN: the iOS build, the app unit tests and the UI tests** (no Xcode in the session). The owner's Xcode build is the first compile of this combination.

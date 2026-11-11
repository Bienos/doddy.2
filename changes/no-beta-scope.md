Every feature is shown in every build: `ReleaseScope.shipping` is `.everything` (owner, 10 Nov 2026: "forget the beta"); the hide mechanism and its tests stay, the ~40-feature hidden list, the Debug toggle and owner queue row 22 are gone.
Decision `docs/decisions/2026-11-10-no-beta-scope.md` (costs, caps, what to watch). The live agent and servers are untouched; no deploy needed.
Ran: DoddyCore tests, scripts/ci.sh --only swift,checks, strings catalog check on Linux. Not compiled: SwiftUI, DoddyTests, DoddyUITests (no Xcode).

# Every build shows every feature until the beta

- **Date:** 2026-11-08
- **Decided by:** owner, 8 Nov 2026: "nie ukrywaj nic, wersja beta bedzie pozniej" ("don't hide anything, the beta comes later")
- **Status:** applied in this pull request, once merged
- **Replaces:** the Release/TestFlight part of `2026-11-07-release-scope` and `2026-11-08-debug-shows-every-feature`

## Decision
`ReleaseScopeStore.current` returns `ReleaseScope.everything` in Release and TestFlight builds too. `ReleaseScope.shipping` and its tests stay, unused, for the beta.

## Consequences
- The 44 hidden features and their voice tools show in every build. The voice agent still decides which tools it offers: the 67 tools of owner queue 22 are only gone from the app's side.
- To bring the beta back: return `.shipping` in the non-Debug branch.

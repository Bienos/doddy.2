# A Debug build shows every feature until its switch is turned off

- **Date:** 2026-11-08
- **Decided by:** owner, 8 Nov 2026: "zrób opcję 2, Debug ma domyślnie pokazywać wszystko" ("do option 2, Debug shows everything by default"), after a build run from Xcode showed half of Home's menu missing
- **Status:** applied in the pull request from `claude/beautiful-tesla-s79cm7`, once merged
- **Replaces:** part of `2026-11-07-release-scope`: there a Debug build showed the beta scope until the switch was turned on

## Why
After `2026-11-07-release-scope` (#221) every build, Debug included, hid 44 of 46 features. The owner ran the app from Xcode, saw Translate, Tasks, Voice, Cheapest this week, Following and Files gone from Home, and took it for a regression. The switch that shows them existed, but was off on a fresh install and three screens deep.

## Decision
- A **Debug** build shows `ReleaseScope.everything` unless `releaseScope.previewEverything` is set to false. Never set counts as on (`ReleaseScope.debugShowsEverythingByDefault`, `ReleaseScope.debug(showEverything:)`).
- Settings › About › Advanced › "Developer: show every feature" starts on in a Debug build; turning it off shows what the beta ships.
- A **Release** or TestFlight build is unchanged: always `ReleaseScope.shipping`, and it never reads the switch.

## Consequences
- Running from Xcode shows the whole app again. To see what testers get, turn the switch off, or archive a Release build.
- A Debug build where the switch was turned off before keeps it off: the stored false still wins.
- Tests that set the key keep working: the voice controller's harness and the UI tests set it explicitly.

## Evidence
See the pull request: DoddyCore `ReleaseScopeTests` (one new test for the default) and the app-logic type check run on Linux; the SwiftUI change was not compiled here.

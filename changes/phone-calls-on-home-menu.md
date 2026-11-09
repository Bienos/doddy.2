Phone calls are on Home's ••• menu (decision `2026-11-09-phone-calls-on-home-menu`). The new row "Phone calls" (`home.calls`, Polish "Rozmowy telefoniczne") opens the existing Settings › Notifications › Phone calls screen in a sheet with Done (`HomeCallsSheet` in `HomeView.swift`). Calls for you is a row on that screen, and the screen says itself when the server or the phone line isn't set up. The Settings entry stays.

To keep the menu at eleven rows (ADR-652), "What leaves this iPhone" left the menu; it stays on Settings › Privacy. "What I can do" stays on the menu, and its descriptions get rewritten in a later pull request.

Visibility: the row follows the release scope. `phoneCalls` is hidden in `ReleaseScope.shipping`, so TestFlight and Release builds don't show it; Debug builds do.

Tests: new UI test `LaunchSmokeTests.testPhoneCallsOpenFromTheHomeMenu`. `testFirstVisitHomeKeepsToTalkingAndShowsWhatICanDo` (was `…AndLinksToPrivacy`) now opens What I can do from the menu and checks the privacy row is gone from it; `testWhatLeavesThisIPhoneFollowsSettings` still opens the privacy screen from Settings. The screen atlas's `2-home-15` is now Phone calls. Not compiled or run here (no Xcode); the hosted Mac job is the check.

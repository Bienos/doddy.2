Phone calls are on Home's ••• menu (owner, 9 Nov 2026: "I want it on Home, the three dots"). The new row "Phone calls" (`home.calls`, Polish "Rozmowy telefoniczne") opens the existing Settings › Notifications › Phone calls screen in a sheet with Done (`HomeCallsSheet` in `HomeView.swift`); Calls for you is a row on that screen, and the screen says itself when the server or the phone line isn't set up. The Settings entry stays.

The menu fits eleven rows (ADR-652), so "Cheapest this week" and "Following" now share one row, "Leaflets and news" (`home.feeds`, "Gazetki i wiadomości"), with the two as its items. The UI tests that open leaflets go through `home.feeds` first.

Visibility: the row follows the release scope. `phoneCalls` is hidden in `ReleaseScope.shipping`, so TestFlight and Release builds don't show it until the owner takes it out of the hidden list; Debug builds show it.

Tests: new UI test `LaunchSmokeTests.testPhoneCallsOpenFromTheHomeMenu` (opens the row, closes it, then checks the menu still reaches What leaves this iPhone). Not compiled or run here (no Xcode); the hosted Mac job is the check.

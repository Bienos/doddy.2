# Phone calls are on Home's ••• menu; What leaves this iPhone is on Settings › Privacy only

- **Date:** 2026-11-09
- **Decided by:** owner, in the session that opened #270: "I want it on Home (the three dots)", then, when asked which row should leave the menu, chose "What leaves this iPhone" (it stays in Settings), with "What I can do" kept on Home and described better in a later pull request, following the brand guidelines.
- **Status:** applied in #270
- **Replaces:** ADR-326 in part (Home linked to What leaves this iPhone)

## Why
Phone calls were only reachable from Settings › Notifications › Phone calls, and the owner wants them easy to find. Home's ••• menu fits eleven rows at the default text size (ADR-652), and a twelfth row put its last rows out of reach in the hosted UI tests, so one row had to go.

## Decision
- Home › ••• has a **Phone calls** row (`home.calls`) that opens the existing Phone calls screen in a sheet with Done. It follows the release scope: `phoneCalls` is hidden in `ReleaseScope.shipping`, so beta builds don't show it.
- **What leaves this iPhone** leaves Home's menu. It stays on Settings › Privacy, where it has been since ADR-580, and What I can do still points to it.
- **What I can do** stays on Home's menu. Its descriptions get rewritten in a separate pull request, in the voice of Brand Guidelines V2.2 (`design/brand-v2.2/`, ADR-556).

## Consequences
The privacy screen is one step further from Home: Settings › Privacy instead of the menu. Phone calls are one tap from Home's menu in Debug builds. Showing them in the beta is a separate owner decision (take `phoneCalls`, and `callCases` for Calls for you, out of `ReleaseScope.shipping`).

## Evidence
`scripts/ci.sh --only checks` run here; the app was not compiled here (no Xcode). The hosted Mac job builds it and runs the UI smoke tests on #270.

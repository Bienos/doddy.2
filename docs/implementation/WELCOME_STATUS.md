# The first-launch welcome: status (ADR-598)

Date: 2026-10-22. Branch `claude/gifted-einstein-61p6hq`. Design: Figma file `kR2N76fNeMmptR53RnMgSj` (frames `13:62`, `13:106`, `13:159`, `13:217`, `13:286`, `13:340`) and the clickable prototype it was drawn from. The build prompt is `prompts/WELCOME_FLOW_2026-10-22.md`.

**Built and tested by CI, not seen on a device.** The code was written in an environment with no Swift toolchain. PR #132's hosted runs passed: run 39872214301 (head `5e2e654`, before Sign in with Apple): `core` (Linux, including the DoddyCore tests) and the macOS job (build, unit tests, 60 UI tests with 1 skipped and 0 failures, including the 6 `WelcomeUITests`; `scripts/ci.sh` RESULT: PASS). Run 39916690546 (head `b82edfe`, with the Apple button, merged with the base): `core` and the macOS job's `scripts/ci.sh` step both succeeded (I did not read its test counts; the `WelcomeUITests` now also assert the Apple button). Nobody has looked at it on a phone, so the look, the feel and the animations are unchecked, and a real Apple sign-in has never been tried.

## What it is
Five chapters you swipe right to left, one persistent Doddy who hops between them, and a sign-in sheet pinned to the bottom. It shows what Doddy does as one morning in Warsaw, using the copy deck (`design/website-what-can-doddy-do/COPY.md`). It is a scripted demonstration: nothing is saved, reminded, sent or looked up, and every scene card is tagged **Example**.

| # | Chapter | Pose | Scene |
|---|---|---|---|
| 1 | One morning in Warsaw / Hi, I'm Doddy. | wave | "Dzień dobry!" types in, "hi!" springs up |
| 2 | 18:45 / My brain has left the chat. | belly_reading | scraps float, a "found in your notes" card drops in with where it came from |
| 3 | 22:30 / Don't let me forget. | shrug | a spoken reminder types, Evening is chosen, a read-back receipt |
| 4 | 23:30 / Sort tomorrow out. | fistpump | three rows tick, "Do these (3)" becomes "3 done" |
| 5 | A mate in your pocket / One tap away. | basketball_dribble | the Dynamic Island stretches into "Doddy · Listening" |

## How it works
- **Position drives everything.** `ScrollView` paging with `scrollPosition`; the page position (0 to 4) is measured and every moving thing is a pure function of it (`WelcomeFlow` in DoddyCore: pose cross-over at half a page, hop, tilt, ground and skyline offsets, text slide). It follows the finger and can be grabbed and reversed. iOS 17 baseline (no `onScrollGeometryChange`).
- **Scenes** are pure functions of the seconds since their chapter began to slide in (`WelcomeTimeline`), driven by a `TimelineView`, so a swipe ends any scene at once and nothing blocks input. A page that has gone off screen resets; Reduce Motion shows every scene in its final state, with no hop, parallax or typing.
- **Sign-in sheet** (`SignInSheet.swift`): custom, two heights (138 and 384 pt), a drag that follows the finger, a spring on release, a scrim, Reduce Transparency opaque. Not a system sheet: that would sit above the Face ID lock's cover.
- **Sign in with Apple is real (ADR-599).** The first button is Apple's system button (`AppleAccountSignInButton`, shared with the voice gate): a finished sign-in creates the Doddy voice account and ends the welcome. It needs the paid team's capability (A5) and the token server (A4); on a free-team build Apple's sheet fails and the sheet says so.
- **The other three are not connected.** `UnconnectedSignIn` is their only provider and returns `.notConnectedYet`; Face ID, Google and email say "Sign-in isn't connected yet". "Try Doddy without an account" also moves on and uses the device session (ADR-563) as before.
- **Labels** follow Apple's HIG: the first button says Face ID, Touch ID or passkey according to `AppLock.biometry` (read only; `LocalAuthentication` stays inside `AppLock.swift`).

## When it shows
`WelcomeRule`: a genuinely new installation, not yet seen. Updating from an older version does not show it. Finishing (Try without an account) sets `welcomeSeen`. Settings › "Show the welcome again" sets `welcomeReplay`. UI tests: `-welcome YES|NO` (`UITestLaunch` defaults to NO). While it is up it covers Home; the opening scene and the first-use introduction wait for it and then go on as before.

## Files
- DoddyCore: `Welcome/WelcomeFlow.swift`, `Welcome/SignInOption.swift`, `Welcome/WelcomePathData.swift`; tests `WelcomeFlowTests`, `SignInOptionTests`, `WelcomePathDataTests`.
- App: `Features/Welcome/` (`WelcomeView`, `WelcomeScenes`, `WelcomeScenery`, `SignInSheet`, `WelcomePreferences`); `RootView` (state, overlay, the opening and introduction held back, two new `PreferenceKey`s); `Theme.hand`; `AppLock.biometry`; the Settings row.
- Tests: `DoddyUITests/WelcomeUITests.swift`, `UITestLaunch` (`welcome:`).
- Strings: 51 new Polish lines in `l10n/pl.json`; `DoddyApp/Resources/Localizable.xcstrings` regenerated. The other eight languages show English for these until `tools/l10n_batch.py` runs.

## What ran
- Locally (Linux, no Swift): `check_forbidden_capabilities.sh` PASS, `build_strings_catalog.py --check` PASS, `l10n_batch.py status pl` 0 missing.
- Hosted CI, PR #132, run 39872214301 on head `5e2e654`: `core` PASS (DoddyCore tests); macOS job PASS: XcodeGen, `build-for-testing`, unit tests, simulator restart, 60 UI tests (1 skipped, 0 failures) including `WelcomeUITests` 6 of 6 (five chapters by swipe, Skip, the sign-in options say "not connected" and only "Try Doddy without an account" moves on, the launch-argument skip, Reduce Motion, largest text).
- Hosted CI, PR #132, run 39916690546 on head `b82edfe` (Apple button, merged with the base): `changes`, `core` and the macOS `ci` job all succeeded (`scripts/ci.sh` step 07:23 to 08:15 UTC). Test counts were not read from the log.
- Not covered by any test: how it looks and feels, the animations, the Dynamic Island scene on a Dynamic Island iPhone, dark mode, VoiceOver order, the Face ID lock over the welcome.

## Owner decisions
1. **Caveat for Doddy's hand-written lines.** The design used Caveat; the app bundles no fonts, so `Theme.hand` is a system stand-in. Bundle Caveat (OFL), or keep the stand-in?
2. **Sign in with Apple next to Google** (App Review 4.8), before any option is connected: GO_LIVE_CHECKLIST C16.
3. **The pigeon and the Warsaw line** are placeholders. Replace with the pack's scenery, or drop the pigeon?
4. **Scenes are hidden from VoiceOver** (each chapter reads label, title and line; the Example cards are decoration). Is that enough, or should the cards be read?
5. The Palace of Culture outline is simplified and unchecked against the building.

## Checks for a Mac and an iPhone
On a device: swipe feel and the hop, the sheet's two heights and its drag, the Face ID or Touch ID label, Dynamic Type at AX sizes (scene hides, text scrolls), Reduce Motion and Reduce Transparency, VoiceOver order, the Dynamic Island scene on a Dynamic Island iPhone, light and dark (the dark art backing comes from `CharacterArtImage`), and that the Face ID lock still covers the welcome.

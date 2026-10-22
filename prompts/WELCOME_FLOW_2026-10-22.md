# Prompt: build the welcome flow, "One morning in Warsaw" (iPhone)

Paste this into a fresh Claude Code session in `Bienos/doddy.2`. It is one milestone. Stop at the report.

---

## 0. Read first, change nothing yet
1. `CLAUDE.md`, `STATUS.md`, `docs/platforms/iphone.md`, `docs/implementation/ONBOARDING_STATUS.md`, `docs/design/BRAND_V2_2_REVIEW.md`, `design/website-what-can-doddy-do/COPY.md` (the copy deck the lines come from).
2. Search `DECISIONS.md` for ADR-225 (opening scene), ADR-299/380 (onboarding), ADR-552 to 555 and 576 (persistent Doddy), ADR-563 (device sign-in), ADR-573 (Polish default). Don't read it whole.
3. Code to understand before designing: `DoddyApp/App/RootView.swift` (how the opening scene, `profiles.isIntroductionPresented` and the Face ID cover are ordered), `DoddyApp/Features/Onboarding/*`, `DoddyApp/Features/Opening/*`, `DoddyApp/DesignSystem/Theme.swift`, `DoddyApp/DesignSystem/Motion/*`, `DoddyApp/Features/Privacy/AppLock.swift`, `DoddyApp/Infrastructure/DeviceSession.swift`.
4. Inventory: branch, `git status`, whether Xcode/Swift exist here. If there is no Xcode, say so and mark the native build BLOCKED / NOT RUN. Never say a build or test passed unless you ran it.
5. Branch from the latest `main`. Next free ADR number: check `DECISIONS.md` (579 or later).

## 1. What to build
A first-launch welcome: **five swipeable chapters** (right to left) that show what Doddy does as one ordinary morning in Warsaw, with a **sign-in sheet pinned at the bottom** (Face ID, Google, email). Once the user has been through it (or tapped "Try Doddy without an account"), it never shows again and the app opens straight to Doddy. It sits in front of the existing first-use flow; it does not delete it.

Design sources, in order of authority:
- **Figma** file `kR2N76fNeMmptR53RnMgSj` (https://www.figma.com/design/kR2N76fNeMmptR53RnMgSj). Static frames: `13:62` Castle Square, `13:106` Notes, `13:159` Reminder, `13:217` Plan, `13:286` Pocket, `13:340` sign-in sheet open. Use `get_design_context` / `get_screenshot` per frame if the Figma MCP is available.
- **Motion and behaviour** are in the clickable prototype https://claude.ai/artifact/3wwUdLRjYsUW95VHN2iMWR (`Main.dc.html`; private, ask the owner for access if you can't open it). The timing table in section 4 is the same spec in text, so you can work without it.
- Look: Apple-native, minimal, calm. Paper `#FFF7E9`, ink `#171715`, orange `#FF6A00` only as an accent. Use `Theme` / `DoddyDesignTokens` colours, not literals.

## 2. Hard rules (the repo's, restated for this task)
- **Honesty.** The five scenes are scripted demonstrations. Show a small visible "Example" tag in every scene card. Don't fake saved memory, a real reminder, a real send or a real lookup. "Trattoria Nonna, Hoża 9" is the copy deck's made-up example. Never write "implemented/tested" for anything you didn't run.
- **Character art:** only the owner's pack, already in `DoddyApp/Resources/Assets.xcassets`: `WholeDoddy_wave`, `WholeDoddy_belly_reading`, `WholeDoddy_shrug`, `WholeDoddy_fistpump`, `WholeDoddy_basketball_dribble`, `WholeDoddy_listening` (island avatar crop). No new Doddy art, no redrawing, no recolouring.
- **Placeholder scenery:** the Warsaw skyline line and the pigeon are my own simple vector placeholders (paths in section 5). Build them as SwiftUI `Shape`s behind one `WelcomeScenery` type, mark them `// PLACEHOLDER: replace with the owner's pack scenery`, and list that in the report. The owner's real pigeon and scenery art is not in the repo.
- **Fonts:** the app bundles none. The hand-written lines were designed in Caveat. Do NOT add a font file. Put every hand line behind one `Theme.handFont` call site that falls back to a system font (`.system(design: .rounded)`, italic, bold), and list "bundle Caveat (OFL)?" as a decision for the owner.
- **Type:** system text styles and Dynamic Type, not fixed point sizes. The layout must still work at the largest accessibility size (let the scene shrink or hide before text clips).
- **Sign-in is UI only.** No backend, no Supabase, no Google/Apple SDK, no Info.plist or entitlement changes. See section 3.
- **Face ID code boundary:** `scripts/check_forbidden_capabilities.sh` allows `LocalAuthentication` only in `AppLock.swift`. Don't import it anywhere else. If you need to know whether Face ID or Touch ID exists (for the button label), expose a tiny read-only property from `AppLock`.
- **Language:** Polish is the default (ADR-573). Every string goes through the existing localisation path (`l10n/`, see `l10n/TRANSLATION_PROMPT.md`). Write `en` and `pl` by hand; follow the repo's process for the other languages. "mate" is never translated literally (`BRAND_GUIDELINES.md` 3.8).
- **Scope.** Don't touch the backend, the live ElevenLabs agent, the website, Watch or Mac code. No new dependencies.

## 3. Sign-in sheet (UI now, backend later)
- **Native pattern:** a sheet that is always presented with two detents, collapsed (about 138 pt) and expanded (about 384 pt): `presentationDetents`, `presentationBackgroundInteraction(.enabled)`, `interactiveDismissDisabled()`, material background. If that conflicts with `RootView`'s other covers, fall back to a custom overlay and say why in the report.
- **Collapsed:** one glass button: Face ID glyph, "Get in", "Face ID, Google or email", a chevron that nudges up. Tapping or swiping up expands the sheet and dims the welcome.
- **Expanded ("Your turn"):** three buttons of equal size and weight: **Continue with Face ID** (ink), **Continue with Google** (white, hairline border), **Continue with email** (tinted). Under them, "Try Doddy without an account". Small line: "Face ID opens Doddy on this iPhone. Doddy only learns that it matched."
- **Label rule (Apple HIG):** name the method the device really has ("Continue with Face ID" / "Touch ID" / "passkey"). Never mention a method that isn't available.
- **Behaviour today:** put the three providers behind a protocol in DoddyCore (`SignInProviding`, one `SignInOption` enum: `faceID`, `google`, `email`). The only implementation, `UnconnectedSignIn`, returns `.notConnectedYet`. Tapping a button shows a short, plain inline message ("Sign-in isn't connected yet. You can try Doddy without an account.") and keeps the sheet open. It must never look like a successful sign-in. "Try Doddy without an account" is the only button that moves on, and it uses the existing device session (ADR-563) exactly as today.
- **Face ID scan animation** (glyph brackets pulse, an orange line sweeps, then an orange check) plays only as the pressed-state of the Face ID button. It must not imply a real check happened: after about 1.2 s it returns to idle and shows the not-connected message.
- **App Review risk to report, not fix:** offering Google sign-in requires an equivalent privacy-preserving option (Sign in with Apple, guideline 4.8) unless the only accounts are the app's own. Add a row to the go-live checklist and state it in the report. Don't ship the Google button without it.

## 4. The five chapters (copy, pose, scene, timing)
Persistent Doddy stands centred on a ground line at the same spot on every page. His pose changes at the top of a hop between pages. He lands with a small squash. The ground line moves 1:1 with the pages; the Warsaw line drifts at 45% of that (parallax). Each chapter has a small label above the title, the title, and one hand-written Doddy line below it. The scene plays when its page becomes current and replays on return.

| # | Label | Title | Doddy's line | Pose | Scene (plays in about 3 s) |
|---|---|---|---|---|---|
| 1 | ONE MORNING IN WARSAW | Hi, I'm Doddy. | Let's take a walk. | wave | "Dzień dobry!" types in; "hi!" springs up by his hand. |
| 2 | 18:45 | My brain has left the chat. | Your words, not a guess. | belly_reading | Three scraps float ("Marta's book", "Locker 4471", "Parked on B2"). A card drops in: FOUND IN YOUR NOTES, "Italian place for Ola's birthday: Trattoria Nonna, Hoża 9.", "Saved 4 Oct · your typed note". |
| 3 | 22:30 | Don't let me forget. | Tomorrow. Morning or evening? Pick one. | shrug | "Remind me to call Mum tomorrow." types; chips Morning 10:00 / Evening 19:00 pop; Evening is chosen; receipt row "Added to Reminders · read back 22:31". |
| 4 | 23:30 | Sort tomorrow out. | Three things, one tap. Untick to skip any. | fistpump | Plan card: three rows tick one after another; "Do these (3)" is tapped and becomes "3 done". |
| 5 | A MATE IN YOUR POCKET | One tap away. | Island, Action Button, or a tap on the back. | basketball_dribble | The Dynamic Island shape stretches into "Doddy · Listening" with sound bars; caption "wherever you are". |

The pigeon pecks near the ground line on every page (a different spot each time) and ends beside Doddy on page 5.

**Motion rules (Apple, "Designing Fluid Interfaces"):**
- Paging is a real `ScrollView` with `scrollTargetBehavior(.paging)` and `scrollPosition`. Everything else is driven by the live scroll progress (`visualEffect` / `onScrollGeometryChange`), 1:1 with the finger, never by a timer.
- Springs, not fixed-duration curves, for anything the user touches. Default critically damped (response about 0.35); a little bounce (damping about 0.8) only where a flick carried momentum (the sheet, the hop landing).
- Every scene animation can be interrupted by swiping on. No input is blocked while a scene plays.
- Haptics only on meaningful moments: a soft tick when a plan row ticks, a light impact when the sheet snaps. Same frame as the visual.
- Reduce Motion: no hop, no parallax, no typing. Pages cross-fade, scenes show their final state. Reduce Transparency: the sheet becomes opaque.
- No autoplay in the app (the prototype autoplays only for demo).

## 5. Reference geometry (design space 390 x 844)
- Doddy images 170 x 255, centred (x 110). Ground line y 464, 2 pt, ink. Soles at the ground. Glow: 240 pt circle at (75, 236), `#FFE2C6`, blurred. Doddy shadow: 110 x 9 ellipse at y 466.
- Pose bottoms as a fraction of image height (for aligning soles): wave .916, belly_reading .689, shrug .929, fistpump .936, dribble .778.
- Chapter label y 490 (13 pt semibold, tracking .6, secondary text), title y 510 (32 pt bold, tracking -0.022em), hand line below (about 28 pt). Page dots y about 652. Scene cards sit at y 104 to about 250 and must stay above his head.
- Card: white, radius 22, shadow (0, 10, 30, 8%) plus (0, 1, 2, 6%).
- Warsaw line (placeholder), stroke 2 pt, ink at 30%, viewBox 1000 x 130, baseline y 130 placed at the ground line:
  `M50 130 V122 H74 V130 M56 122 V40 M68 122 V40 M52 40 H72 M62 40 V24 M56 31 H68` plus a circle (62,19) r4 (Sigismund's Column);
  `M120 130 V76 L132 64 L144 76 L156 64 L168 76 V130 M172 130 V58 H180 V50 H190 V44 H202 V50 H212 V58 H222 V130 M226 130 V82 Q253 54 280 82 V130` (Old Town gables);
  `M430 130 V62 H452 V130 M460 130 V38 H486 V130 M494 130 V78 H516 V130` (towers);
  `M650 130 V102 H668 V86 H684 V72 H696 V34 H700 V10 L704 34 H708 V72 H720 V86 H736 V102 H754 V130` (Palace of Culture, simplified, unverified);
  `M830 130 V80 L842 68 L854 80 L866 68 L878 80 V130 M886 130 V60 H894 V52 H906 V60 H916 V130 M922 130 V86 Q946 62 970 86 V130` (more gables).
- Pigeon (placeholder), 46 x 34: body `M8 22 C8 14 16 11 24 12.5 C30 13.5 33 16 35 20 L42 27 L29 27.5 C22 31 12 29 8 22 Z`, head circle (33, 11.5) r5, legs `M20 29 V33 M26 29 V33`, orange beak triangle `M37.5 11 L43 13 L37.5 14.5 Z`, eye (34.5, 10.5) r1; stroke ink 2.2 pt, fill paper. Faces left on pages that put it on the right (mirror it).
- Face ID glyph (44 x 44 box): brackets `M4 15 V10 a6 6 0 0 1 6 -6 H15 M29 4 H34 a6 6 0 0 1 6 6 V15 M40 29 V34 a6 6 0 0 1 -6 6 H29 M15 40 H10 a6 6 0 0 1 -6 -6 V29`, face `M16 17 V20 M28 17 V20 M22 17 V25 H20.5 M15.5 30 Q22 35 28.5 30`, scan line y 9 to 35 in orange. Prefer SF Symbols (`faceid`) for the standard glyph and use this only for the scan animation.

## 6. Where it goes
- UI: `DoddyApp/Features/Welcome/` (`WelcomeView`, `WelcomeStage`, `WelcomeChapters`, `WelcomeScenery`, `SignInSheet`). Keep each file small.
- Logic that has no UI goes in DoddyCore so it compiles and tests on Linux: `Welcome/WelcomeFlow.swift` (page progress to pose, opacity, hop, parallax offsets; the "seen" rule), `SignInOption.swift` and `SignInProviding`.
- "Seen" flag: one `PreferenceKey` (UserDefaults), set when the user finishes or skips. Returning users go straight to Doddy. Add Settings › "Show the welcome again" and a launch argument for UI tests (`-welcome 1` forces it, `-welcome 0` skips it).
- Order in `RootView`: decide it from what you read, then document it. Default: welcome, then the existing opening scene and optional introduction. Don't break the Face ID cover (it must stay above everything) or the persistent Doddy hand-off.

## 7. Tests (run what you can, report what you can't)
- DoddyCore, Linux (`scripts/ci.sh --core-only`): `WelcomeFlow` maths (poses cross over at half a page, hop peaks mid-page, parallax factor, clamping at both ends), the seen-flag rule, a completeness test that every chapter has en and pl copy, and `UnconnectedSignIn` never returns success.
- App/UI (hosted Mac CI only; not runnable on Linux): launch with `-welcome 1`, swipe through five pages, open the sheet, tap Google (message appears, sheet stays), tap "Try Doddy without an account" (Home appears), relaunch (welcome doesn't show). Add Dynamic Type XXL and Reduce Motion launch variants.
- Physical iPhone checklist for the owner: Face ID label on a Face ID device, swipe feel, sheet detents, VoiceOver order (one element per chapter, label + title + line; art hidden; the sheet reachable), Island overlap on the Dynamic Island models.

## 8. Docs and the end of the milestone
- ADR in `DECISIONS.md`, a `docs/implementation/WELCOME_STATUS.md`, a line in `STATUS.md`, the feature map row in `docs/platforms/iphone.md`, and the 4.8 row in the go-live checklist.
- Finish with the repo's report: files changed, shipped behaviour, actual tests (command, output, environment, failed/skipped), manual verification pending, privacy and security notes, decisions the owner must make (Caveat, Apple sign-in, whether to keep the pigeon), the constitution evidence log, and the next recommended milestone (real sign-in). Then stop.

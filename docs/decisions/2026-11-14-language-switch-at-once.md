# Settings › Language has a Polski | English switch, and a choice shows at once

- **Date:** 2026-11-14
- **Decided by:** owner: "Can you add switch between polish and English language in settings as now current setting are not chainging anything"
- **Status:** proposed in this pull request (not compiled here; the hosted Mac job compiles it)
- **Replaces:** the "a change shows the next time Doddy is opened" part of ADR-459. ADR-573 (Polish by default) stays.

## Why
Settings › Language (ADR-459) saved the choice in the app's own `AppleLanguages`. iOS reads that only when an app starts, and iOS rarely ends an app that was only sent to the background, so picking English or Polish changed nothing on screen until Doddy was swiped away and opened again. The footer said so, but the owner saw a setting that did nothing.

## Decision
- The Language page starts with a segmented **Polski | English** switch (`AppLanguage.switchChoices`). Every language of the build and "Same as this iPhone" stay, in one list under it.
- **A choice shows at once.** `ScreenLanguage` (app, `Infrastructure/`) gives `Bundle.main` a subclass that answers `localizedString(forKey:value:table:)` from the chosen language's `.lproj` (then English's, then the English in the code) and `preferredLocalizations` as that language. So every `NSLocalizedString`, the island's words, the cards that choose Polish or English themselves and the Polish or English web pages follow. `ScreenLanguageEnvironment` hands SwiftUI the same language as its locale, with the iPhone's own region and formats, for `Text("…")`, dates and numbers. `RootView` makes its screens new when the saved choice changes (the same way it already does when the Face ID lock comes back), so Settings comes back on its first page in the new language; the tab stays.
- Which table to use is `AppLanguage.screenLanguage(chosen:launchLocalization:)` in DoddyCore: none when iOS already started Doddy in the chosen language, none for "Same as this iPhone" (only iOS knows the iPhone's languages, so that one still shows from the next start).
- `AppleLanguages` is still written, so the next start is in the chosen language from its first frame and the subclass has nothing to do then. At launch the subclass is used only when a choice was made in Doddy and iOS started in another language (for example after iOS Settings › Doddy › Language was changed). The Polish default for a person who chose nothing still shows from the second start, as before.

## Consequences
- Not changed until the next start: what iOS draws itself (permission prompts, Siri phrases, the share sheet, Sign in with Apple's button), the widgets (their own process), anything kept in memory outside the redrawn screens, and six messages held in a `static let` (for example "Open Doddy to talk." in `TalkInIsland`), which stay in the language they were first shown in. The voice's language is its own setting (Voice and personality › Starts in) and is untouched.
- Replacing `Bundle.main`'s class at run time is an Objective-C technique Apple doesn't document for this; it touches no private API. If a later iOS stops SwiftUI from following it, `ScreenLanguageTests.testSwiftUITextFollowsTheChoice` fails in the hosted Mac job.
- Switching rebuilds the screens under the tab bar, the same as the Face ID lock's return: an open page in Settings closes. A conversation is held by `HomeConversation` and keeps running.
- Privacy: nothing new is stored or sent; the choice was already saved on the iPhone.

## Evidence
- `python3 -I tools/build_strings_catalog.py --check`: PASS (the old footer's line removed from nine tables, three new lines in each).
- `make test-core` with Swift 6.1.2 on Linux (the version of CI's `core` job): 3,519 tests, 0 failures, 2 skipped; `AppLanguageTests` 14 of 14, four of them new.
- `scripts/ci.sh --only checks`: every check PASS; "Studio skills: renderers on samples" NOT RUN (reportlab and matplotlib missing here), unrelated.
- The app code (`ScreenLanguage`, the Settings page, `RootView`, `DoddyApp`) and the hosted `DoddyTests/ScreenLanguageTests` (six tests, including one that draws `Text("Settings")` and compares it with "Ustawienia"): **not compiled here** (no iOS SDK on Linux). The hosted Mac job compiles and runs them.
- First hosted run of #487 (`ios-build`, Xcode 26.6, simulator): the app compiled; five of the six `ScreenLanguageTests` passed, including `testTheCodesWordsFollowTheChoiceAtOnce` (`NSLocalizedString("Settings")` gives "Ustawienia" in an app that started in English) and `testSwiftUITextFollowsTheChoice`; 189 other unit tests and the UI smoke tests passed. `testTheLocaleKeepsTheRegion` failed (the built locale had no region), a real bug: `Locale.Components(locale:)` keeps "US" of en_US inside the language components, so replacing them dropped the region and dates and numbers would have lost the iPhone's regional format. Fixed by setting `components.region` explicitly; the next run is the check.
- Not seen on a device.

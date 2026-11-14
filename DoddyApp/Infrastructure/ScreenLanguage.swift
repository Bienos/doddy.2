import DoddyCore
import Foundation
import ObjectiveC
import os
import SwiftUI

/// Doddy's screens in the language chosen in Settings › Language from the moment it is chosen
/// (owner, 14 Nov 2026: "add switch between polish and English language in settings as now current
/// setting are not changing anything"; decision `2026-11-14-language-switch-at-once`).
///
/// iOS picks an app's language once, as it starts, from the app's `AppleLanguages`. `AppLanguageStore`
/// still writes that, so the next start is in the chosen language from its first frame. Until then this
/// makes the app's main bundle answer from the chosen language's table (`<code>.lproj`, built from the
/// string catalogs): every `NSLocalizedString`, and every place that asks
/// `Bundle.main.preferredLocalizations` (the island's words, the cards that pick Polish or English
/// themselves, the Polish or English web pages). `ScreenLanguageEnvironment` hands SwiftUI the same
/// language for `Text("…")` and for dates and numbers, and `RootView` draws its screens again when the
/// choice changes. Which language that is, is `AppLanguage.screenLanguage` in DoddyCore.
///
/// Not changed until the next start: what iOS itself draws (permission prompts, Siri phrases, the share
/// sheet, Sign in with Apple's button), the widgets (their own process) and the voice, which has its own
/// language under Voice and personality.
enum ScreenLanguage {
    /// What iOS picked as Doddy started. Read before anything here changes the answer.
    static let launchLocalization: String? = Bundle.main.preferredLocalizations.first

    /// The chosen language's table, and English's for a line it doesn't have (strings with no line in a
    /// language show in English, as without this).
    struct Table: @unchecked Sendable {
        let code: String
        let strings: Bundle?
        let english: Bundle?
    }

    private static let current = OSAllocatedUnfairLock<Table?>(initialState: nil)

    /// The table in use, or nil when the screens use iOS's own pick.
    static var table: Table? { current.withLock { $0 } }

    /// The `.lproj` the screens use now instead of iOS's pick, or nil.
    static var code: String? { table?.code }

    /// The locale SwiftUI gets: the chosen language with the iPhone's own region and formats (a person
    /// in Poland who picks English still sees 14.11.2026 and a 24-hour clock). Nil: iOS's own.
    static var locale: Locale? {
        guard let code else { return nil }
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: code)
        return Locale(components: components)
    }

    /// Show `language` from now on (`AppLanguageStore.choose` and the launch).
    static func show(_ language: AppLanguage) {
        use(AppLanguage.screenLanguage(chosen: language, launchLocalization: launchLocalization))
    }

    /// Use the table for `code` (an `.lproj` name), or iOS's own pick for nil. A language with no table
    /// in this build leaves iOS's pick; English needs none, since the code's own words are English.
    static func use(_ code: String?) {
        _ = launchLocalization
        guard let code, let table = makeTable(code) else {
            current.withLock { $0 = nil }
            return
        }
        current.withLock { $0 = table }
        // Once per run. With no table set the subclass answers exactly as `Bundle` does.
        if !(Bundle.main is ScreenLanguageBundle) {
            _ = object_setClass(Bundle.main, ScreenLanguageBundle.self)
        }
    }

    private static func makeTable(_ code: String) -> Table? {
        let strings = lproj(code)
        let english = lproj("en")
        guard strings != nil || code == "en" else { return nil }
        return Table(code: code, strings: strings, english: english)
    }

    private static func lproj(_ code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// `key` from the table in use, then English's, then the English the code was written in.
    fileprivate static func text(_ table: Table, key: String, value: String?, tableName: String?) -> String {
        let missing = "\u{1}"
        for bundle in [table.strings, table.english].compactMap({ $0 }) {
            let found = bundle.localizedString(forKey: key, value: missing, table: tableName)
            if found != missing { return found }
        }
        // As `Bundle` does for a key it doesn't have: the default value if there is one, else the key.
        if let value, !value.isEmpty { return value }
        return key
    }
}

/// `Bundle.main`'s class once a language was chosen in Doddy during this run (`ScreenLanguage`).
private final class ScreenLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let table = ScreenLanguage.table else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return ScreenLanguage.text(table, key: key, value: value, tableName: tableName)
    }

    override var preferredLocalizations: [String] {
        if let code = ScreenLanguage.code { return [code] }
        return super.preferredLocalizations
    }
}

/// SwiftUI's locale for `Text("…")`, dates and numbers, in the language the screens use (`ScreenLanguage`).
/// On the root view (`DoddyApp`). It reads the saved choice so a change in Settings hands SwiftUI the new one.
struct ScreenLanguageEnvironment: ViewModifier {
    @AppStorage(PreferenceKey.appLanguage) private var appLanguage: String?

    func body(content: Content) -> some View {
        content.environment(\.locale, locale(after: appLanguage))
    }

    /// `ScreenLanguage` has already switched when the saved choice changes (`AppLanguageStore.choose`).
    private func locale(after _: String?) -> Locale {
        ScreenLanguage.locale ?? .autoupdatingCurrent
    }
}

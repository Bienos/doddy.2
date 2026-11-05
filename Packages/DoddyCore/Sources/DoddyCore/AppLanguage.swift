import Foundation

/// The language Doddy's screens are shown in (ADR-459): Polish unless the person picks another
/// in Settings (ADR-573; it was English until 21 Oct 2026). iOS decides the screens' language when the app starts, from the app's own
/// `AppleLanguages` setting (the one iOS Settings › Doddy › Language writes too), so a change
/// shows the next time Doddy is opened. This type holds the choices and the rule for what to
/// write at launch; the app does the writing.
///
/// Platforms: iPhone and iPad use it. The Watch and Mac apps don't show the picker.
public enum AppLanguage: String, CaseIterable, Sendable {
    // English first, then the others by their English name. The raw value is the language code
    // the String Catalogs and `CFBundleLocalizations` use (tools/build_strings_catalog.py checks
    // that every language with a table in l10n/ is listed here).
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case croatian = "hr"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case polish = "pl"
    case portugueseBrazil = "pt-BR"
    case spanish = "es"
    /// No choice of Doddy's own: the language of the iPhone, as for any app.
    case followPhone = "system"

    /// What a person gets before choosing (owner, 21 Oct 2026: "it should be Polish", ADR-573;
    /// before that, 13 Oct: "english by default").
    public static let `default`: AppLanguage = .polish

    /// The saved choice, or Polish when nothing valid is saved.
    public init(stored: String?) {
        self = stored.flatMap(AppLanguage.init(rawValue:)) ?? .default
    }

    /// The language's own name, shown as it is so a person can find it in any language.
    /// Nil for `followPhone`, which is a sentence the app translates.
    public var nativeName: String? {
        switch self {
        case .english: "English"
        case .chineseSimplified: "简体中文"
        case .croatian: "Hrvatski"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .polish: "Polski"
        case .portugueseBrazil: "Português (Brasil)"
        case .spanish: "Español"
        case .followPhone: nil
        }
    }

    /// The code written to `AppleLanguages`, or nil for `followPhone`.
    public var code: String? { self == .followPhone ? nil : rawValue }

    /// The language of an `AppleLanguages` entry such as "de", "pt-BR" or "zh-Hans-CN", or nil
    /// when Doddy has none of that language. A region Doddy doesn't have falls back to the
    /// language ("pt-PT" gives Brazilian Portuguese, as iOS would pick it). Traditional Chinese
    /// is not Simplified Chinese.
    public static func matching(_ identifier: String) -> AppLanguage? {
        let id = identifier.lowercased()
        if id.contains("-hant") { return nil }
        let languages = allCases.filter { $0 != .followPhone }
        if let exact = languages.first(where: { id == $0.rawValue.lowercased() || id.hasPrefix($0.rawValue.lowercased() + "-") }) {
            return exact
        }
        let base = id.split(separator: "-").first.map(String.init)
        return languages.first { $0.rawValue.lowercased().split(separator: "-").first.map(String.init) == base }
    }

    /// What the picker shows. A saved choice wins. With none, a language set in iOS Settings ›
    /// Doddy › Language (read from the app's own `AppleLanguages`), else Polish.
    public static func chosen(stored: String?, appLanguages: [String]?) -> AppLanguage {
        if let stored { return AppLanguage(stored: stored) }
        if let first = appLanguages?.first, let language = matching(first) { return language }
        return .default
    }

    /// What to do to the app's own `AppleLanguages` when Doddy starts.
    public enum LaunchAction: Equatable, Sendable {
        case leave
        case set([String])
        case remove
    }

    /// `stored` is the saved choice (nil when none was made in Doddy). `appLanguages` is the app's
    /// own `AppleLanguages` (nil when the app has no setting of its own, so iOS uses the
    /// iPhone's languages).
    ///
    /// - A choice made in Doddy is written (or removed, for "same as this iPhone").
    /// - With no choice, a language set in iOS Settings › Doddy is left alone.
    /// - With no choice and no setting at all, Polish is written: that is the default.
    /// - Once (`polishDefaultApplied` false): builds before ADR-573 wrote English on their first
    ///   launch, and that reads like a setting. With no choice made in Doddy, exactly that English
    ///   is replaced by Polish. The app then remembers it did this, so English set again later in
    ///   iOS Settings › Doddy stays.
    public static func launchAction(stored: String?, appLanguages: [String]?, polishDefaultApplied: Bool = true) -> LaunchAction {
        guard let stored else {
            if !polishDefaultApplied, appLanguages == [AppLanguage.english.rawValue] { return .set([AppLanguage.default.rawValue]) }
            return appLanguages == nil ? .set([AppLanguage.default.rawValue]) : .leave
        }
        let language = AppLanguage(stored: stored)
        guard let code = language.code else { return appLanguages == nil ? .leave : .remove }
        return appLanguages == [code] ? .leave : .set([code])
    }
}

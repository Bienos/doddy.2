import DoddyCore
import SwiftUI

/// Settings › Language (ADR-459). A Polski | English switch at the top (owner, 14 Nov 2026: "add switch
/// between polish and English language in settings as now current setting are not changing anything"),
/// then every language of the build and "Same as this iPhone" in one list. Polish until the person picks
/// another (ADR-573). A choice shows at once (`ScreenLanguage`, decision
/// `2026-11-14-language-switch-at-once`): the screens are drawn again in it, and Settings comes back on
/// its first page. "Same as this iPhone" shows from the next start. Each language is shown by its own
/// name, so it can be found whatever language is on.
struct AppLanguageSettingsSection: View {
    @State private var selection = AppLanguageStore.chosen()

    /// The build's languages (decision 2026-11-07-release-scope), plus the current choice if it is one the build hides.
    private var choices: [AppLanguage] { ReleaseScopeStore.current.languageChoices(current: selection) }

    var body: some View {
        Section {
            // With another language chosen in the list below, neither half is selected.
            Picker("App language", selection: $selection) {
                ForEach(AppLanguage.switchChoices.filter { choices.contains($0) }, id: \.self) { language in
                    Text(verbatim: language.nativeName ?? language.rawValue).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("settings.appLanguage")
            .onChange(of: selection) { _, language in AppLanguageStore.choose(language) }
        } footer: {
            Text("The screens change at once. The language Doddy speaks in is under Voice and personality.")
        }
        Section {
            Picker("All languages", selection: $selection) {
                ForEach(choices, id: \.self) { language in
                    if let name = language.nativeName {
                        Text(verbatim: name).tag(language)
                    } else {
                        Text("Same as this iPhone").tag(language)
                    }
                }
            }
            .accessibilityIdentifier("settings.appLanguage.all")
        } footer: {
            Text("Same as this iPhone shows the next time you open Doddy. Widgets, Siri phrases and the iPhone's permission questions follow the iPhone's language.")
        }
    }
}

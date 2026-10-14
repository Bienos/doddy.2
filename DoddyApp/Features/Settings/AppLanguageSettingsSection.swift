import DoddyCore
import SwiftUI

/// Settings › App language (ADR-459). English until the person picks another language. iOS
/// applies the language when the app starts, so the footer says to close Doddy and open it
/// again. Each language is shown by its own name, so it can be found whatever language is on.
struct AppLanguageSettingsSection: View {
    @State private var selection = AppLanguageStore.chosen()

    var body: some View {
        Section {
            Picker("App language", selection: $selection) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    if let name = language.nativeName {
                        Text(verbatim: name).tag(language)
                    } else {
                        Text("Same as this iPhone").tag(language)
                    }
                }
            }
            .accessibilityIdentifier("settings.appLanguage")
            .onChange(of: selection) { _, language in AppLanguageStore.choose(language) }
        } footer: {
            Text("Doddy starts in English until you pick another language. A change shows the next time you open Doddy: close it first, then open it again.")
        }
    }
}

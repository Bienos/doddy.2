import DoddyCore
import SwiftUI

/// Conversation memory, save suggestions, and confirmed learning controls.
struct SettingsKnowledgeSection: View {
    @Environment(MemoryStore.self) private var store
    @AppStorage(PreferenceKey.rememberConversations) private var rememberConversations = true
    @AppStorage(PreferenceKey.suggestSavesAfterConversation) private var suggestSaves = true
    @AppStorage(PreferenceKey.learningOn) private var learningOn = false

    private var conversationLogs: ConversationLogStore { .shared }

    var body: some View {
        Section("What Doddy knows") {
            Toggle("Remember recent conversations", isOn: $rememberConversations)
                .accessibilityIdentifier("settings.rememberConversations")
            NavigationLink {
                RememberedConversationsView(store: conversationLogs)
            } label: {
                StatusRow(title: "Remembered conversations", value: "\(conversationLogs.logs.count) of the last \(ConversationLogStore.maxLogs)")
            }
            .accessibilityIdentifier("settings.rememberedConversations")
            Button("Forget remembered conversations", role: .destructive) { conversationLogs.clear() }
                .disabled(conversationLogs.logs.isEmpty)
            // ADR-247: "Worth keeping?" after a voice conversation.
            Toggle("Suggest notes after a conversation", isOn: $suggestSaves)
                .accessibilityIdentifier("settings.suggestSaves")
            Text("When a conversation ends, Doddy may offer up to three things you said, in your words, to save as notes. Nothing is ticked and nothing is saved unless you tap Save. They're picked on this iPhone; never for a private conversation, and never passwords or card numbers.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if let learning = store.learning, learning.isAvailable {
                // ADR-440: facts and routines Doddy kept, each confirmed by the user.
                NavigationLink {
                    LearnedView(learning: learning)
                } label: {
                    StatusRow(
                        title: "What I've learned",
                        value: learningOn
                            ? "On · \(learning.confirmedFacts.count + learning.confirmedProcedures.count)"
                            : "Off")
                }
                .accessibilityIdentifier("settings.learned")
            }
            if let problem = conversationLogs.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
            }
            Text("When a conversation starts, the app hands Doddy your saved notes and, if this is on, your last few conversations, so he can carry on where you left off. They are kept only on this iPhone. Weather comes from Open-Meteo and facts from Wikipedia.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

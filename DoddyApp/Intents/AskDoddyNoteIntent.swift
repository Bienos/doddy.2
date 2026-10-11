import AppIntents
import DoddyCore
import SwiftUI

/// "Ask Doddy what I saved" (ADR-248): Siri asks what to look for, Doddy searches the saved notes
/// on this iPhone (the same search as Memories → Find) and Siri says the note's own words and
/// when it was saved. The app doesn't open. Nothing is saved or changed.
///
/// Notes can hold codes and addresses, so the iPhone must be unlocked: Siri asks to unlock first
/// when it is locked. Settings → Back Tap and Siri can turn the readback off. App target only.
struct AskDoddyNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Doddy what I saved"
    static var description: IntentDescription {
        IntentDescription("Searches your saved notes on this iPhone and reads the matching note aloud. Works only when your iPhone is unlocked.")
    }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Looking for", requestValueDialog: "What are you looking for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Doddy about \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let answer = await SiriNoteLookup.spokenAnswer(for: query, environment: .shared)
        // Siri's panel shows Doddy in the pose for the answer (ADR-313); the words are Siri's own.
        return .result(dialog: "\(answer)", view: SiriDoddySnippet(pose: SiriNoteLookup.pose(forAnswer: answer)))
    }
}

/// Doddy in Siri's panel (ADR-313). Decorative: Siri says and shows the answer itself. Empty with
/// "Hide Doddy's pictures".
struct SiriDoddySnippet: View {
    let pose: IslandPose

    var body: some View {
        WholeDoddyView(pose: pose, height: 110)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

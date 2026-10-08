import DoddyCore
import SwiftUI

/// Cloud assistant preview. Appears only after the user accepted the notice in Settings.
struct AskView: View {
    @State private var ask: AskStore
    @State private var question = ""

    init(environment: AppEnvironment) {
        _ask = State(initialValue: AskStore(environment: environment))
    }

    private var canSend: Bool { !question.allSatisfy(\.isWhitespace) && !ask.isSending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ask Doddy")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Label("Preview · AI-written answers can be wrong. Your question and up to 3 matching saved notes are sent to Doddy's server and OpenAI. Untested on a physical iPhone.", systemImage: "cloud")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)

                    TextField("What do you want to ask?", text: $question, axis: .vertical)
                        .lineLimit(1...6)
                        .padding(12)
                        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("ask.question")

                    if ask.isSending {
                        HStack {
                            ProgressView()
                            Text("Waiting for the answer…")
                            Spacer()
                            Button("Cancel") { ask.cancel() }
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Button {
                            ask.ask(question)
                        } label: {
                            HStack { Text("Ask"); Spacer(); Image(systemName: "arrow.up") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSend)
                        .accessibilityIdentifier("ask.send")
                    }

                    result
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
        }
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var result: some View {
        switch ask.phase {
        case .idle, .sending:
            EmptyView()
        case .failed(let message):
            ProblemView(message: message)
                .accessibilityIdentifier("ask.error")
        case .answered(let answer):
            VStack(alignment: .leading, spacing: 12) {
                Text(answer.text)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("ask.answer")
                if answer.sources.isEmpty {
                    Text(ask.notesSent == 0
                         ? "No saved note was used. This answer isn't based on your memories."
                         : "None of the \(ask.notesSent) matching notes sent was cited, so this answer isn't based on your memories.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Based on your saved notes")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(answer.sources) { record in
                        MemoryRow(record: record)
                        Divider()
                    }
                }
            }
        }
    }
}

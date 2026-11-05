import DoddyCore
import SwiftUI

/// "Hey. Let's talk." A short, optional set of questions, one at a time. Answers stay in this
/// screen's memory as a draft; nothing is stored until the user reviews them and taps Save.
/// The questions are fixed and scripted: no AI reads or interprets the answers.
struct IntroductionView: View {
    private enum Phase: Equatable {
        case question(Int)
        case review
    }

    @Environment(ProfileStore.self) private var profiles
    @State private var phase: Phase = .question(0)
    @State private var draft = ProfileDraft()
    @State private var didSeedDraft = false

    private let keys = ProfileKey.introductionQuestions

    var body: some View {
        Group {
            switch phase {
            case .question(let index):
                ProfileQuestionView(
                    key: keys[index], number: index + 1, total: keys.count,
                    answer: binding(for: keys[index]),
                    back: { if index == 0 { finish(saved: false) } else { phase = .question(index - 1) } },
                    next: { phase = index + 1 < keys.count ? .question(index + 1) : .review },
                    review: { phase = .review },
                    notNow: { finish(saved: false) })
                .id(index)
            case .review:
                ProfileReviewView(
                    draft: $draft,
                    back: { phase = .question(keys.count - 1) },
                    finishWithoutSaving: { finish(saved: false) },
                    saved: { finish(saved: true) })
            }
        }
        .onAppear {
            // Reopened from Settings: start from what is already approved.
            guard !didSeedDraft else { return }
            draft = profiles.introductionDraft
            didSeedDraft = true
        }
    }

    private func binding(for key: ProfileKey) -> Binding<String> {
        // An emptied answer counts as skipped, so it doesn't show up in the review.
        Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0.isEmpty ? nil : $0 })
    }

    private func finish(saved: Bool) {
        Task { await profiles.finishIntroduction(saved: saved) }
    }
}

// MARK: One question

private struct ProfileQuestionView: View {
    let key: ProfileKey
    let number: Int
    let total: Int
    @Binding var answer: String
    let back: () -> Void
    let next: () -> Void
    let review: () -> Void
    let notNow: () -> Void

    private var trimmed: String { ProfileDraft.normalize(answer) }

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "Question \(number) of \(total) · optional")
            DoddySaysCard(text: key.question)
                .accessibilityAddTraits(.isHeader)
            Text(key.hint)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)

            let choices = ProfileChoices.options(for: key)
            if !choices.isEmpty {
                ChoiceChips(choices: choices, selection: $answer)
            }

            ProfileTextField(
                key: key,
                prompt: choices.isEmpty ? "Your answer" : "Or in your own words",
                text: $answer)
                .submitLabel(.next)
                .onSubmit(next)

            Button(action: next) {
                HStack { Text(trimmed.isEmpty ? "Skip this one" : "Next"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("intro.next")

            HStack {
                Button("Not now", action: notNow)
                    .accessibilityIdentifier("intro.close")
                Spacer()
            }
            HStack {
                if number > 1 {
                    Button("Back", action: back)
                        .accessibilityIdentifier("intro.back")
                }
                Spacer()
                Button("Review and finish", action: review)
                    .accessibilityIdentifier("intro.review")
            }
            .frame(minHeight: 44)
        }
    }
}

/// Preset answers. Choosing one fills the answer; it can still be edited.
private struct ChoiceChips: View {
    let choices: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(choices, id: \.self) { choice in
                let selected = ProfileDraft.normalize(selection) == choice
                Button { selection = selected ? "" : choice } label: {
                    HStack {
                        Text(choice)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Theme.accentText : Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(selected ? Theme.quietSurface : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// One-line answer with a live length counter (same counting rule as validation).
struct ProfileTextField: View {
    let key: ProfileKey
    let prompt: String
    @Binding var text: String

    private var length: Int { ProfileDraft.normalize(text).unicodeScalars.count }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField(prompt, text: $text, axis: key == .context || key == .help ? .vertical : .horizontal)
                .lineLimit(1...4)
                .textInputAutocapitalization(key == .name ? TextInputAutocapitalization.words : TextInputAutocapitalization.sentences)
                .padding(12)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(key.label)
                .accessibilityIdentifier("profile.field.\(key.rawValue)")
            Text("\(length) / \(key.maxLength)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(length > key.maxLength ? Theme.error : Theme.secondaryText)
                .accessibilityLabel("\(length) of \(key.maxLength) characters")
        }
    }
}

// MARK: Review

/// Editable summary. "Save these preferences" is the only step that stores anything.
private struct ProfileReviewView: View {
    @Binding var draft: ProfileDraft
    let back: () -> Void
    let finishWithoutSaving: () -> Void
    let saved: () -> Void

    @Environment(ProfileStore.self) private var profiles
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showSavedConfirmation = false

    var body: some View {
        OnboardingPage {
            OnboardingLabel(text: "Before I keep anything")
            Text("Here's what I'd remember.")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Only the answers shown here are changed. They're saved on this iPhone.")
                .foregroundStyle(Theme.secondaryText)

            ProfileFieldsEditor(draft: $draft, visibleFields: ProfileKey.introductionQuestions)

            if let errorText {
                ProblemView(message: errorText)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Button {
                Task { await save() }
            } label: {
                HStack {
                    Text(isSaving ? "Saving…" : "Save these preferences")
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving || draft.isEffectivelyEmpty)
            .accessibilityIdentifier("profile.save")

            Button("Continue without saving", action: finishWithoutSaving)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSaving)
                .accessibilityIdentifier("profile.discard")

            HStack {
                Button("Back to the questions", action: back)
                Spacer()
            }
            .frame(minHeight: 44)
        }
        .alert("Saved on this iPhone", isPresented: $showSavedConfirmation) {
            Button("Done", action: saved)
        } message: {
            Text("Your name and response style are saved on this iPhone. You can edit or clear them in Settings.")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await profiles.commitIntroduction(draft)
            errorText = nil
            showSavedConfirmation = true
        } catch {
            errorText = ProfileErrorText.message(for: error)
        }
    }
}

/// Every answered field, editable, each with its own Remove. Shared with Settings.
struct ProfileFieldsEditor: View {
    @Binding var draft: ProfileDraft
    var visibleFields: [ProfileKey] = ProfileKey.allCases

    /// Fields in the draft, even while their text is being retyped.
    private var answeredKeys: [ProfileKey] {
        visibleFields.filter { draft[$0] != nil }
    }

    var body: some View {
        if answeredKeys.isEmpty {
            Text("Nothing to keep. That's fine: you can use Doddy without any of this.")
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("profile.empty")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(answeredKeys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(key.label).font(.headline)
                            Spacer()
                            Button(role: .destructive) { draft.remove(key) } label: {
                                Text("Remove")
                            }
                            .accessibilityLabel("Remove \(key.label)")
                            .accessibilityIdentifier("profile.remove.\(key.rawValue)")
                        }
                        ProfileTextField(
                            key: key, prompt: key.label,
                            text: Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0 }))
                    }
                }
            }
        }
    }
}

import DoddyCore
import SwiftUI

/// Compatibility wrapper for existing onboarding/voice views. All visible drawings
/// now use the owner's uploaded pack; original asset sets remain untouched.
struct CandidateCharacterView: View {
    let assetName: String
    var size: CGFloat = 180

    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            UploadedCharacterView(assetName: assetName == "Doddy_listening" ? "UploadedDoddy_Listening" : "UploadedDoddy_Sitting",
                                  height: size)
        }
    }
}

/// Label on the left, explicit text value on the right (never colour alone).
struct StatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.separator, lineWidth: 1)
                    .background(configuration.isPressed ? Theme.quietSurface : .clear, in: RoundedRectangle(cornerRadius: 18)))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Text editor with a live length counter (Unicode scalars, same rule as validation).
struct MemoryTextEditor: View {
    @Binding var text: String
    let label: String

    private var length: Int { text.unicodeScalars.count }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $text)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(label)
            Text("\(length) / \(MemoryLimits.maxTextLength)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(length > MemoryLimits.maxTextLength ? Theme.error : Theme.secondaryText)
                .accessibilityLabel("\(length) of \(MemoryLimits.maxTextLength) characters")
        }
    }
}

struct MemoryRow: View {
    let record: MemoryRecord
    var matchedTerms: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "note.text")
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.currentText)
                    .lineLimit(3)
                Text("\(record.source.displayName) · \(DateText.full(record.capturedAt))\(record.userEdited ? " · corrected" : "")")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if !matchedTerms.isEmpty {
                    Text("Matched: \(matchedTerms.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(Theme.accentText)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ProblemView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(Theme.error)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

enum StatusCopy {
    static func text(for status: CapabilityStatus) -> String {
        switch status {
        case .available: "Available"
        case .limited(let note): "Limited · \(note)"
        case .needsSetup(let note): "Needs setup · \(note)"
        case .notImplemented(let milestone) where milestone == "unscheduled": "Not built · not scheduled"
        case .notImplemented(let milestone): "Not built yet · planned \(milestone)"
        }
    }
}

extension Capability {
    var displayName: String {
        switch self {
        case .memoryStorage: "Saving memories"
        case .memoryRecall: "Finding memories"
        case .cloudAssistant: "AI answers"
        case .textAssistant: "Typed AI questions"
        case .voiceInput: "Listening (voice)"
        case .voiceOutput: "Speaking (voice)"
        case .reminders: "Reminders"
        case .connectedAccounts: "Connected accounts"
        case .cloudSync: "Sync between devices"
        case .systemShortcut: "Shortcut and Back Tap"
        case .pushUpdates: "Updates as notifications"
        case .textUpdates: "Updates by text message"
        case .phoneCalls: "Phone calls with Doddy"
        case .newsDigests: "Daily news message"
        case .noteReminders: "Reminders on notes"
        }
    }
}

extension MemorySource {
    var displayName: String {
        switch self {
        case .explicitText: "Your typed note"
        case .explicitVoice: "Your voice note"
        case .sharedContent: "Shared into Doddy"
        case .importedLegacyUnknown: "Imported, date unknown"
        case .sampleFixture: "Sample"
        }
    }
}

extension MemoryCategory {
    var displayName: String {
        switch self {
        case .fact: "Fact"
        case .preference: "Preference"
        case .commitment: "Commitment"
        case .recommendation: "Recommendation"
        case .decision: "Decision"
        case .item: "Item"
        case .place: "Place"
        case .intention: "Intention"
        case .other: "Other"
        case .list: "List"
        }
    }
}

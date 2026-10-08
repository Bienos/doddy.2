import SwiftUI
import DoddyCore

/// Decorative character art. Labelled as candidate art; hidden from VoiceOver; hidden
/// entirely when the user turns on "Hide character artwork".
struct CandidateCharacterView: View {
    let assetName: String
    var size: CGFloat = 180

    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false

    var body: some View {
        if !hideCharacterArt {
            VStack(spacing: 4) {
                Image(decorative: assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: size, maxHeight: size)
                Text("Candidate art — not final")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityHidden(true)
        }
    }
}

/// A plain status row: label on the left, an explicit text value on the right
/// (state is never conveyed by colour alone).
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

enum StatusCopy {
    static func text(for status: CapabilityStatus) -> String {
        switch status {
        case .available: "Available"
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
        case .voiceInput: "Listening (voice)"
        case .voiceOutput: "Speaking (voice)"
        case .reminders: "Reminders"
        case .connectedAccounts: "Connected accounts"
        case .cloudSync: "Sync between devices"
        }
    }
}

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
            switch assetName {
            // Whole Doddy poses (ADR-299): hello is the wave, played once from the pack's whole
            // wave strip (ADR-380); "on the way" is the tiptoe.
            case "Doddy_waving": DoddyMotionView(motion: .wave, height: size)
            case "Doddy_approaching": WholeDoddyView(pose: .tiptoe, height: size)
            case "Doddy_listening": UploadedCharacterView(assetName: "UploadedDoddy_Listening", height: size)
            default: UploadedCharacterView(assetName: "UploadedDoddy_Sitting", height: size)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.canvas)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Theme.ink.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.secondaryText, lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityContrast) private var contrast

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
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(tint.opacity(isEnabled ? 0.9 : 0.45), lineWidth: 1.5)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0), value: configuration.isPressed)
    }
}

/// Immediate physical feedback for large, quiet cards that open an existing route.
struct TactileCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0), value: configuration.isPressed)
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
    /// Doddy's facepalm beside the message (ADR-299), for a whole screen that failed (a save,
    /// loading notes). Small inline problems leave it off.
    var showsDoddy = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsDoddy { WholeDoddyView(pose: .facepalm, height: 64) }
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.error)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        // One element, as when this was only a Label, so identifiers and VoiceOver land on it.
        .accessibilityElement(children: .combine)
    }
}

enum StatusCopy {
    static func text(for status: CapabilityStatus) -> String {
        switch status {
        case .available: NSLocalizedString("Available", comment: "")
        case .limited(let note): "Limited · \(note)"
        case .needsSetup(let note): "Needs setup · \(note)"
        case .notImplemented(let milestone) where milestone == "unscheduled": NSLocalizedString("Not built · not scheduled", comment: "")
        case .notImplemented(let milestone): "Not built yet · planned \(milestone)"
        }
    }
}

extension Capability {
    var displayName: String {
        switch self {
        case .memoryStorage: NSLocalizedString("Saving memories", comment: "")
        case .memoryRecall: NSLocalizedString("Finding memories", comment: "")
        case .cloudAssistant: NSLocalizedString("AI answers", comment: "")
        case .textAssistant: NSLocalizedString("Typed AI questions", comment: "")
        case .voiceInput: NSLocalizedString("Listening (voice)", comment: "")
        case .voiceOutput: NSLocalizedString("Speaking (voice)", comment: "")
        case .reminders: NSLocalizedString("Reminders", comment: "")
        case .connectedAccounts: NSLocalizedString("Connected accounts", comment: "")
        case .cloudSync: NSLocalizedString("Sync between devices", comment: "")
        case .systemShortcut: NSLocalizedString("Shortcut and Back Tap", comment: "")
        case .pushUpdates: NSLocalizedString("Updates as notifications", comment: "")
        case .textUpdates: NSLocalizedString("Updates by text message", comment: "")
        case .phoneCalls: NSLocalizedString("Phone calls with Doddy", comment: "")
        case .newsDigests: NSLocalizedString("Daily news message", comment: "")
        case .noteReminders: NSLocalizedString("Reminders on notes", comment: "")
        }
    }
}

extension MemorySource {
    var displayName: String {
        switch self {
        case .explicitText: NSLocalizedString("Your typed note", comment: "")
        case .explicitVoice: NSLocalizedString("Your voice note", comment: "")
        case .sharedContent: NSLocalizedString("Shared into Doddy", comment: "")
        case .importedLegacyUnknown: NSLocalizedString("Imported, date unknown", comment: "")
        case .importedFile: NSLocalizedString("Imported from a file", comment: "")
        case .sampleFixture: NSLocalizedString("Sample", comment: "")
        }
    }
}

extension MemoryCategory {
    var displayName: String {
        switch self {
        case .fact: NSLocalizedString("Fact", comment: "")
        case .preference: NSLocalizedString("Preference", comment: "")
        case .commitment: NSLocalizedString("Commitment", comment: "")
        case .recommendation: NSLocalizedString("Recommendation", comment: "")
        case .decision: NSLocalizedString("Decision", comment: "")
        case .item: NSLocalizedString("Item", comment: "")
        case .place: NSLocalizedString("Place", comment: "")
        case .intention: NSLocalizedString("Intention", comment: "")
        case .other: NSLocalizedString("Other", comment: "")
        case .list: NSLocalizedString("List", comment: "")
        }
    }
}

/// What this device can do that the iPhone-only parts of Doddy need (ADR-337).
enum DeviceSupport {
    /// Accessibility › Touch › Back Tap is an iPhone setting; iPad has none.
    @MainActor static var hasBackTap: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    /// Live Activities: every iPhone, and iPad from iPadOS 26 (ADR-453; earlier iPads have none, so
    /// shopping mode is hidden there instead of saying "turn them on in Settings", ADR-432).
    @MainActor static var hasLiveActivities: Bool {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return true
        case .pad:
            if #available(iOS 26.0, *) { return true }
            return false
        default:
            return false
        }
    }
    /// The Dynamic Island and the styles for it: iPhone only (ADR-432, ADR-453).
    @MainActor static var hasDynamicIsland: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    /// The sidebar replaces the tab bar on a wide screen (ADR-430), but not on an iPhone: a large
    /// iPhone in landscape is regular width too, and keeps the tab bar.
    @MainActor static var hasSidebar: Bool { UIDevice.current.userInterfaceIdiom != .phone }
    /// Only an iPhone places a phone call itself. iPad shows Doddy's number without a call link (ADR-437).
    @MainActor static var hasPhoneCalls: Bool { UIDevice.current.userInterfaceIdiom == .phone }
}

/// One readable column on a wide screen (ADR-337, ADR-437): content at most 760 pt wide and
/// centred, while what comes after it (a background) still fills the screen. Compact width
/// (every iPhone in portrait, iPad Slide Over) is unchanged.
struct ReadableColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? 760 : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func readableColumn() -> some View { modifier(ReadableColumn()) }
}

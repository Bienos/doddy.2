import SwiftUI

/// Settings → Voice → Dynamic Island style (ADR-239): the owner's V4 boards that have a voice
/// conversation state, and Whole Doddy (ADR-264). Each row shows the island drawn by the same views the widget uses, for a
/// state picked at the top. It is a preview: nothing here is a running conversation, and the
/// real island also depends on the phone (size, other apps' activities, text size).
struct IslandStyleView: View {
    @AppStorage(PreferenceKey.islandStyle) private var styleRaw = IslandStyle.preferredDefault.rawValue
    @State private var previewState = PreviewState.listening

    enum PreviewState: String, CaseIterable, Identifiable {
        case listening = "Listening", speaking = "Speaking", thinking = "Working on it", muted = "Muted"
        var id: String { rawValue }

        var content: DoddyVoiceAttributes.ContentState {
            switch self {
            case .listening: .init(status: .listening, isMuted: false)
            case .speaking: .init(status: .speaking, isMuted: false)
            case .thinking: .init(status: .thinking, isMuted: false)
            case .muted: .init(status: .listening, isMuted: true)
            }
        }
    }

    /// A fixed start, so the preview's timer reads like a conversation already running.
    @State private var previewStart = Date().addingTimeInterval(-42)

    var body: some View {
        Form {
            Section {
                Picker("Preview", selection: $previewState) {
                    ForEach(PreviewState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("How the island looks while you talk to Doddy from another app. These are previews, not a running conversation.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(IslandStyle.allCases, id: \.self) { style in
                Section {
                    Button {
                        styleRaw = style.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(style.displayName).font(.headline)
                                Spacer()
                                if styleRaw == style.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accentText)
                                        .accessibilityLabel("Selected")
                                }
                            }
                            Text(style.summary)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                            IslandPreview(scene: scene(for: style), startedAt: previewStart, muted: previewState == .muted)
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(styleRaw == style.rawValue ? .isSelected : [])
                    .accessibilityIdentifier("settings.islandStyle.\(style.rawValue)")
                }
            }
            Section {
                Text("Designs: the owner's Dynamic Island pack (V4); Whole Doddy uses the owner's pose pack. While a note, plan or reminder waits for you, or while Doddy translates, the island switches to its own design whatever you pick here. In Whole Doddy, Doddy's pose changes instead, except while translating.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Dynamic Island")
    }

    private func scene(for style: IslandStyle) -> IslandScene {
        var state = previewState.content
        state.islandStyle = style
        return state.islandScene(isStale: false)
    }
}

/// The expanded and compact island in black capsules, from the widget's own views. The
/// buttons are drawn but do nothing here.
struct IslandPreview: View {
    let scene: IslandScene
    let startedAt: Date
    var muted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                HStack {
                    IslandLabelView(scene: scene)
                    Spacer(minLength: 8)
                    IslandTimeView(scene: scene, startedAt: startedAt)
                }
                IslandBottomView(scene: scene, startedAt: startedAt) {
                    HStack(spacing: 6) {
                        IslandPillLabel(title: muted ? "Unmute" : "Mute",
                                        systemImage: muted ? "mic.fill" : "mic.slash.fill", prominent: muted)
                        IslandPillLabel(title: "Stop", systemImage: "stop.fill")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 371)
            .background(Color.islandBlack, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            // The light behind Whole Doddy reaches past his column; the island's edge cuts it,
            // as iOS's island does (ADR-615).
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    IslandCompactLeadingView(scene: scene)
                    Spacer(minLength: 60)
                    IslandCompactTrailingView(scene: scene, startedAt: startedAt)
                        .frame(width: 52)
                }
                .frame(width: 230, height: 36.67)
                .background(Color.islandBlack, in: Capsule())
                IslandMinimalView(scene: scene, startedAt: startedAt)
                    .frame(width: 45, height: 36.67)
                    .background(Color.islandBlack, in: Capsule())
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Settings → Voice row.
struct IslandStyleLinkRow: View {
    @AppStorage(PreferenceKey.islandStyle) private var styleRaw = IslandStyle.preferredDefault.rawValue

    var body: some View {
        NavigationLink {
            IslandStyleView()
        } label: {
            StatusRow(title: "Dynamic Island style", value: IslandStyle.stored(styleRaw).displayName)
        }
        .accessibilityIdentifier("settings.islandStyle")
    }
}

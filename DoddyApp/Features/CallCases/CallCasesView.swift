import DoddyCore
import SwiftUI

/// Settings → Phone calls → Calls for you (ADR-500): the calls Doddy made or may make for the
/// user, each with its card, answer, cost and deletion receipts, kept on this iPhone.
/// Not compiled or run on a device yet.
struct CallCasesView: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(ProfileStore.self) private var profiles
    @State private var model: CallCasesModel?
    @State private var editor: EditorItem?
    /// Opened once the editor sheet has closed.
    @State private var preparedCase: StoredCallCase?
    @State private var opened: OpenedCase?
    @State private var exportText: String?

    var body: some View {
        Group {
            if let model {
                list(model)
            } else {
                ProgressView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Calls for you")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { open in
            if let model {
                CallCaseView(model: open.model, list: model,
                             onOpen: { opened = OpenedCase(open: $0, in: model) },
                             onClose: { opened = nil })
                    // A replaced card is a new screen, not the old one's state with a new record.
                    .id(open.id)
            }
        }
        .sheet(item: $editor, onDismiss: {
            if let preparedCase, let model {
                self.preparedCase = nil
                opened = OpenedCase(open: preparedCase, in: model)
            }
        }) { item in
            if let model {
                NavigationStack {
                    CallBriefEditorView(list: model, draft: item.draft, replacing: nil) { saved in
                        preparedCase = saved
                        editor = nil
                    }
                }
            }
        }
        .task {
            if model == nil {
                model = CallCasesModel(backend: ServerConfig.client(), repository: environment.callCaseRepository,
                                       describe: { UpdatesModel.text(for: $0) })
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func list(_ model: CallCasesModel) -> some View {
        Form {
            Section {
                Text("Doddy calls a business or a person for you in Polish, says it's an AI calling on your behalf, asks one question and brings the answer back as a card. Nothing is dialled until you approve the card, and Doddy never agrees to anything, pays or gives your PESEL or address unless you tick it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if let blocker = model.blocker {
                    Label(blocker, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                    if model.availability?.phoneVerified == false {
                        NavigationLink("Verify my number") { UpdatesSettingsView() }
                    }
                } else {
                    Button {
                        editor = EditorItem(draft: CallBriefDraft(principalName: firstName))
                    } label: {
                        Label("New call", systemImage: "phone.badge.plus")
                    }
                    .disabled(model.availability == nil)
                    .accessibilityIdentifier("callCases.new")
                }
            }

            if let problem = model.loadProblem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                    Button("Try again") { Task { await model.load() } }
                }
            }

            if !model.cases.isEmpty {
                Section("Your calls") {
                    ForEach(model.cases) { record in
                        Button {
                            opened = OpenedCase(open: record, in: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title).font(.headline).foregroundStyle(Theme.ink)
                                Text(record.brief.question).lineLimit(2).foregroundStyle(Theme.ink)
                                Text("\(CallCaseText.state(record)) · \(DateText.full(record.createdAt))")
                                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await model.deleteLocal(record.id) } }
                        }
                    }
                }
                Section("Cost") {
                    let summary = model.costSummary
                    LabeledContent("Calls", value: "\(summary.cases)")
                    LabeledContent("Answered", value: "\(summary.answered)")
                    LabeledContent("Known cost, all calls", value: String(format: "%.4f USD", Double(summary.knownTotalMicros) / 1_000_000))
                    if let per = summary.perAnsweredMicros {
                        LabeledContent("Per answered call", value: String(format: "%.4f USD", Double(per) / 1_000_000))
                    }
                    if summary.casesWithUnknownCost > 0 {
                        Text(String(format: NSLocalizedString("%lld calls still have a part of their cost unknown or pending, so no average is shown for them.", comment: ""),
                                    summary.casesWithUnknownCost))
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Text("Phone line and transcript from Twilio, Doddy's voice from ElevenLabs, the answer card from Claude. Twilio's price arrives after the call; the rest is estimated from documented prices.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Section {
                    Button("Export my calls") { Task { exportText = await model.exportText() } }
                    if let exportText {
                        ShareLink(item: exportText, preview: SharePreview("Doddy calls.json")) {
                            Label("Share the export", systemImage: "square.and.arrow.up")
                        }
                    }
                    Text("Transcripts are kept only on this iPhone once the answer card is saved here. Deleting a call here deletes it from this iPhone.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            } else if model.hasLoaded && model.loadProblem == nil {
                Section { Text("No calls yet.").foregroundStyle(Theme.secondaryText) }
            }

            if let message = model.message {
                Section { Label(message, systemImage: "info.circle").accessibilityIdentifier("callCases.message") }
            }
        }
        .disabled(model.isWorking)
        .overlay { if model.isWorking { ProgressView() } }
        .refreshable { await model.load() }
    }

    /// "W imieniu …" starts from the first word of the approved name in About you; the user can change it.
    private var firstName: String {
        profiles.profile.value(.name)?.split(separator: " ").first.map(String.init) ?? ""
    }
}

/// The call on screen, with its own model, so withdrawing or replacing the card in the list never
/// leaves the screen blank.
struct OpenedCase: Identifiable, Hashable {
    let id: UUID
    let model: CallCaseModel

    @MainActor
    init(open record: StoredCallCase, in list: CallCasesModel) {
        id = record.id
        model = list.caseModel(for: record, activity: CallLiveActivity.shared)
    }

    static func == (a: OpenedCase, b: OpenedCase) -> Bool { a.id == b.id && a.model === b.model }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct EditorItem: Identifiable {
    let id = UUID()
    let draft: CallBriefDraft
}

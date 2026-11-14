import DoddyCore
import SwiftUI

/// The brief for a call (ADR-500, ADR-501): who, why, the one question, the facts Doddy may say
/// (only ticked ones leave this iPhone), and how long. "Prepare the card" sends it; the server
/// makes the card from exactly what it will send, and nothing is dialled until that card is
/// approved. Opened from "who and why" (decision 2026-11-13-calls-one-field-brief) it starts with
/// the details folded under one row; they open by themselves when one of them needs fixing.
/// Not compiled or run on a device yet.
struct CallBriefEditorView: View {
    let list: CallCasesModel
    let replacing: StoredCallCase?
    /// What Doddy says about how it filled the brief in, shown first.
    let notes: [String]
    /// False when pushed from the first screen: Back goes there instead.
    let showsCancel: Bool
    let onPrepared: (StoredCallCase) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CallBriefDraft
    @State private var newFact = ""
    @State private var pickingContact = false
    /// The genitive follows the name until the user edits it.
    @State private var genitiveEdited = false
    /// On whose behalf, where the number came from, the facts, what Doddy must not do and the length.
    @State private var showDetails: Bool

    init(list: CallCasesModel, draft: CallBriefDraft, replacing: StoredCallCase?, detailsShown: Bool = true,
         notes: [String] = [], showsCancel: Bool = true, onPrepared: @escaping (StoredCallCase) -> Void) {
        self.list = list
        self.replacing = replacing
        self.notes = notes
        self.showsCancel = showsCancel
        self.onPrepared = onPrepared
        _draft = State(initialValue: draft)
        _genitiveEdited = State(initialValue: draft.principalGenitive != PolishGenitive.suggest(draft.principalName))
        _showDetails = State(initialValue: detailsShown || draft.problems.contains(where: Self.isDetailProblem))
    }

    private var maxMinutes: Int { max(1, min(5, (list.availability?.maxDurationSecs ?? 300) / 60)) }

    /// A problem in a field under Details: those open, so the fix is in view.
    private static func isDetailProblem(_ problem: CallBriefProblem) -> Bool {
        switch problem {
        case .missingPrincipal, .tooManyFacts, .sensitiveFactKind, .peselFactInvalid: true
        default: false
        }
    }

    /// One line under the folded Details row: what Doddy says it calls for, the length, the facts it may say.
    private var detailsSummary: String {
        var parts = [String(format: NSLocalizedString("Doddy says: w imieniu %@", comment: ""), draft.principalGenitive),
                     String(format: NSLocalizedString("At most %lld min", comment: ""), draft.maxDurationSecs / 60)]
        let ticked = draft.tickedFacts.count
        if ticked > 0 { parts.append(String(format: NSLocalizedString("Facts Doddy may say: %lld", comment: ""), ticked)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Form {
            if !notes.isEmpty {
                Section {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Label(note, systemImage: "info.circle")
                    }
                }
            }
            whoSection
            Section {
                TextField("Goal, in one sentence", text: $draft.goal, axis: .vertical)
                    .accessibilityIdentifier("callBrief.goal")
                TextField("The one question Doddy asks", text: $draft.question, axis: .vertical)
                    .accessibilityIdentifier("callBrief.question")
            } header: {
                Text("Goal and question")
            } footer: {
                Text("Doddy asks this question word for word, may ask one short follow-up, then thanks and ends. Ask, don't agree: \"Is the laptop ready?\", not \"Please book me in.\"")
            }
            Section {
                Button {
                    withAnimation { showDetails.toggle() }
                } label: {
                    HStack {
                        Text("Details").foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("callBrief.details")
            } footer: {
                if !showDetails { Text(detailsSummary) }
            }
            if showDetails {
                behalfSection
                factsSection
                Section {
                    Label("Agree to anything, book, order or confirm", systemImage: "xmark.circle")
                    Label("Pay or give card or account numbers", systemImage: "xmark.circle")
                    Label("Give your PESEL or address, unless ticked above as one", systemImage: "xmark.circle")
                } header: {
                    Text("Doddy must not")
                } footer: {
                    Text("If they ask for anything outside the card, Doddy says it will check with you and call back.")
                }
                Section {
                    Stepper(value: Binding(get: { draft.maxDurationSecs / 60 }, set: { draft.maxDurationSecs = $0 * 60 }), in: 1...maxMinutes) {
                        Text(String(format: NSLocalizedString("At most %lld min", comment: ""), draft.maxDurationSecs / 60))
                    }
                } header: {
                    Text("Length")
                } footer: {
                    Text("Doddy says goodbye when the time is up. Calls happen only between 8:00 and 23:00 Polish time, and the whole call must fit.")
                }
            }

            let problems = draft.problems
            if !problems.isEmpty {
                Section("Before the card can be made") {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        Label(CallCaseText.problem(problem), systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.error)
                    }
                }
            }
            if let message = list.message {
                Section { Label(message, systemImage: "info.circle").foregroundStyle(Theme.error) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(replacing == nil ? "New call" : "Change the brief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Prepare the card") {
                    Task {
                        if let saved = await list.prepare(draft, replacing: replacing) { onPrepared(saved) }
                    }
                }
                .disabled(!draft.problems.isEmpty || list.isWorking)
                .accessibilityIdentifier("callBrief.prepare")
            }
        }
        .disabled(list.isWorking)
        .overlay { if list.isWorking { ProgressView() } }
        // The server's longest call can be shorter than the 4-minute default.
        .onAppear { draft.maxDurationSecs = min(draft.maxDurationSecs, maxMinutes * 60) }
        .onChange(of: maxMinutes) { draft.maxDurationSecs = min(draft.maxDurationSecs, maxMinutes * 60) }
        .background(ContactNumberPicker(isPresented: $pickingContact) { picked in
            draft.phone = picked.number
            draft.source = .contacts
            draft.sourceLabel = picked.name
            if draft.calleeName.isEmpty { draft.calleeName = picked.name }
        })
    }

    private var whoSection: some View {
        Section {
            TextField("Name (for example: Serwis Komputerowy Bajt)", text: $draft.calleeName)
                .textContentType(.organizationName)
                .accessibilityIdentifier("callBrief.callee")
            TextField("Phone number", text: Binding(get: { draft.phone }, set: { value in
                // A number changed by hand no longer comes from the contact.
                if draft.source == .contacts, value != draft.phone { draft.source = .typed; draft.sourceLabel = nil }
                draft.phone = value
            }))
            .keyboardType(.phonePad)
            .accessibilityIdentifier("callBrief.phone")
            Button {
                pickingContact = true
            } label: {
                Label("Pick from Contacts", systemImage: "person.crop.circle")
            }
            // Where the number came from is a detail: the card says it either way.
            if showDetails {
                Picker("Where the number came from", selection: $draft.source) {
                    Text("Typed in").tag(CallNumberSource.typed)
                    Text("From a note").tag(CallNumberSource.note)
                    if draft.source == .contacts { Text("From Contacts").tag(CallNumberSource.contacts) }
                }
                if draft.source != .contacts {
                    TextField("Where exactly (optional, e.g. their website)", text: Binding(get: { draft.sourceLabel ?? "" },
                                                                                           set: { draft.sourceLabel = $0.isEmpty ? nil : $0 }))
                }
            }
        } header: {
            Text("Who Doddy calls")
        } footer: {
            Text("Polish mobile, landline and 800 numbers only. Never emergency, premium or foreign numbers. The card shows where the number came from.")
        }
    }

    private var behalfSection: some View {
        Section {
            TextField("Your first name", text: Binding(get: { draft.principalName }, set: { value in
                draft.principalName = value
                if !genitiveEdited { draft.principalGenitive = PolishGenitive.suggest(value) }
            }))
            .textContentType(.givenName)
            .accessibilityIdentifier("callBrief.principal")
            TextField("As Doddy says it: \"w imieniu …\"", text: Binding(get: { draft.principalGenitive }, set: { value in
                genitiveEdited = true
                draft.principalGenitive = value
            }))
            .accessibilityIdentifier("callBrief.genitive")
        } header: {
            Text("On whose behalf")
        } footer: {
            Text("Doddy opens with: \"Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu …\". Check the form of your name after \"w imieniu\".")
        }
    }

    private var factsSection: some View {
        Section {
            ForEach($draft.facts) { $fact in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $fact.ticked) {
                        Text(fact.text)
                    }
                    Picker("Kind", selection: $fact.kind) {
                        Text("General").tag(CallFactKind.general)
                        Text("Reference number").tag(CallFactKind.reference)
                        Text("Date").tag(CallFactKind.date)
                        Text("Device").tag(CallFactKind.device)
                        Text("Contact").tag(CallFactKind.contact)
                        Text("PESEL").tag(CallFactKind.pesel)
                        Text("Address").tag(CallFactKind.address)
                    }
                    .pickerStyle(.menu)
                    .font(.footnote)
                }
            }
            .onDelete { draft.facts.remove(atOffsets: $0) }
            HStack {
                TextField("A fact, e.g. order number 12345", text: $newFact)
                    .accessibilityIdentifier("callBrief.newFact")
                Button("Add") {
                    let text = newFact.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft.facts.append(.suggested(text))
                    newFact = ""
                }
                .disabled(newFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("What Doddy may say")
        } footer: {
            Text("Only ticked facts leave this iPhone, at most five. A PESEL or an address is left unticked when you add it: tick it, and mark it as one, only if Doddy really needs to give it.")
        }
    }
}

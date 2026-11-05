import DoddyCore
import SwiftUI

/// The brief for a call (ADR-500, ADR-501): who, why, the one question, the facts Doddy may say
/// (only ticked ones leave this iPhone), and how long. "Prepare the card" sends it; the server
/// makes the card from exactly what it will send, and nothing is dialled until that card is
/// approved. Not compiled or run on a device yet.
struct CallBriefEditorView: View {
    let list: CallCasesModel
    let replacing: StoredCallCase?
    let onPrepared: (StoredCallCase) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CallBriefDraft
    @State private var newFact = ""
    @State private var pickingContact = false
    /// The genitive follows the name until the user edits it.
    @State private var genitiveEdited = false

    init(list: CallCasesModel, draft: CallBriefDraft, replacing: StoredCallCase?, onPrepared: @escaping (StoredCallCase) -> Void) {
        self.list = list
        self.replacing = replacing
        self.onPrepared = onPrepared
        _draft = State(initialValue: draft)
        _genitiveEdited = State(initialValue: draft.principalGenitive != PolishGenitive.suggest(draft.principalName))
    }

    private var maxMinutes: Int { max(1, min(5, (list.availability?.maxDurationSecs ?? 300) / 60)) }

    var body: some View {
        Form {
            whoSection
            behalfSection
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
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
            Picker("Where the number came from", selection: $draft.source) {
                Text("Typed in").tag(CallNumberSource.typed)
                Text("From a note").tag(CallNumberSource.note)
                if draft.source == .contacts { Text("From Contacts").tag(CallNumberSource.contacts) }
            }
            if draft.source != .contacts {
                TextField("Where exactly (optional, e.g. their website)", text: Binding(get: { draft.sourceLabel ?? "" },
                                                                                       set: { draft.sourceLabel = $0.isEmpty ? nil : $0 }))
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

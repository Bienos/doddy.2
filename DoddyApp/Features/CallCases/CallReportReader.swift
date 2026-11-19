import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// Native, selectable evidence report. Export uses the system's user-controlled file picker.
struct CallReportReader: View {
    let report: CallReport
    @State private var exporting = false
    @State private var exportFailed = false
    private var polish: Bool { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) == .polish }

    var body: some View {
        Form {
            Section {
                Text(verbatim: report.objective).font(.headline).textSelection(.enabled)
                Text(CallCaseText.outcome(CallOutcome(rawValue: report.outcome) ?? .unknown))
            }
            ForEach(Array(report.orderedFacts.enumerated()), id: \.offset) { _, fact in
                Section {
                    Text(verbatim: fact.value).font(.body.weight(.medium)).textSelection(.enabled)
                    if fact.certainty != "reported" {
                        Label { Text(verbatim: polish ? "Niepewne" : "Uncertain") } icon: { Image(systemName: "questionmark.circle") }
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text(verbatim: "„\(fact.evidence.quote)”").textSelection(.enabled)
                    Text(verbatim: "\(polish ? "Wiersz" : "Line") \(fact.evidence.line + 1)")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                } header: { Text(verbatim: CallReport.factTitle(fact.kind, polish: polish)) }
            }
            if report.facts.isEmpty {
                Section {
                    Text(verbatim: polish ? "Brak szczegółów, które udało się sprawdzić w zapisie rozmowy."
                         : "No details could be verified against the call record.")
                }
            }
            if report.verification.rejected > 0 || !(report.verification.uncoveredLines?.isEmpty ?? true) {
                Section {
                    Text(verbatim: polish ? "Nie wszystkie szczegóły udało się sprawdzić. Raport może być niepełny."
                         : "Some details still need review. The report may be incomplete.")
                }
            }
            Section {
                Button { exporting = true } label: {
                    Label { Text(verbatim: polish ? "Zapisz raport jako plik" : "Save report as a file") }
                    icon: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.canvas)
        .navigationTitle(CallReport.title(polish: polish))
        .fileExporter(isPresented: $exporting, document: CallReportFile(data: Data(report.markdown(polish: polish).utf8)),
                      contentType: CallReportFile.contentType, defaultFilename: "Doddy-call-report.md") { result in
            if case .failure = result { exportFailed = true }
        }
        .alert(polish ? "Nie udało się zapisać raportu" : "The report couldn't be saved", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        }
    }
}

private struct CallReportFile: FileDocument {
    static var contentType: UTType { UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText }
    static var readableContentTypes: [UTType] { [contentType, .plainText] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

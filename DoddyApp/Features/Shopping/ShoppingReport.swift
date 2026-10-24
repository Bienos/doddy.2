import DoddyCore
import SwiftUI

// The shopping report as a PDF (docs/implementation/SHOPPING.md 3, design/shopping-mode-v0.1/report):
// drawn on this iPhone from the task's stored result, two A4 pages in fixed light colours so it looks
// the same wherever it is sent. No model writes it and nothing leaves the iPhone to make it: every
// price, shop, link and time is the one the server's code registered, and Doddy's words are the ones
// already on the result card. The file goes to the temporary folder and is shared from there.

struct ShoppingReport {
    let title: String
    let words: String
    let result: ErrandResult
    let shopping: ShoppingResult
    let language: NotificationLanguage
    let madeAt: Date

    /// A4 in PDF points.
    static let pageSize = CGSize(width: 595.28, height: 841.89)

    /// Writes the two pages to `url`. Must run on the main actor (ImageRenderer).
    @MainActor
    func writePDF(to url: URL) throws {
        var box = CGRect(origin: .zero, size: Self.pageSize)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        let pages: [AnyView] = [AnyView(ReportPageOne(report: self)), AnyView(ReportPageTwo(report: self))]
        for page in pages {
            let renderer = ImageRenderer(content: page
                .frame(width: Self.pageSize.width, height: Self.pageSize.height)
                .environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(Self.pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
    }

    /// A fresh file in the temporary folder, named after the task.
    @MainActor
    func temporaryFile() throws -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: " ")
        let name = String(format: NSLocalizedString("Doddy report – %@", comment: "PDF file name"), safe)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShoppingReports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: url)
        try writePDF(to: url)
        return url
    }

    // MARK: What the pages show

    var picks: [(pick: ShoppingPick, offer: ShoppingOffer)] { shopping.picksInDisplayOrder }
    var best: (pick: ShoppingPick, offer: ShoppingOffer)? { picks.first { $0.pick.role == .best } }

    func price(_ money: Money) -> String { money.text(language) }

    func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    func evidenceLine(_ offer: ShoppingOffer) -> String {
        "\(offer.evidence.label(language)) \(time(offer.seenAt))"
    }
}

/// Fixed light colours (Brand Guidelines V2.2): the PDF looks the same in dark mode and in print.
private enum Paper {
    static let paper = Color(red: 0xFF / 255, green: 0xF7 / 255, blue: 0xE9 / 255)
    static let ink = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x15 / 255)
    static let quiet = Color(red: 0xF5 / 255, green: 0xEA / 255, blue: 0xD8 / 255)
    static let line = Color(red: 0xDF / 255, green: 0xD5 / 255, blue: 0xC6 / 255)
    static let muted = Color(red: 0x65 / 255, green: 0x5F / 255, blue: 0x56 / 255)
    static let accentText = Color(red: 0xA6 / 255, green: 0x4B / 255, blue: 0x00 / 255)
    static let orange = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x00 / 255)
    static let ok = Color(red: 0x32 / 255, green: 0x67 / 255, blue: 0x46 / 255)
    static let error = Color(red: 0xA3 / 255, green: 0x34 / 255, blue: 0x2E / 255)
}

private struct ReportHeader: View {
    let report: ShoppingReport
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                Image("DoddyWordmark").resizable().renderingMode(.template).scaledToFit()
                    .frame(height: 26).foregroundStyle(Paper.ink)
                    .accessibilityLabel("Doddy")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SHOPPING REPORT").font(.system(size: 9, weight: .bold)).kerning(0.8).foregroundStyle(Paper.ink)
                    Text(report.madeAt.formatted(date: .complete, time: .shortened)).font(.system(size: 8)).foregroundStyle(Paper.muted)
                    Text(subtitle).font(.system(size: 8)).foregroundStyle(Paper.muted).lineLimit(1)
                }
            }
            Rectangle().fill(Paper.ink).frame(height: 1)
        }
    }
}

private struct ReportFooter: View {
    let page: Int

    var body: some View {
        VStack(spacing: 6) {
            Rectangle().fill(Paper.line).frame(height: 0.5)
            HStack(alignment: .top) {
                Text("Doddy is an AI. Prices and availability can change after the time they were checked. Check the price in the shop before you pay.")
                    .font(.system(size: 7.5)).foregroundStyle(Paper.muted)
                Spacer(minLength: 12)
                Text(verbatim: "\(page) / 2").font(.system(size: 7.5)).foregroundStyle(Paper.muted)
            }
        }
    }
}

private struct ReportPageOne: View {
    let report: ShoppingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReportHeader(report: report, subtitle: report.title)
            Text(report.title).font(.system(size: 24, weight: .heavy)).foregroundStyle(Paper.ink).lineLimit(2)
            words
            if !report.shopping.priorities.isEmpty { priorities }
            if let best = report.best { pickCard(best.pick, best.offer) }
            table
            howChosen
            Spacer(minLength: 0)
            ReportFooter(page: 1)
        }
        .padding(.horizontal, 42).padding(.top, 36).padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Paper.paper)
    }

    private var words: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Paper.orange).frame(width: 2.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\u{201E}\(report.words)\u{201D}").font(.system(size: 11)).foregroundStyle(Paper.ink)
                Text("YOUR WORDS, UNCHANGED").font(.system(size: 7, weight: .semibold)).kerning(0.6).foregroundStyle(Paper.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var priorities: some View {
        HStack(spacing: 6) {
            Text("Your order:").font(.system(size: 8.5)).foregroundStyle(Paper.muted)
            ForEach(Array(report.shopping.priorities.enumerated()), id: \.offset) { index, priority in
                HStack(spacing: 4) {
                    Text(verbatim: "\(index + 1)").font(.system(size: 7, weight: .bold)).foregroundStyle(Paper.paper)
                        .frame(width: 13, height: 13).background(Circle().fill(Paper.ink))
                    Text(priority).font(.system(size: 9, weight: .semibold)).foregroundStyle(Paper.ink)
                }
                .padding(.leading, 3).padding(.trailing, 8).padding(.vertical, 2)
                .overlay(Capsule().stroke(Paper.ink, lineWidth: 0.8))
            }
        }
    }

    private func pickCard(_ pick: ShoppingPick, _ offer: ShoppingOffer) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(pick.role.label(report.language).uppercased()).font(.system(size: 7.5, weight: .bold)).kerning(0.8).foregroundStyle(Paper.accentText)
                Text(offer.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Paper.ink).lineLimit(2)
                Text(report.price(offer.price)).font(.system(size: 30, weight: .heavy)).foregroundStyle(Paper.ink)
                HStack(spacing: 10) {
                    Text(offer.shop).font(.system(size: 9, weight: .semibold)).foregroundStyle(Paper.ink)
                    if let delivery = offer.delivery { Text(delivery).font(.system(size: 9)).foregroundStyle(Paper.ink) }
                }
                Text(report.evidenceLine(offer)).font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(offer.evidence == .shopPage ? Paper.ok : Paper.muted)
                VStack(alignment: .leading, spacing: 3) {
                    bullet(pick.why)
                    if let tradeoff = pick.tradeoff { bullet(tradeoff) }
                    if let notes = offer.notes { bullet(notes) }
                    if let over = pick.overBudget {
                        bullet(String(format: NSLocalizedString("%@ over your budget", comment: ""), report.price(over)), color: Paper.error)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Image("WholeDoddy_kneeling_inspect").resizable().scaledToFit().frame(width: 78)
                    .accessibilityHidden(true)
                if let stats = report.shopping.stats {
                    Text(String(format: NSLocalizedString("%lld offers, %lld shops.", comment: ""), stats.offersSeen, stats.shops))
                        .font(Theme.hand(.footnote)).foregroundStyle(Paper.ink).multilineTextAlignment(.center)
                }
            }
            .frame(width: 96)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Paper.quiet))
    }

    private func bullet(_ text: String, color: Color = Paper.ink) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(Paper.orange).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The offers worth a look").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Paper.ink).padding(.bottom, 6)
            HStack {
                Text("OFFER").frame(maxWidth: .infinity, alignment: .leading)
                Text("PRICE").frame(width: 76, alignment: .trailing)
                Text("SHOP").frame(width: 92, alignment: .leading)
                Text("PRICE FROM").frame(width: 110, alignment: .leading)
            }
            .font(.system(size: 6.5, weight: .semibold)).kerning(0.5).foregroundStyle(Paper.muted)
            .padding(.bottom, 4)
            Rectangle().fill(Paper.ink).frame(height: 0.8)
            ForEach(Array(report.picks.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.pick.role.label(report.language).uppercased()).font(.system(size: 6.5, weight: .bold)).foregroundStyle(Paper.accentText)
                        Text(row.offer.title).font(.system(size: 8.5)).foregroundStyle(Paper.ink).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(report.price(row.offer.price)).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Paper.ink)
                        if let over = row.pick.overBudget {
                            Text(String(format: NSLocalizedString("+%@", comment: "over budget"), report.price(over))).font(.system(size: 7)).foregroundStyle(Paper.error)
                        }
                    }
                    .frame(width: 76, alignment: .trailing)
                    Text(row.offer.shop).font(.system(size: 8.5)).foregroundStyle(Paper.ink).frame(width: 92, alignment: .leading).lineLimit(2)
                    Text(report.evidenceLine(row.offer)).font(.system(size: 7.5)).foregroundStyle(Paper.muted).frame(width: 110, alignment: .leading).lineLimit(2)
                }
                .padding(.vertical, 5)
                .background(row.pick.role == .best ? Paper.quiet.opacity(0.6) : Color.clear)
                Rectangle().fill(Paper.line).frame(height: 0.5)
            }
        }
    }

    @ViewBuilder
    private var howChosen: some View {
        if !report.shopping.howChosen.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("How I chose").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Paper.ink)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(report.shopping.howChosen.enumerated()), id: \.offset) { index, line in
                        VStack(alignment: .leading, spacing: 3) {
                            Rectangle().fill(Paper.ink).frame(height: 1)
                            Text(verbatim: "\(index + 1). \(line)").font(.system(size: 8.5)).foregroundStyle(Paper.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct ReportPageTwo: View {
    let report: ShoppingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReportHeader(report: report, subtitle: report.title)
            HStack(alignment: .top, spacing: 14) {
                box(title: Text("Watch out for"), mark: "!", markColor: Paper.accentText, lines: report.shopping.watchOuts,
                    empty: Text("Nothing in particular."))
                box(title: Text("Left out, and why"), mark: "×", markColor: Paper.error, lines: report.shopping.rejected,
                    empty: Text("Nothing left out."))
            }
            HStack(alignment: .bottom, spacing: 10) {
                box(title: Text("What I don't know"), mark: "?", markColor: Paper.muted, lines: report.shopping.unknowns,
                    empty: Text("Nothing open that I know of."))
                Image("WholeDoddy_shrug").resizable().scaledToFit().frame(width: 74).accessibilityHidden(true)
            }
            next
            sources
            Text("Doddy put this report together from offers his server's code found and checked. A price without the page it came from is left out. The file was made on this iPhone from the task's result; nobody else received it.")
                .font(.system(size: 7.5)).foregroundStyle(Paper.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ReportFooter(page: 2)
        }
        .padding(.horizontal, 42).padding(.top, 36).padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Paper.paper)
    }

    private func box(title: Text, mark: String, markColor: Color, lines: [String], empty: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title.font(.system(size: 11.5, weight: .bold)).foregroundStyle(Paper.ink)
            if lines.isEmpty {
                empty.font(.system(size: 9)).foregroundStyle(Paper.muted)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mark).font(.system(size: 9, weight: .heavy)).foregroundStyle(markColor)
                    Text(line).font(.system(size: 9)).foregroundStyle(Paper.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Paper.ink, lineWidth: 0.8))
    }

    private var next: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("What next").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Paper.paper)
            if let best = report.best {
                Text(String(format: NSLocalizedString("Buying? Tap \u{201C}Buy at %@\u{201D} in the app. The shop's page opens and you pay there: Apple Pay, BLIK or a card. Doddy doesn't see the payment.", comment: ""), best.offer.shop))
                    .font(.system(size: 9)).foregroundStyle(Paper.paper).fixedSize(horizontal: false, vertical: true)
            }
            Text("Want to wait? Ask Doddy to look again later: prices change.").font(.system(size: 9)).foregroundStyle(Paper.paper)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Paper.ink))
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Where the prices come from").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Paper.ink)
            ForEach(Array(report.shopping.offers.enumerated()), id: \.offset) { index, offer in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(index + 1).").font(.system(size: 8)).foregroundStyle(Paper.muted)
                    Text(offer.url).font(.system(size: 7.5)).foregroundStyle(Paper.ink).lineLimit(1).truncationMode(.middle)
                    Text(verbatim: "· \(report.evidenceLine(offer))").font(.system(size: 7.5)).foregroundStyle(Paper.muted).lineLimit(1)
                }
            }
        }
    }
}

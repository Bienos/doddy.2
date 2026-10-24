import Foundation

// The sums of an invoice, in integer grosze (ADR-633). Doddy "verifies the math, not only the
// language" (research 5.3 step 4): the model never states an amount that code did not compute.
//
// Rounding, stated once and tested:
//  - a line's net value is quantity × net unit price, rounded half up to a grosz;
//  - VAT is worked out per rate on the SUM of the net values of that rate (as a Polish invoice
//    shows it: "suma wartości sprzedaży netto z podziałem na stawki"), rounded half up to a grosz;
//  - gross is net plus VAT.
// Exempt ("zw") and not-subject ("np") lines carry no VAT. Amounts that would overflow are refused.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

public struct InvoiceTotals: Equatable, Sendable, Codable {
    public struct Group: Equatable, Sendable, Codable {
        public let rate: VatRate
        public let netMinor: Int
        public let vatMinor: Int
        public var grossMinor: Int { netMinor + vatMinor }
    }

    /// Net value of each line, in the order of the lines.
    public let lineNetMinor: [Int]
    /// One group per rate used, in the order 23, 8, 5, 0, zw, np.
    public let groups: [Group]

    public var netMinor: Int { groups.reduce(0) { $0 + $1.netMinor } }
    public var vatMinor: Int { groups.reduce(0) { $0 + $1.vatMinor } }
    public var grossMinor: Int { netMinor + vatMinor }

    /// Nil when a line lacks a quantity, a price or a confirmed VAT rate, or a figure is out of
    /// range or would overflow.
    public static func compute(_ lines: [InvoiceLine]) -> InvoiceTotals? {
        guard !lines.isEmpty, lines.count <= InvoiceDraft.maxLines else { return nil }
        var lineNets: [Int] = []
        var byRate: [VatRate: Int] = [:]
        for line in lines {
            guard let quantity = line.quantityMilli, (1...InvoiceDraft.maxQuantityMilli).contains(quantity),
                  let price = line.netUnitPriceMinor, (1...InvoiceDraft.maxUnitPriceMinor).contains(price),
                  let vat = line.vat, vat.isConfirmed else { return nil }
            let (product, overflow) = quantity.multipliedReportingOverflow(by: price)
            guard !overflow else { return nil }
            let net = (product + 500) / 1000
            lineNets.append(net)
            let (sum, sumOverflow) = (byRate[vat.value] ?? 0).addingReportingOverflow(net)
            guard !sumOverflow else { return nil }
            byRate[vat.value] = sum
        }
        let order: [VatRate] = [.percent(23), .percent(8), .percent(5), .percent(0), .exempt, .notSubject]
        let groups = order.compactMap { rate -> Group? in
            guard let net = byRate[rate] else { return nil }
            let (scaled, overflow) = net.multipliedReportingOverflow(by: rate.percent)
            guard !overflow else { return nil }
            return Group(rate: rate, netMinor: net, vatMinor: (scaled + 50) / 100)
        }
        guard groups.count == byRate.count else { return nil }
        return InvoiceTotals(lineNetMinor: lineNets, groups: groups)
    }
}

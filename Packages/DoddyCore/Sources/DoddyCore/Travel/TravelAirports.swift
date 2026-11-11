import Foundation

// The airports Poles fly from and to most, with their country and time zone, so that a booking that says
// only "(BRS)" can be planned: check-in opens in Bristol's local time, and the UK's entry rules apply.
// An airport missing here gives no country and no time zone; the trip then says "check with the airline"
// and "check the entry rules for this country" instead of guessing (DOD-02).
// Countries are ISO 3166-1 alpha-2; zones are IANA identifiers. Hand-written 11 Nov 2026.

public struct TravelAirport: Equatable, Sendable {
    public let code: String
    public let country: String
    public let zone: String
    public var timeZone: TimeZone? { TimeZone(identifier: zone) }
}

public enum TravelAirports {
    private static let rows: [(String, [String])] = [
        ("PL|Europe/Warsaw", ["GDN", "WAW", "WMI", "KRK", "KTW", "WRO", "POZ", "BZG", "LCJ", "RZE", "SZZ", "LUZ", "SZY", "RDO", "IEG"]),
        ("GB|Europe/London", ["STN", "LTN", "LGW", "LHR", "SEN", "BRS", "NCL", "MAN", "EDI", "GLA", "PIK", "BHX", "LPL", "EMA", "LBA", "BFS", "ABZ", "DSA", "BOH", "EXT", "CWL"]),
        ("IE|Europe/Dublin", ["DUB", "ORK", "SNN", "NOC", "KIR"]),
        ("ES|Europe/Madrid", ["BCN", "MAD", "AGP", "ALC", "PMI", "VLC", "SVQ", "IBZ", "GRO", "REU", "MAH", "BIO", "SDR", "SCQ", "VGO", "ZAZ"]),
        ("ES|Atlantic/Canary", ["TFS", "TFN", "LPA", "ACE", "FUE"]),
        ("PT|Europe/Lisbon", ["LIS", "OPO", "FAO"]),
        ("PT|Atlantic/Madeira", ["FNC"]),
        ("PT|Atlantic/Azores", ["PDL"]),
        ("IT|Europe/Rome", ["FCO", "CIA", "BGY", "MXP", "LIN", "NAP", "BLQ", "PSA", "FLR", "CTA", "PMO", "BRI", "BDS", "VCE", "TSF", "CAG", "TRN", "OLB", "AHO", "TPS", "SUF", "VRN", "TRS", "PSR", "GOA"]),
        ("FR|Europe/Paris", ["NCE", "CDG", "ORY", "BVA", "MRS", "LYS", "BOD", "TLS", "NTE", "BES", "CCF", "PUF", "LIG", "BIQ", "MPL", "SXB", "EGC"]),
        ("GR|Europe/Athens", ["ATH", "RHO", "HER", "CHQ", "CFU", "KGS", "ZTH", "SKG", "JTR", "JMK", "EFL", "PVK", "KVA", "JSI", "AOK"]),
        ("CY|Asia/Nicosia", ["LCA", "PFO"]),
        ("MT|Europe/Malta", ["MLA"]),
        ("HR|Europe/Zagreb", ["SPU", "DBV", "ZAG", "ZAD", "PUY", "RJK", "OSI"]),
        ("DE|Europe/Berlin", ["BER", "FRA", "HHN", "MUC", "DUS", "HAM", "CGN", "DTM", "NRN", "STR", "LEJ", "HAJ", "NUE", "FMM", "BRE"]),
        ("NL|Europe/Amsterdam", ["AMS", "EIN", "RTM", "MST", "GRQ"]),
        ("BE|Europe/Brussels", ["BRU", "CRL"]),
        ("LU|Europe/Luxembourg", ["LUX"]),
        ("AT|Europe/Vienna", ["VIE", "SZG", "INN", "GRZ", "LNZ"]),
        ("CH|Europe/Zurich", ["ZRH", "GVA"]),
        ("CZ|Europe/Prague", ["PRG", "BRQ", "OSR"]),
        ("SK|Europe/Bratislava", ["BTS", "KSC"]),
        ("HU|Europe/Budapest", ["BUD", "DEB"]),
        ("SI|Europe/Ljubljana", ["LJU"]),
        ("DK|Europe/Copenhagen", ["CPH", "BLL", "AAL", "AAR"]),
        ("SE|Europe/Stockholm", ["ARN", "NYO", "GOT", "MMX", "VST"]),
        ("NO|Europe/Oslo", ["OSL", "TRF", "RYG", "BGO", "SVG", "TRD", "HAU", "AES", "KRS", "TOS"]),
        ("FI|Europe/Helsinki", ["HEL", "RVN", "TMP", "TKU"]),
        ("IS|Atlantic/Reykjavik", ["KEF"]),
        ("EE|Europe/Tallinn", ["TLL"]),
        ("LV|Europe/Riga", ["RIX"]),
        ("LT|Europe/Vilnius", ["VNO", "KUN", "PLQ"]),
        ("RO|Europe/Bucharest", ["OTP", "CLJ", "TSR", "IAS"]),
        ("BG|Europe/Sofia", ["SOF", "BOJ", "VAR", "PDV"]),
        ("TR|Europe/Istanbul", ["IST", "SAW", "AYT", "DLM", "BJV", "ADB", "ESB", "GZP"]),
        ("EG|Africa/Cairo", ["HRG", "SSH", "RMF", "CAI"]),
        ("TN|Africa/Tunis", ["NBE", "DJE", "MIR", "TUN"]),
        ("MA|Africa/Casablanca", ["RAK", "AGA", "FEZ", "CMN", "TNG"]),
        ("AL|Europe/Tirane", ["TIA"]),
        ("ME|Europe/Podgorica", ["TGD", "TIV"]),
        ("MK|Europe/Skopje", ["SKP", "OHD"]),
        ("BA|Europe/Sarajevo", ["SJJ", "TZL"]),
        ("RS|Europe/Belgrade", ["BEG", "INI"]),
        ("GE|Asia/Tbilisi", ["TBS", "KUT", "BUS"]),
        ("AM|Asia/Yerevan", ["EVN"]),
        ("JO|Asia/Amman", ["AMM", "AQJ"]),
        ("IL|Asia/Jerusalem", ["TLV"]),
        ("AE|Asia/Dubai", ["DXB", "DWC", "AUH", "SHJ", "RKT"]),
        ("UA|Europe/Kyiv", ["KBP", "LWO"]),
    ]

    private static let table: [String: TravelAirport] = {
        var out: [String: TravelAirport] = [:]
        for (key, codes) in rows {
            let parts = key.split(separator: "|").map(String.init)
            for code in codes where out[code] == nil {
                out[code] = TravelAirport(code: code, country: parts[0], zone: parts[1])
            }
        }
        return out
    }()

    public static func airport(_ code: String?) -> TravelAirport? {
        guard let code else { return nil }
        return table[code.uppercased()]
    }

    public static var all: [TravelAirport] { Array(table.values) }
}

import Foundation

// A buyer's official name and address from Poland's public registers, by the NIP the person said
// (ADR-671; owner, 1 Nov 2026: "Connect with CEIDG for NIP etc so it takes details from register").
//
//  - The Ministry of Finance's VAT register ("biała lista", `wl-api.mf.gov.pl`): every VAT taxpayer,
//    firms and sole traders. No key; at most 100 searches a day per address (gov.pl, "Jak korzystać
//    z wykazu"). Asked from the iPhone. Answer read on 1 Nov 2026 (a real search, NIP 5260250995).
//  - CEIDG (`dane.biznes.gov.pl/api/ceidg/v3`): every sole trader, VAT-registered or not. It needs a
//    JWT that only Doddy's owner can get (biznes.gov.pl, e-service 00_9999_00), so it is asked through
//    Doddy's server, which holds the token; off until it is set. Answer shape from the official
//    integrator documentation (API v3, v1.0).
//
// The rules as code: only a NIP that passed its check digit and that the person said (or confirmed)
// is looked up; only the NIP leaves the iPhone; a register answer is about that NIP or it is ignored;
// a page that isn't the register's JSON (the register's bot check answers 200 with HTML) is
// "couldn't check", never "not found"; nothing from a register is invented or completed by guessing.
// The bank accounts on the VAT register are not read or kept.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

/// Which register the data came from.
public enum CompanyRegisterSource: String, Codable, Sendable {
    case vatRegister
    case ceidg
}

/// What a register says about one NIP. Only what an invoice needs.
public struct RegisteredCompany: Equatable, Sendable, Codable {
    public let nip: String
    public let name: String
    public let address: InvoiceAddress
    /// The address exactly as the register wrote it, when it gave one line (the VAT register).
    public let addressLine: String?
    /// "Czynny", "Zwolniony", ... (VAT register) or "AKTYWNY", "ZAWIESZONY", ... (CEIDG), as written.
    public let status: String
    public let source: CompanyRegisterSource
    public let checkedOn: CalendarDate
    /// The VAT register's id of this search: proof that and when it was checked.
    public let requestId: String?

    public init(nip: String, name: String, address: InvoiceAddress, addressLine: String?, status: String,
                source: CompanyRegisterSource, checkedOn: CalendarDate, requestId: String?) {
        self.nip = nip
        self.name = name
        self.address = address
        self.addressLine = addressLine
        self.status = status
        self.source = source
        self.checkedOn = checkedOn
        self.requestId = requestId
    }

    /// An active VAT taxpayer (VAT register) or an active business (CEIDG).
    public var isActive: Bool { status == "Czynny" || status == "AKTYWNY" }
}

public enum CompanyLookup: Equatable, Sendable {
    case found(RegisteredCompany)
    /// The register answered and has no entry for this NIP.
    case notFound
    /// The register refused the NIP as invalid.
    case invalidNip
    /// No usable answer: offline, a timeout, a limit, a bot check, a page that isn't the register's.
    /// Says nothing about the NIP.
    case couldNotCheck
    /// The register isn't switched on (CEIDG without its token on Doddy's server).
    case unavailable
}

extension CompanyLookup {
    /// The VAT register is asked first (every VAT taxpayer); CEIDG (sole traders, VAT or not) only
    /// when the register had no taxpayer or couldn't be asked.
    public var asksCeidgToo: Bool { self == .notFound || self == .couldNotCheck || self == .unavailable }

    /// One answer from the two. CEIDG's entry wins when it has one; otherwise "not found" only if the
    /// VAT register itself said so, and never "found" without an entry.
    public static func combined(vat: CompanyLookup, ceidg: CompanyLookup?) -> CompanyLookup {
        guard vat.asksCeidgToo, let ceidg else { return vat }
        if case .found = ceidg { return ceidg }
        return vat == .notFound ? .notFound : .couldNotCheck
    }
}

// MARK: The VAT register

public enum VatRegister {
    public static let host = "wl-api.mf.gov.pl"
    public static let timeout: TimeInterval = 10
    public static let maxBytes = 256 * 1024
    /// The register's own limit is 100 searches a day; Doddy keeps well under it.
    public static let lookupsPerMinute = 6

    /// `GET https://wl-api.mf.gov.pl/api/search/nip/{nip}?date=YYYY-MM-DD`.
    public static func url(for nip: Nip, on day: CalendarDate) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/search/nip/\(nip.digits)"
        components.queryItems = [URLQueryItem(name: "date", value: day.iso)]
        return components.url!
    }

    /// Reads the register's answer about `nip`.
    public static func read(_ data: Data, statusCode: Int, nip: Nip, on day: CalendarDate) -> CompanyLookup {
        guard data.count <= maxBytes, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .couldNotCheck
        }
        if statusCode == 400, let code = object["code"] as? String, code == "WL-113" || code == "WL-114" || code == "WL-115" {
            return .invalidNip
        }
        guard statusCode == 200, let result = object["result"] as? [String: Any] else { return .couldNotCheck }
        let requestId = result["requestId"] as? String
        guard let subject = result["subject"] as? [String: Any] else {
            // `subject` null: the register has no taxpayer with this NIP.
            return result.keys.contains("subject") ? .notFound : .couldNotCheck
        }
        guard (subject["nip"] as? String) == nip.digits,
              let name = (subject["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let status = subject["statusVat"] as? String else { return .couldNotCheck }
        // A firm's seat ("residenceAddress") or a person's place of business ("workingAddress").
        let line = [subject["workingAddress"], subject["residenceAddress"]].compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        guard let line, let address = AddressLine.parse(line) else { return .couldNotCheck }
        return .found(RegisteredCompany(nip: nip.digits, name: name, address: address, addressLine: line, status: status,
                                        source: .vatRegister, checkedOn: day, requestId: requestId))
    }
}

// MARK: CEIDG, through Doddy's server

public enum CeidgRegister {
    /// The server's answer to `GET /v1/registry/ceidg?nip=`: CEIDG's own entry, passed on as it came
    /// (`{"firma":[...]}` from `dane.biznes.gov.pl/api/ceidg/v3/firma?nip=`), or 404 when CEIDG has none.
    public static func read(_ data: Data, statusCode: Int, nip: Nip, on day: CalendarDate) -> CompanyLookup {
        switch statusCode {
        case 404: return .notFound
        case 503: return .unavailable
        case 400: return .invalidNip
        case 200: break
        default: return .couldNotCheck
        }
        guard data.count <= VatRegister.maxBytes,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let firms = object["firma"] as? [[String: Any]] else { return .couldNotCheck }
        // The entry whose owner has this NIP, preferring an active one: a person may have older,
        // removed entries too.
        let matching = firms.filter { ($0["wlasciciel"] as? [String: Any])?["nip"] as? String == nip.digits }
        guard let firm = matching.first(where: { $0["status"] as? String == "AKTYWNY" }) ?? matching.first else {
            return firms.isEmpty ? .notFound : .couldNotCheck
        }
        guard let name = (firm["nazwa"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let place = firm["adresDzialalnosci"] as? [String: Any] else { return .couldNotCheck }
        func text(_ key: String) -> String? {
            let value = (place[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        guard let city = text("miasto"), let postCode = text("kod") else { return .couldNotCheck }
        // A village without streets has no "ulica": the place's name stands in for it, as on letters.
        let address = InvoiceAddress(street: text("ulica") ?? city, buildingNumber: text("budynek"), flatNumber: text("lokal"),
                                     city: city, postCode: postCode, countryCode: text("kraj") ?? "PL")
        return .found(RegisteredCompany(nip: nip.digits, name: name, address: address, addressLine: nil,
                                        status: firm["status"] as? String ?? "", source: .ceidg, checkedOn: day, requestId: nil))
    }
}

extension DoddyServerClient {
    /// A sole trader's entry in CEIDG, through Doddy's server, which holds CEIDG's token. Only the NIP
    /// is sent. Never throws: no answer is `.couldNotCheck`.
    public func lookupCeidg(_ nip: Nip, on day: CalendarDate) async -> CompanyLookup {
        guard let response = try? await authorized(.get, "/v1/registry/ceidg?nip=\(nip.digits)", body: nil, timeout: VatRegister.timeout) else {
            return .couldNotCheck
        }
        return CeidgRegister.read(response.body, statusCode: response.status, nip: nip, on: day)
    }
}

// MARK: One-line addresses

/// "ALEJE JEROZOLIMSKIE 160, 02-326 WARSZAWA" into street, building, flat, postcode and city. Nil
/// when the line doesn't end in a Polish postcode and a place: then the register's answer isn't used.
public enum AddressLine {
    public static func parse(_ line: String) -> InvoiceAddress? {
        let text = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard let comma = text.range(of: ", ", options: .backwards) else { return nil }
        let place = text[comma.upperBound...].split(separator: " ", maxSplits: 1).map(String.init)
        guard place.count == 2, InvoiceAddress.isPostCode(place[0]), !place[1].isEmpty else { return nil }
        var words = text[..<comma.lowerBound].split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        // "12A LOK. 5", "12A/5", "12A M. 5" or "12A".
        var flat: String?
        if words.count >= 3, ["LOK.", "LOK", "M.", "M", "LOKAL"].contains(words[words.count - 2].uppercased()) {
            flat = words.removeLast()
            words.removeLast()
        }
        var building: String?
        if words.count >= 2, let last = words.last, last.first?.isNumber == true {
            words.removeLast()
            let parts = last.split(separator: "/", maxSplits: 1).map(String.init)
            building = parts[0]
            if parts.count == 2, flat == nil { flat = parts[1] }
        }
        let street = words.joined(separator: " ")
        guard !street.isEmpty else { return nil }
        return InvoiceAddress(street: street, buildingNumber: building, flatNumber: flat, city: place[1], postCode: place[0])
    }
}

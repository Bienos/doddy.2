import Foundation

// "I lost my wallet" by voice (ADR-686; owner, 2 Nov 2026: "Continue", to "Shall I start on the
// lost-wallet flow?", after the mObywatel review of 1 Nov). Doddy can't cancel an ID card, reserve a
// PESEL number or block a bank card: no state or bank service lets an app do that for a person. So it
// shows the steps in the order that limits the damage most, each with the one official page or
// number for it, and opens that page or dials that number only when the person taps.
//
// The rules as code:
//  - the steps and their links come from this file's fixed table, checked against the official pages
//    (docs/research/2026-11-02/lost_wallet_pl.md); the model only says what was lost, whether it was
//    stolen and whether the person is abroad, and never supplies a link or a number;
//  - a link opens only an https page on an allowed government host, and a call only a number listed here;
//  - nothing is ever marked done by Doddy or the model: a step is ticked only by the person's own tap,
//    and the tick says only that they said they did it;
//  - no card number, PESEL, ID number or account detail is asked for, kept or sent anywhere.
//
// Platforms: iPhone and iPad. Pure logic; tested on Linux.

extension VoiceToolName {
    public static let lostWallet = "lost_wallet"
}

/// What the person says is gone.
public enum LostItem: String, CaseIterable, Codable, Sendable {
    case idCard = "id_card"
    case bankCards = "bank_cards"
    case drivingLicence = "driving_licence"
    case passport
}

/// What happened, as the person said it. Only these three facts reach the app.
public struct LostWalletSituation: Equatable, Sendable, Codable {
    /// Each item once, in `LostItem.allCases` order.
    public let lost: [LostItem]
    public let stolen: Bool
    public let abroad: Bool

    public init(lost: [LostItem], stolen: Bool, abroad: Bool) {
        self.lost = LostItem.allCases.filter(lost.contains)
        self.stolen = stolen
        self.abroad = abroad
    }

    public func has(_ item: LostItem) -> Bool { lost.contains(item) }
}

/// What a step's button does, on the person's tap.
public enum LostWalletAction: Equatable, Sendable {
    /// An official page. Always https on `LostWalletPlan.allowedHosts`.
    case open(URL)
    /// A phone number from `LostWalletPlan.allowedNumbers`, as dialled.
    case call(String)

    /// The URL the app hands to iOS: the page, or `tel:` with the number.
    public var url: URL? {
        switch self {
        case .open(let url): url
        case .call(let number): URL(string: "tel:" + number)
        }
    }
}

public enum LostWalletStepID: String, CaseIterable, Codable, Sendable {
    case blockCards
    case cancelIdCard
    case reservePesel
    case reportTheft
    case reportDrivingLicence
    case reportPassport
    case consulAbroad
    case newIdCard
}

/// One step on the card, in the language the card is shown in.
public struct LostWalletStep: Equatable, Sendable, Identifiable {
    public let id: LostWalletStepID
    public let title: String
    public let detail: String
    public let action: LostWalletAction?
    public let actionLabel: String?

    init(_ id: LostWalletStepID, title: String, detail: String, action: LostWalletAction? = nil, actionLabel: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.actionLabel = actionLabel
    }
}

public enum LostWalletPlan {
    /// The only hosts a step may open.
    public static let allowedHosts: Set<String> = ["www.gov.pl"]
    /// The only numbers a step may dial: the shared card-blocking line (+48 828 828 828).
    public static let allowedNumbers: Set<String> = ["+48828828828"]

    /// True when the action may run: https on an allowed host, or an allowed number.
    public static func isAllowed(_ action: LostWalletAction) -> Bool {
        switch action {
        case .open(let url):
            guard url.scheme == "https", let host = url.host, allowedHosts.contains(host),
                  url.user == nil, url.password == nil, url.port == nil else { return false }
            return true
        case .call(let number):
            return allowedNumbers.contains(number)
        }
    }

    /// The steps for what happened, most urgent first. Empty when nothing on the list was lost.
    public static func steps(for situation: LostWalletSituation, polish: Bool) -> [LostWalletStep] {
        let text = polish ? LostWalletText.polish : LostWalletText.english
        var steps: [LostWalletStep] = []
        if situation.has(.bankCards) {
            steps.append(LostWalletStep(.blockCards, title: text.blockCardsTitle,
                                        detail: situation.abroad ? text.blockCardsDetailAbroad : text.blockCardsDetail,
                                        action: .call("+48828828828"), actionLabel: text.callCardLine))
        }
        if situation.has(.idCard) {
            steps.append(LostWalletStep(.cancelIdCard, title: text.cancelIdTitle,
                                        detail: situation.abroad ? text.cancelIdDetailAbroad : text.cancelIdDetail,
                                        action: .open(Links.reportIdCard), actionLabel: text.openGovPl))
        }
        if situation.has(.idCard) || situation.has(.passport) || situation.has(.drivingLicence) {
            steps.append(LostWalletStep(.reservePesel, title: text.reservePeselTitle, detail: text.reservePeselDetail,
                                        action: .open(Links.reservePesel), actionLabel: text.openGovPl))
        }
        if situation.stolen {
            steps.append(LostWalletStep(.reportTheft, title: text.reportTheftTitle,
                                        detail: situation.abroad ? text.reportTheftDetailAbroad : text.reportTheftDetail))
        }
        if situation.has(.passport) {
            steps.append(LostWalletStep(.reportPassport, title: text.reportPassportTitle,
                                        detail: situation.abroad ? text.reportPassportDetailAbroad : text.reportPassportDetail,
                                        action: .open(Links.reportPassport), actionLabel: text.openGovPl))
        }
        if situation.abroad && (situation.has(.idCard) || situation.has(.passport)) {
            steps.append(LostWalletStep(.consulAbroad, title: text.consulTitle, detail: text.consulDetail,
                                        action: .open(Links.consulates), actionLabel: text.openGovPl))
        }
        if situation.has(.drivingLicence) {
            steps.append(LostWalletStep(.reportDrivingLicence, title: text.drivingLicenceTitle, detail: text.drivingLicenceDetail,
                                        action: .open(Links.reportDrivingLicence), actionLabel: text.openGovPl))
        }
        if situation.has(.idCard) {
            steps.append(LostWalletStep(.newIdCard, title: text.newIdTitle, detail: text.newIdDetail,
                                        action: .open(Links.newIdCard), actionLabel: text.openGovPl))
        }
        return steps
    }

    /// The official pages, checked on 2 Nov 2026 (docs/research/2026-11-02/lost_wallet_pl.md).
    enum Links {
        static let reportIdCard = URL(string: "https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-dowodu-osobistego")!
        static let reservePesel = URL(string: "https://www.gov.pl/web/gov/zastrzez-swoj-numer-pesel")!
        static let reportPassport = URL(string: "https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-paszportu")!
        static let consulates = URL(string: "https://www.gov.pl/web/dyplomacja/polskie-przedstawicielstwa-na-swiecie")!
        static let reportDrivingLicence = URL(string: "https://www.gov.pl/web/gov/zglos-utrate-prawa-jazdy")!
        static let newIdCard = URL(string: "https://www.gov.pl/web/gov/uzyskaj-dowod-osobisty")!

        static let all: [URL] = [reportIdCard, reservePesel, reportPassport, consulates, reportDrivingLicence, newIdCard]
    }
}

/// The card's words. Fixed here, so the model never writes a step, a link or a number.
struct LostWalletText {
    let blockCardsTitle, blockCardsDetail, blockCardsDetailAbroad, callCardLine: String
    let cancelIdTitle, cancelIdDetail, cancelIdDetailAbroad: String
    let reservePeselTitle, reservePeselDetail: String
    let reportTheftTitle, reportTheftDetail, reportTheftDetailAbroad: String
    let reportPassportTitle, reportPassportDetail, reportPassportDetailAbroad: String
    let consulTitle, consulDetail: String
    let drivingLicenceTitle, drivingLicenceDetail: String
    let newIdTitle, newIdDetail: String
    let openGovPl: String

    static let english = LostWalletText(
        blockCardsTitle: "Block your bank cards",
        blockCardsDetail: "First in your bank's app, or on your bank's helpline. The shared card-blocking line +48 828 828 828 works for many Polish banks, day and night.",
        blockCardsDetailAbroad: "First in your bank's app, or on your bank's helpline. The shared card-blocking line +48 828 828 828 works for many Polish banks, from abroad too.",
        callCardLine: "Call 828 828 828",
        cancelIdTitle: "Report your ID card lost",
        cancelIdDetail: "In the mObywatel app, on gov.pl, or at any town or municipal office. Once reported, the ID card is cancelled for good, even if you find it.",
        cancelIdDetailAbroad: "In the mObywatel app, on gov.pl, or at a Polish consulate. Once reported, the ID card is cancelled for good, even if you find it.",
        reservePeselTitle: "Reserve your PESEL number",
        reservePeselDetail: "In the mObywatel app or on gov.pl. It's free, and banks and lenders must check it, so nobody can take a loan in your name. You can lift it at any time.",
        reportTheftTitle: "Report the theft to the police",
        reportTheftDetail: "At any police station. Call 112 only if you are in danger now.",
        reportTheftDetailAbroad: "To the local police, and keep the report for your bank and the consulate. Call 112 if you are in danger now.",
        reportPassportTitle: "Report your passport lost",
        reportPassportDetail: "On gov.pl or at a passport office. Once reported, it is cancelled for good.",
        reportPassportDetailAbroad: "At a Polish consulate, or on gov.pl. Once reported, it is cancelled for good.",
        consulTitle: "Contact a Polish consulate",
        consulDetail: "If you need a document to travel home, the consulate can issue a temporary passport.",
        drivingLicenceTitle: "Report your driving licence lost",
        drivingLicenceDetail: "On gov.pl or at the driving-licence office of your town or district. In Poland you don't need to carry it while driving.",
        newIdTitle: "Apply for a new ID card",
        newIdDetail: "Online on gov.pl or at any town or municipal office. It's free; you collect it in person.",
        openGovPl: "Open gov.pl")

    static let polish = LostWalletText(
        blockCardsTitle: "Zastrzeż karty płatnicze",
        blockCardsDetail: "Najpierw w aplikacji banku albo na infolinii banku. Wspólny numer do zastrzegania kart +48 828 828 828 działa dla wielu polskich banków, przez całą dobę.",
        blockCardsDetailAbroad: "Najpierw w aplikacji banku albo na infolinii banku. Wspólny numer do zastrzegania kart +48 828 828 828 działa dla wielu polskich banków, także z zagranicy.",
        callCardLine: "Zadzwoń: 828 828 828",
        cancelIdTitle: "Zgłoś utratę dowodu osobistego",
        cancelIdDetail: "W aplikacji mObywatel, na gov.pl albo w dowolnym urzędzie gminy. Zgłoszony dowód jest od razu unieważniony, nawet jeśli się znajdzie.",
        cancelIdDetailAbroad: "W aplikacji mObywatel, na gov.pl albo w polskim konsulacie. Zgłoszony dowód jest od razu unieważniony, nawet jeśli się znajdzie.",
        reservePeselTitle: "Zastrzeż numer PESEL",
        reservePeselDetail: "W aplikacji mObywatel albo na gov.pl. To nic nie kosztuje, a banki i pożyczkodawcy muszą to sprawdzać, więc nikt nie weźmie kredytu na ciebie. Możesz cofnąć zastrzeżenie w każdej chwili.",
        reportTheftTitle: "Zgłoś kradzież na policji",
        reportTheftDetail: "Na dowolnym komisariacie. Na 112 dzwoń tylko, jeśli coś ci teraz grozi.",
        reportTheftDetailAbroad: "Na miejscowej policji. Zachowaj zgłoszenie dla banku i konsulatu. Na 112 dzwoń, jeśli coś ci teraz grozi.",
        reportPassportTitle: "Zgłoś utratę paszportu",
        reportPassportDetail: "Na gov.pl albo w punkcie paszportowym. Zgłoszony paszport jest unieważniony na stałe.",
        reportPassportDetailAbroad: "W polskim konsulacie albo na gov.pl. Zgłoszony paszport jest unieważniony na stałe.",
        consulTitle: "Skontaktuj się z polskim konsulatem",
        consulDetail: "Jeśli potrzebujesz dokumentu, żeby wrócić do kraju, konsul może wydać paszport tymczasowy.",
        drivingLicenceTitle: "Zgłoś utratę prawa jazdy",
        drivingLicenceDetail: "Na gov.pl albo w wydziale komunikacji starostwa lub urzędu miasta. W Polsce nie musisz mieć go przy sobie, gdy prowadzisz.",
        newIdTitle: "Złóż wniosek o nowy dowód",
        newIdDetail: "Przez internet na gov.pl albo w dowolnym urzędzie gminy. To nic nie kosztuje; odbierasz go osobiście.",
        openGovPl: "Otwórz gov.pl")
}

extension VoiceToolRequest {
    static func parseLostWallet(_ args: Arguments, name: String) -> VoiceToolRequest {
        let choices = LostItem.allCases.map(\.rawValue).joined(separator: ", ")
        let raw: [String]
        switch args.stringList("lost") {
        case .absent: return .invalid(name: name, reason: "missing lost: one or more of \(choices)")
        case .notStrings: return .invalid(name: name, reason: "lost must be a list of strings: \(choices)")
        case .list(let list): raw = list
        }
        var items: [LostItem] = []
        for text in raw {
            guard let item = LostItem(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased()) else {
                return .invalid(name: name, reason: "lost has \"\(text)\"; each must be one of \(choices)")
            }
            items.append(item)
        }
        guard !items.isEmpty else { return .invalid(name: name, reason: "lost is empty: one or more of \(choices)") }
        return .lostWallet(LostWalletSituation(lost: items, stolen: args.flag("stolen"), abroad: args.flag("abroad")))
    }
}

extension VoiceToolReply {
    /// The checklist is on the person's screen. The agent hears the steps in English, in order, and
    /// what it must never do.
    public static func lostWalletShown(_ situation: LostWalletSituation) -> String {
        let steps = LostWalletPlan.steps(for: situation, polish: false)
        let numbered: [String] = steps.enumerated().map { "\($0.offset + 1). \($0.element.title): \($0.element.detail)" }
        let parts: [String] = [
            "shown: a checklist with \(steps.count) steps is on the user's screen, most urgent first.",
            numbered.joined(separator: " "),
            "Doddy can't do any of these steps itself: each button only opens the official page or dials the number when the user taps it, and the user does the step there.",
            "Go through them one at a time, starting with the first, in a calm, plain voice; no jokes.",
            "Never say a card is blocked, a document cancelled or a PESEL reserved: only the user can see that, in their bank or in mObywatel.",
            "Never ask for or repeat a card number, PESEL, ID number, PIN or password.",
            "If the user is in danger now, tell them to call 112.",
        ]
        return parts.joined(separator: " ")
    }
}

import Foundation

// "I lost my wallet" by voice (ADR-686; owner, 2 Nov 2026: "Continue", to "Shall I start on the
// lost-wallet flow?", after the mObywatel review of 1 Nov). Doddy can't cancel an ID card, reserve a
// PESEL number or block a bank card: no state or bank service lets an app do that for a person. So it
// shows the steps in the order that limits the damage most, each with the one official page or
// number for it, and opens that page or dials that number only when the person taps.
//
// The rules as code:
//  - the steps and their links come from this file's fixed table, written from the official pages
//    read on 2 Nov 2026 (docs/research/2026-11-02/lost_wallet_pl.md); the model only says what was
//    lost, whether it was stolen and whether the person is abroad, and never supplies a link or a number;
//  - a link opens only an https page on an allowed host, and a call only a number listed here;
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
    case checkPesel
    case blockDocuments
    case reportTheft
    case reportPassport
    case consulAbroad
    case reportDrivingLicence
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
    /// The only hosts a step may open: the government portal and the banks' own database of blocked
    /// documents (Związek Banków Polskich).
    public static let allowedHosts: Set<String> = ["www.gov.pl", "dokumentyzastrzezone.pl"]
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
            steps.append(LostWalletStep(.checkPesel, title: text.checkPeselTitle, detail: text.checkPeselDetail,
                                        action: .open(Links.reservePesel), actionLabel: text.openGovPl))
        }
        if situation.has(.idCard) || situation.has(.passport) {
            steps.append(LostWalletStep(.blockDocuments, title: text.blockDocumentsTitle, detail: text.blockDocumentsDetail,
                                        action: .open(Links.blockDocuments), actionLabel: text.openDokumentyZastrzezone))
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

    /// The official pages, each opened and read on 2 Nov 2026 (docs/research/2026-11-02/lost_wallet_pl.md).
    /// `LostWalletTests.testLinksAreTheOnesReadOnTheOfficialPages` pins them.
    enum Links {
        static let reportIdCard = URL(string: "https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-swojego-dowodu-osobistego-uniewaznij-dowod")!
        static let reservePesel = URL(string: "https://www.gov.pl/web/gov/zastrzez-swoj-numer-pesel-lub-cofnij-zastrzezenie")!
        static let blockDocuments = URL(string: "https://dokumentyzastrzezone.pl/zastrzeganie-dokumentow/")!
        static let reportPassport = URL(string: "https://www.gov.pl/web/gov/zglos-utrate-lub-zniszczenie-paszportu")!
        static let consulates = URL(string: "https://www.gov.pl/web/dyplomacja/polskie-przedstawicielstwa-na-swiecie")!
        static let reportDrivingLicence = URL(string: "https://www.gov.pl/web/gov/zglos-utrate-lub-uszkodzenie-prawa-jazdy")!
        static let newIdCard = URL(string: "https://www.gov.pl/web/gov/uzyskaj-dowod-osobisty")!

        static let all: [URL] = [reportIdCard, reservePesel, blockDocuments, reportPassport, consulates, reportDrivingLicence, newIdCard]
    }
}

/// The card's words. Fixed here, so the model never writes a step, a link or a number. What each
/// sentence says is in the official pages (docs/research/2026-11-02/lost_wallet_pl.md); what those
/// pages don't say plainly is left out (whether mDowód stays valid after the ID card is cancelled,
/// whether a police report alone reserves the PESEL, the exact button names in the app).
struct LostWalletText {
    let blockCardsTitle: String
    let blockCardsDetail: String
    let blockCardsDetailAbroad: String
    let callCardLine: String
    let cancelIdTitle: String
    let cancelIdDetail: String
    let cancelIdDetailAbroad: String
    let checkPeselTitle: String
    let checkPeselDetail: String
    let blockDocumentsTitle: String
    let blockDocumentsDetail: String
    let reportTheftTitle: String
    let reportTheftDetail: String
    let reportTheftDetailAbroad: String
    let reportPassportTitle: String
    let reportPassportDetail: String
    let reportPassportDetailAbroad: String
    let consulTitle: String
    let consulDetail: String
    let drivingLicenceTitle: String
    let drivingLicenceDetail: String
    let newIdTitle: String
    let newIdDetail: String
    let openGovPl: String
    let openDokumentyZastrzezone: String

    static let english = LostWalletText(
        blockCardsTitle: "Block your bank cards",
        blockCardsDetail: "In your bank's app or on its helpline, choose a permanent block (zastrzeżenie), which can't be undone; a temporary lock is only for a card you may just have mislaid. Or call the shared line +48 828 828 828, day and night: say your bank's name and it puts you through. One call covers one bank. If your bank isn't recognised, use its app or the number on its website.",
        blockCardsDetailAbroad: "In your bank's app or on its helpline, choose a permanent block (zastrzeżenie), which can't be undone; a temporary lock is only for a card you may just have mislaid. The shared line +48 828 828 828 works from abroad too: say your bank's name and it puts you through. One call covers one bank. If your bank isn't recognised, use its app or the international number on its website.",
        callCardLine: "Call 828 828 828",
        cancelIdTitle: "Report your ID card lost",
        cancelIdDetail: "In the mObywatel app (look for “Unieważnij swój dowód”), on gov.pl, or at any gmina office. It takes effect at once and can't be undone, even if you find the card. If it was stolen, a police report alone cancels it. Online you need Profil Zaufany and an e-Doręczenia address; at a gmina office you need no account. An e-dowód you may still find can be suspended for up to 14 days instead.",
        cancelIdDetailAbroad: "In the mObywatel app or on gov.pl, which cancel it at once, or at a Polish consulate (in person, by post or by fax), which passes it to your gmina. Cancelling can't be undone, even if you find the card.",
        checkPeselTitle: "Check that your PESEL is reserved",
        checkPeselDetail: "Reporting a lost ID card reserves your PESEL automatically if you're an adult, but check it: in the mObywatel app open Usługi, then Zastrzeż PESEL, or use gov.pl. If it isn't reserved, reserve it. It's free, and banks and lenders must check it before lending in your name. You can lift it at any time.",
        blockDocumentsTitle: "Report the documents to Dokumenty Zastrzeżone",
        blockDocumentsDetail: "The banks' shared database of blocked documents: a report reaches banks, phone operators and thousands of firms, separately from the state register. gov.pl still recommends it. Report in the mObywatel app (Usługi › Ochrona danych › Zastrzeż dokument) or at a bank branch; with no account, use a bank from the list on the page. For an ID card or passport.",
        reportTheftTitle: "Report the theft to the police",
        reportTheftDetail: "At any police station; bring a photo ID if you have one (a passport, a driving licence or your mDowód). Call 112 only if there is danger or a thief nearby right now. A police report also cancels a stolen ID card or passport.",
        reportTheftDetailAbroad: "Tell the local police and keep a copy of the report for your bank and the consulate. If you're in danger now, call the local emergency number (112 in the EU).",
        reportPassportTitle: "Report your passport lost",
        reportPassportDetail: "On gov.pl, in the mObywatel app, or at any passport office. It's cancelled at once and can't be undone. If it was stolen and already reported to the Polish police, you don't need to report it again.",
        reportPassportDetailAbroad: "At a Polish consulate (no appointment needed to report), in the mObywatel app, or on gov.pl. It's cancelled at once and can't be undone.",
        consulTitle: "Contact a Polish consulate",
        consulDetail: "To get home, the consul can issue a temporary passport after checking your identity and citizenship. An honorary consul can't take the report. Find your nearest consulate on gov.pl.",
        drivingLicenceTitle: "Report your driving licence lost",
        drivingLicenceDetail: "Within 30 days, at the district office (starostwo) or city office where you live, or online. A duplicate costs 100 zł.",
        newIdTitle: "Apply for a new ID card",
        newIdDetail: "Only after the old one is cancelled. Apply at any gmina office, or online (you then visit an office within 30 days for fingerprints). It's free and takes up to 30 days. You collect it in person; bring a passport or other photo ID.",
        openGovPl: "Open gov.pl",
        openDokumentyZastrzezone: "Open Dokumenty Zastrzeżone")

    static let polish = LostWalletText(
        blockCardsTitle: "Zastrzeż karty płatnicze",
        blockCardsDetail: "W aplikacji banku albo na jego infolinii wybierz zastrzeżenie karty, którego nie da się cofnąć; blokada tymczasowa jest tylko na wypadek, gdy karta mogła się po prostu zawieruszyć. Możesz też zadzwonić na wspólny numer +48 828 828 828, całą dobę: powiedz nazwę banku, a numer połączy cię z bankiem. Jedno połączenie obejmuje jeden bank. Jeśli twój bank nie zostanie rozpoznany, użyj aplikacji banku albo numeru ze strony banku.",
        blockCardsDetailAbroad: "W aplikacji banku albo na jego infolinii wybierz zastrzeżenie karty, którego nie da się cofnąć; blokada tymczasowa jest tylko na wypadek, gdy karta mogła się po prostu zawieruszyć. Wspólny numer +48 828 828 828 działa też z zagranicy: powiedz nazwę banku, a numer połączy cię z bankiem. Jedno połączenie obejmuje jeden bank. Jeśli twój bank nie zostanie rozpoznany, użyj aplikacji banku albo numeru międzynarodowego ze strony banku.",
        callCardLine: "Zadzwoń: 828 828 828",
        cancelIdTitle: "Zgłoś utratę dowodu osobistego",
        cancelIdDetail: "W aplikacji mObywatel (szukaj „Unieważnij swój dowód”), na gov.pl albo w dowolnym urzędzie gminy. Unieważnienie działa od razu i nie da się go cofnąć, nawet jeśli dowód się znajdzie. Jeśli dowód ukradziono, wystarczy zgłoszenie na policji. Przez internet potrzebujesz profilu zaufanego i adresu do e-Doręczeń; w urzędzie gminy nie potrzebujesz żadnego konta. E-dowód, który może się jeszcze znaleźć, możesz zamiast tego zawiesić na maksymalnie 14 dni.",
        cancelIdDetailAbroad: "W aplikacji mObywatel albo na gov.pl (unieważnienie następuje od razu), albo w polskim konsulacie, osobiście, pocztą lub faksem; konsul przekaże zgłoszenie twojej gminie. Unieważnienia nie da się cofnąć, nawet jeśli dowód się znajdzie.",
        checkPeselTitle: "Sprawdź, czy twój PESEL jest zastrzeżony",
        checkPeselDetail: "Zgłoszenie utraty dowodu zastrzega PESEL automatycznie, jeśli masz skończone 18 lat, ale sprawdź to: w aplikacji mObywatel wejdź w Usługi, potem Zastrzeż PESEL, albo skorzystaj z gov.pl. Jeśli nie jest zastrzeżony, zastrzeż go. To nic nie kosztuje, a banki i pożyczkodawcy muszą to sprawdzać, zanim udzielą pożyczki na twoje dane. Możesz cofnąć zastrzeżenie w każdej chwili.",
        blockDocumentsTitle: "Zgłoś dokumenty do Dokumentów Zastrzeżonych",
        blockDocumentsDetail: "Wspólna baza banków z zastrzeżonymi dokumentami: zgłoszenie dociera do banków, operatorów telefonii i tysięcy firm, niezależnie od rejestru państwowego. Gov.pl nadal to zaleca. Zgłoś w aplikacji mObywatel (Usługi › Ochrona danych › Zastrzeż dokument) albo w oddziale banku; kto nie ma konta, może skorzystać z banku z listy na stronie. Dotyczy dowodu i paszportu.",
        reportTheftTitle: "Zgłoś kradzież na policji",
        reportTheftDetail: "Na dowolnym komisariacie; weź dokument ze zdjęciem, jeśli go masz (paszport, prawo jazdy albo mDowód). Na 112 dzwoń tylko, gdy teraz coś ci grozi albo złodziej jest w pobliżu. Zgłoszenie na policji unieważnia też skradziony dowód lub paszport.",
        reportTheftDetailAbroad: "Zgłoś na miejscowej policji i zachowaj kopię zgłoszenia dla banku i konsulatu. Gdy teraz coś ci grozi, zadzwoń pod lokalny numer alarmowy (w UE 112).",
        reportPassportTitle: "Zgłoś utratę paszportu",
        reportPassportDetail: "Na gov.pl, w aplikacji mObywatel albo w dowolnym punkcie paszportowym. Paszport jest unieważniony od razu i nie da się tego cofnąć. Jeśli go ukradziono i zgłoszono to już polskiej policji, nie trzeba zgłaszać ponownie.",
        reportPassportDetailAbroad: "W polskim konsulacie (do zgłoszenia nie trzeba się umawiać), w aplikacji mObywatel albo na gov.pl. Paszport jest unieważniony od razu i nie da się tego cofnąć.",
        consulTitle: "Skontaktuj się z polskim konsulatem",
        consulDetail: "Żeby wrócić do kraju, konsul może wydać paszport tymczasowy po sprawdzeniu tożsamości i obywatelstwa. Konsul honorowy nie przyjmuje zgłoszeń. Najbliższy konsulat znajdziesz na gov.pl.",
        drivingLicenceTitle: "Zgłoś utratę prawa jazdy",
        drivingLicenceDetail: "W ciągu 30 dni, w starostwie albo urzędzie miasta właściwym dla twojego miejsca zamieszkania, lub przez internet. Duplikat kosztuje 100 zł.",
        newIdTitle: "Złóż wniosek o nowy dowód",
        newIdDetail: "Dopiero po unieważnieniu starego. Złóż wniosek w dowolnym urzędzie gminy albo przez internet (wtedy w ciągu 30 dni odwiedzasz urząd po odciski palców). To nic nie kosztuje, a dowód jest gotowy do 30 dni. Odbierasz go osobiście; weź paszport albo inny dokument ze zdjęciem.",
        openGovPl: "Otwórz gov.pl",
        openDokumentyZastrzezone: "Otwórz Dokumenty Zastrzeżone")
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

import Foundation

// BLIK phone transfers, prepared by voice (ADR-510). BLIK has no public interface that lets an
// app send money: a phone transfer ("przelew na telefon") is made only in the user's own bank app.
// So Doddy never sends, pays or moves money. "Send Ania 50 zł for the pizza" becomes a card with
// the person, their phone number from Contacts, the amount in złoty and the title, for the user
// to check and send themselves in their bank app. The agent hears only that the details were
// shown, never that anything was sent or paid, because Doddy can't see whether it was.
//
// The amount is kept in grosze and is never rounded: a figure with more than two decimals, a
// negative one, another currency or one above Doddy's own ceiling is refused, and the agent asks
// the user again.

extension VoiceToolName {
    public static let draftBlikTransfer = "draft_blik_transfer"
}

/// An amount of Polish złoty, in grosze so that nothing is rounded. Always more than zero.
public struct BlikAmount: Equatable, Hashable, Sendable {
    public let grosze: Int

    public init?(grosze: Int) {
        guard grosze > 0 else { return nil }
        self.grosze = grosze
    }

    /// "50.00 PLN": what the agent hears and repeats.
    public var agentText: String {
        let minor = grosze % 100
        return "\(grosze / 100).\(minor < 10 ? "0" : "")\(minor) PLN"
    }

    /// For the card, formatted in the iPhone's language there ("50,00 zł" in Polish).
    public var decimal: Decimal { Decimal(grosze) / 100 }
}

public enum BlikTransferLimits {
    /// Doddy's own ceiling for one prepared transfer: 1,000 zł (the owner's choice, ADR-541; was
    /// 10,000 zł in ADR-510). Not BLIK's limit or a bank's (each bank sets its own); it stops a
    /// misheard amount from reaching the card.
    public static let maxGrosze = 100_000
}

/// What the agent asked for. Nothing here has been sent anywhere.
public struct BlikTransferDraft: Equatable, Sendable {
    /// As the user said it, for example "Ania". Looked up in Contacts when Doddy may read them.
    public let recipientName: String
    public let amount: BlikAmount
    /// The transfer title, if the user gave one ("pizza").
    public let title: String?

    public init(recipientName: String, amount: BlikAmount, title: String?) {
        self.recipientName = recipientName
        self.amount = amount
        self.title = title
    }
}

/// One of the person's numbers: as Contacts shows it, and what the Copy button copies.
public struct BlikPhoneNumber: Equatable, Hashable, Sendable {
    public let shown: String
    public let copy: String
}

public enum BlikPhone {
    /// Digits only, as bank apps' phone fields take them. A Polish number written with +48 or
    /// 0048 becomes its nine digits; another country keeps its plus sign. Nil when there are no
    /// digits at all.
    public static func forCopy(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // ASCII digits only: Character.isNumber would also keep other scripts' digits and fractions.
        let digits = String(trimmed.filter { ("0"..."9").contains($0) })
        guard !digits.isEmpty else { return nil }
        if trimmed.hasPrefix("+") {
            if digits.count == 11, digits.hasPrefix("48") { return String(digits.dropFirst(2)) }
            return "+" + digits
        }
        if digits.count == 13, digits.hasPrefix("0048") { return String(digits.dropFirst(4)) }
        return digits
    }

    /// The contact's numbers, each once (the same number written two ways counts once), in
    /// Contacts' order. Entries with no digits are left out.
    public static func numbers(_ raw: [String]) -> [BlikPhoneNumber] {
        var seen: Set<String> = []
        return raw.compactMap { shown in
            guard let copy = forCopy(shown), seen.insert(copy).inserted else { return nil }
            return BlikPhoneNumber(shown: shown.trimmingCharacters(in: .whitespacesAndNewlines), copy: copy)
        }
    }
}

/// Who the card is for, decided from the Contacts search. Several people with the same name are
/// never guessed between: showing the wrong person's number next to an amount is worse than
/// asking.
public enum BlikRecipient: Equatable, Sendable {
    /// Contacts can't be read (no iOS permission), or nobody matched: the card shows the name as
    /// said, and the user picks the person in the bank app.
    case nameOnly
    /// One contact; `numbers` may be empty when they have none.
    case contact(name: String, numbers: [BlikPhoneNumber])
    /// More than one contact matched; the agent asks which one.
    case several(names: [String])

    /// `matches` is what the Contacts search found, in its order.
    public static func resolve(_ matches: [(name: String, phoneNumbers: [String])]) -> BlikRecipient {
        switch matches.count {
        case 0: return .nameOnly
        case 1: return .contact(name: matches[0].name, numbers: BlikPhone.numbers(matches[0].phoneNumbers))
        default: return .several(names: matches.map(\.name))
        }
    }
}

extension VoiceToolRequest {
    /// to (the person's name), amount (złoty, a number), optional title and currency.
    static func parseBlikTransfer(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let recipient = args.text("to") else { return .invalid(name: name, reason: "missing to (the person's name)") }
        if let currency = args.text("currency"), CurrencyConversion.code(currency) != "PLN" {
            return .invalid(name: name, reason: "BLIK phone transfers are in złoty (PLN) only; ask the user for the amount in złoty")
        }
        let amount: Swift.Result<BlikAmount, BlikAmountProblem>
        if let number = args.number("amount") {
            amount = BlikAmountParser.parse(number)
        } else if let text = args.text("amount") {
            amount = BlikAmountParser.parse(text)
        } else {
            return .invalid(name: name, reason: "missing amount")
        }
        switch amount {
        case .success(let value):
            return .draftBlikTransfer(BlikTransferDraft(recipientName: recipient, amount: value, title: args.text("title")))
        case .failure(let problem):
            return .invalid(name: name, reason: problem.reason)
        }
    }
}

enum BlikAmountProblem: Error, Equatable {
    case notANumber, notPositive, tooManyDecimals, tooLarge

    var reason: String {
        switch self {
        case .notANumber: "amount must be a number of złoty written with a dot, e.g. 49.99"
        case .notPositive: "amount must be more than zero"
        case .tooManyDecimals: "amount has more than two decimal places; ask the user for the exact amount in złoty and grosze"
        case .tooLarge: "amount is above \(BlikTransferLimits.maxGrosze / 100) PLN, the most Doddy prepares at once; check the amount with the user"
        }
    }
}

enum BlikAmountParser {
    /// A number as the model sent it in JSON. Checked as a Double first: Int(_:) traps on a value
    /// it can't hold (review C6).
    static func parse(_ value: Double) -> Swift.Result<BlikAmount, BlikAmountProblem> {
        guard value.isFinite else { return .failure(.notANumber) }
        guard value > 0 else { return .failure(.notPositive) }
        guard value <= Double(BlikTransferLimits.maxGrosze) / 100 else { return .failure(.tooLarge) }
        let scaled = value * 100
        let grosze = scaled.rounded()
        // 12.34 is 1233.9999… as a Double; 12.345 is 1234.5 and is refused, never rounded.
        guard abs(scaled - grosze) < 0.000_001 else { return .failure(.tooManyDecimals) }
        guard let amount = BlikAmount(grosze: Int(grosze)) else { return .failure(.notPositive) }
        return .success(amount)
    }

    /// A number sent as text: "50", "49.99" or "49,99", with an optional "zł" or "PLN" after it.
    /// Read digit by digit, so nothing goes through floating point.
    static func parse(_ text: String) -> Swift.Result<BlikAmount, BlikAmountProblem> {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["pln", "zł", "zl"] where cleaned.hasSuffix(suffix) {
            cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if cleaned.hasPrefix("-") { return .failure(.notPositive) }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false).flatMap {
            $0.split(separator: ",", omittingEmptySubsequences: false)
        }
        guard (1...2).contains(parts.count), let whole = parts.first, !whole.isEmpty,
              whole.allSatisfy({ ("0"..."9").contains($0) }) else { return .failure(.notANumber) }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.allSatisfy({ ("0"..."9").contains($0) }) else { return .failure(.notANumber) }
        guard parts.count == 1 || !fraction.isEmpty else { return .failure(.notANumber) }
        guard fraction.count <= 2 else { return .failure(.tooManyDecimals) }
        // More digits than the ceiling has can't be under it (and can't overflow Int below).
        let significant = whole.drop { $0 == "0" }
        guard significant.count <= 5, let units = Int(significant.isEmpty ? "0" : String(significant)) else {
            return .failure(.tooLarge)
        }
        let grosze = units * 100 + (Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        guard grosze > 0 else { return .failure(.notPositive) }
        guard grosze <= BlikTransferLimits.maxGrosze else { return .failure(.tooLarge) }
        guard let amount = BlikAmount(grosze: grosze) else { return .failure(.notPositive) }
        return .success(amount)
    }
}

extension VoiceToolReply {
    /// The user tapped Done on the card: they have the details to send in their bank app. Nothing
    /// was sent and Doddy can't see whether they send it. Names and the title are data (ToolData).
    public static func blikShown(_ draft: BlikTransferDraft, contactName: String?) -> String {
        var lines = [quoted("To", contactName ?? draft.recipientName), "Amount: \(draft.amount.agentText)"]
        if let title = draft.title { lines.append(quoted("Title", title)) }
        return "shown: the user has the BLIK phone transfer below on their screen to send themselves in their bank app. "
            + "Nothing was sent: Doddy can't send money and can't see whether they send it. "
            + "Never say it was sent, paid or done; if they ask, say they send it in their bank app.\n"
            + ToolData.block(lines)
    }

    public static let blikDeclined = "declined: the user closed the BLIK transfer card. Nothing was sent; Doddy never sends money."

    /// More than one contact has the name the agent sent. Names are from Contacts: data.
    public static func blikSeveralContacts(_ names: [String], query: String) -> String {
        "failed: more than one contact matches the name below, so no transfer was shown. Ask the user which person they mean, then call "
            + "\(VoiceToolName.draftBlikTransfer) again with that contact's full name. Never read out a number. Nothing was sent.\n"
            + ToolData.block([quoted("Searched for", query)] + names.map { "- \(ToolData.clean($0))" })
    }
}

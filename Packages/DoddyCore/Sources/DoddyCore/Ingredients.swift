import Foundation

// Recipe to shopping list (ADR-305). "Add what I need for lasagne to my shopping list": the agent
// proposes the ingredients from its own knowledge, so they are only a suggestion. One card lists
// them with a tick each; anything already open on the list starts unticked and says so. The user
// unticks what they have and taps once; only the ticked ones are added, through the same add as
// add_to_list, and read back. Text from a recipe, web page or note is never a request on its own:
// the agent uses this tool only when the user asks for a dish's ingredients.

extension VoiceToolName {
    public static let addIngredients = "add_ingredients"
}

public struct IngredientsProposal: Equatable, Sendable {
    public static let maxItems = 30

    public let list: String
    public let dish: String
    public let items: [String]

    public init(list: String, dish: String, items: [String]) {
        self.list = list
        self.dish = dish
        self.items = items
    }

    /// Cleaned, without repeats (same words ignoring case and accents), at most `maxItems`.
    public static func cleanedItems(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for text in raw {
            guard let clean = ListText.cleaned(text), clean.count <= ListLimits.itemLength else { continue }
            let key = ListMatch.key(clean)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(clean)
            if result.count == maxItems { break }
        }
        return result
    }

    /// Positions of the items already open on the list; the card starts them unticked.
    public static func alreadyOpen(_ items: [String], on list: DoddyList) -> Set<Int> {
        let open = Set(list.open.map { ListMatch.key($0.text) })
        return Set(items.indices.filter { open.contains(ListMatch.key(items[$0])) })
    }
}

extension VoiceToolRequest {
    /// list (one of the user's lists), dish, and items (the ingredients, short names).
    static func parseIngredients(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let list = args.text("list").flatMap(ListText.cleaned) else { return .invalid(name: name, reason: "missing list") }
        guard let dish = args.text("dish")?.trimmingCharacters(in: .whitespacesAndNewlines), !dish.isEmpty else {
            return .invalid(name: name, reason: "missing dish")
        }
        let items = IngredientsProposal.cleanedItems(args.texts("items") ?? [])
        guard !items.isEmpty else { return .invalid(name: name, reason: "missing items") }
        return .addIngredients(IngredientsProposal(list: list, dish: String(dish.prefix(80)), items: items))
    }
}

/// Why ingredients were left out, each named as it really was: already open on the list, on the At home list, or
/// unticked by the person on the card. Since step 2b of decision `2026-11-14-spoken-yes-and-fewer-cards` they are
/// added with no card, so only the first two happen then, and the agent is never told the person unticked one.
public struct IngredientsLeftOut: Equatable, Sendable {
    public var onTheList: [String]
    public var atHome: [String]
    public var unticked: [String]

    public init(onTheList: [String] = [], atHome: [String] = [], unticked: [String] = []) {
        self.onTheList = onTheList
        self.atHome = atHome
        self.unticked = unticked
    }

    /// The names came from the model, so they go back as data (review C4).
    var text: String {
        func part(_ title: String, _ items: [String]) -> String {
            items.isEmpty ? "" : "\n\(title):\n" + ToolData.block(items.map { "- \(ToolData.clean($0))" })
        }
        return part("Left out, already on the list", onTheList)
            + part("Left out, on the user's At home list", atHome)
            + part("Left out, the user unticked them on the card", unticked)
    }
}

extension VoiceToolReply {
    public static let ingredientsDeclined = "declined: the user chose not to add the ingredients. Nothing was added."
    /// Nothing was added: every ingredient was left out, for the reasons that follow.
    public static func ingredientsNoneAdded(_ leftOut: IngredientsLeftOut) -> String {
        "not added: none of the ingredients were added. Nothing was added." + leftOut.text
    }

    /// What was added (read back by the list store) and what was left out, and why.
    public static func ingredientsAdded(_ result: ListAddResult, list: String, dish: String, leftOut: IngredientsLeftOut) -> String {
        // The dish came from the model, so it goes back as data (review C4).
        listAdded(result, list: list) + leftOut.text
            + "\nThese were Doddy's suggestions for this dish; say so if the user asks where they came from:\n"
            + ToolData.block(["Dish: \"\(ToolData.clean(dish))\""])
    }
}

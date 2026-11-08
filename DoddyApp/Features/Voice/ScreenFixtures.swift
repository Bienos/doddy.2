#if DEBUG
import ActivityKit
import DoddyCore
import Foundation
import SwiftUI
import UIKit

/// Real screens with sample data, for the screens run (ADR-821). `-screenFixture <name>` on the
/// command line makes a Debug build put one state on screen that the offline simulator can't reach
/// by itself, so `DoddyUITests/ScreenFixtureTests` can photograph the app's own views:
///
/// - `card:<id>`: the transcript sheet with a conversation holding that card. The card is made the
///   way the agent's tool call makes it (`VoiceToolRequest.parse` on sample arguments), then shown by
///   the controller's own test seam. No provider, no microphone, no network, no write to Calendar,
///   Reminders or anything else: the stand-in link below drops every reply.
/// - `deals`, `dealsHome`: "Cheapest this week" holds an answer (and, for `dealsHome`, Home shows its
///   "Leaflet offers" card). The answer is the repository's contract fixture: made-up shops and prices.
/// - `errand`: Tasks holds one finished shopping task (the same fixture's result) and Home shows its
///   "Done" card.
/// - `report`: the shopping report PDF the app makes for that task, its two pages full screen.
/// - `island:<state>`: the app's real voice Live Activity in one real state (the one a conversation
///   sends), for iOS to draw on the simulator's island and Lock Screen. No conversation behind it.
///
/// Nothing here ships: the whole file is `#if DEBUG`, and nothing runs without the launch argument.
/// NOT COMPILED OR RUN in the authoring environment (Linux, no Xcode): the hosted Mac job is the
/// first compile.
@MainActor
enum ScreenFixtures {
    static let argument = "-screenFixture"

    /// The fixture named on the command line, if any.
    static var requested: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: argument), at + 1 < arguments.count else { return nil }
        return arguments[at + 1]
    }

    /// Called once from `DoddyApp.init` (Debug builds only).
    static func startIfRequested(store: MemoryStore) {
        guard let name = requested else { return }
        if name == "deals" || name == "dealsHome" {
            seedDeals(homeCard: name == "dealsHome")
        } else if name == "errand" {
            Task { await seedErrand() }
        } else if name.hasPrefix("island:") {
            let id = String(name.dropFirst("island:".count))
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                startIsland(id)
            }
        } else if name == "report" {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                presentReport()
            }
        } else if name.hasPrefix("card:") {
            let id = String(name.dropFirst("card:".count))
            // Home first, so the sheet comes up over it as it does in a conversation.
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                presentCard(id, store: store)
            }
        }
    }

    // MARK: The conversation with a card

    private static func presentCard(_ id: String, store: MemoryStore) {
        let controller = VoiceSessionController(store: store)
        let link = FixtureLink()
        controller.beginForTesting(link: link)
        let words = lines(id)
        controller.addLineForTesting(words.user, fromUser: true)
        controller.addLineForTesting(words.doddy, fromUser: false)
        if let action = pending(id) {
            controller.showCardForTesting(action, link: link)
        }
        HomeConversation.shared.hold(controller)
        ShortcutRouter.shared.isVoicePresented = true
    }

    /// What was said before the card, in the transcript.
    private static func lines(_ id: String) -> (user: String, doddy: String) {
        switch id {
        case "memory": ("Remember the gate code at Ola's is 4821.", "Got it. Tap Save if that's right.")
        case "event": ("Put the dentist in the day after tomorrow at four.", "The day after tomorrow, 16:00 to 17:00. Tap Add if that's right.")
        case "reminder": ("Remind me to call Mum at six tomorrow.", "Tomorrow at 18:00. Tap Add if that's right.")
        case "timer": ("Set a timer for eight minutes.", "Eight minutes for the pasta. Tap Start.")
        case "alarm": ("Wake me at seven on weekdays.", "Weekdays at 07:00. Tap Set alarm.")
        case "message": ("Text Ola that I'm running late.", "Here's the text. You send it yourself.")
        case "blik": ("Send Ania fifty zloty for the pizza.", "Here's the transfer. You send it in your bank app.")
        case "email": ("Email the landlord about the boiler.", "Here's the email. Nothing is sent until you tap.")
        case "presentation": ("Make me a short deck for the offsite.", "Six slides. Tap Make presentation.")
        case "plan": ("I'm at Mum's for lunch in three days, sort it out.", "Here's what I'd do. Untick anything you don't want.")
        case "ingredients": ("Add what I need for pancakes to Shopping.", "Untick what you already have.")
        case "parking": ("I parked on level two, row C.", "Save your parking spot here?")
        case "changeEvent": ("Move the dentist a day later.", "Here's the change. Nothing happens until you tap.")
        case "deleteEvent": ("Cancel my dentist the day after tomorrow.", "This can't be undone from Doddy. Tap Delete.")
        case "map": ("Show me where the Biedronka is.", "Open it in Maps?")
        case "shortcut": ("Run my Good night shortcut.", "The Shortcuts app opens for a moment.")
        case "camera": ("Take a photo of the receipt.", "Open the camera?")
        case "createList": ("Start a list called Weekend shop.", "Fix the name if I misheard.")
        case "askYes": ("What's the weather in Kraków on Saturday?", "I'd look that up on the web. Say yes, or tap.")
        case "askTap": ("Add milk and eggs to Shopping.", "Nothing changes until you tap.")
        default: ("Hello.", "Hi.")
        }
    }

    private static func pending(_ id: String) -> VoiceSessionController.PendingAction? {
        let call = "fixture-\(id)"
        let hour: TimeInterval = 3600
        switch id {
        case "memory":
            return .memory(toolCallID: call, text: "Gate code for Ola's building is 4821.")
        case "event":
            guard case .createCalendarEvent(let draft) = parse("create_calendar_event", [
                "title": "Dentist", "start": when(2, 16, 0), "end": when(2, 17, 0), "location": "ul. Hoża 9",
            ]) else { return nil }
            return .event(toolCallID: call, draft: draft)
        case "reminder":
            guard case .createReminder(let draft) = parse("create_reminder", [
                "title": "Call Mum", "due": when(1, 18, 0),
            ]) else { return nil }
            return .reminder(toolCallID: call, draft: draft)
        case "timer":
            guard case .setTimer(let draft) = parse("set_timer", ["minutes": 8, "label": "Pasta"]) else { return nil }
            return .timer(toolCallID: call, draft: draft)
        case "alarm":
            guard case .setAlarm(let draft) = parse("set_alarm", [
                "time": when(1, 7, 0), "repeat": "weekdays", "label": "Gym",
            ]) else { return nil }
            return .alarm(toolCallID: call, draft: draft)
        case "message":
            guard case .draftMessage(let draft) = parse("draft_message", [
                "to": "Ola", "body": "Running 10 min late, sorry!", "channel": "text",
            ]) else { return nil }
            return .message(toolCallID: call, draft: draft, address: "+48 500 100 200")
        case "blik":
            guard case .draftBlikTransfer(let draft) = parse("draft_blik_transfer", [
                "to": "Ania", "amount": 50, "title": "Pizza",
            ]) else { return nil }
            return .blik(toolCallID: call, draft: draft, contactName: "Ania Kowalska",
                         numbers: BlikPhone.numbers(["+48 600 200 300"]))
        case "email":
            let json = #"{"title":"Send this email?","lines":["To: landlord@example.pl","Subject: Boiler","Hi, the boiler is making that noise again. Could someone come this week?","Nothing is sent until you tap."],"confirmLabel":"Send"}"#
            guard let preview = try? JSONDecoder().decode(ToolPreview.self, from: Data(json.utf8)) else { return nil }
            return .cloud(toolCallID: call, call: CloudToolCall(name: "send_email", arguments: [:]),
                          preview: preview, approvalID: UUID(), mode: .live)
        case "presentation":
            guard case .makePresentation(let draft) = parse("make_presentation", [
                "title": "Team offsite", "subtitle": "Q1 planning",
                "slides": [
                    ["title": "Where we are", "points": ["Revenue up 12%", "Two launches shipped"]],
                    ["title": "What we heard", "points": ["Onboarding is too long", "Reports are slow"]],
                    ["title": "Three bets for Q1", "points": ["Shorter onboarding", "Faster reports", "A partner programme"]],
                    ["title": "Next steps", "points": ["Owners by Friday"]],
                    ["title": "Questions", "points": [String]()],
                ] as [[String: Any]],
            ]) else { return nil }
            return .presentation(toolCallID: call, draft: draft)
        case "plan":
            let steps: [[String: Any]] = [
                ["tool": "create_reminder", "title": "Leave for Mum's", "due": when(3, 12, 15)],
                ["tool": "create_calendar_event", "title": "Lunch at Mum's", "start": when(3, 13, 0), "end": when(3, 15, 0)],
                ["tool": "save_memory", "text": "Bring flowers for Mum"],
            ]
            guard case .plan(let parsed) = PlanProposal.parse(parametersJSON: params(["steps": steps])) else { return nil }
            return .plan(toolCallID: call, steps: parsed, blocked: [:])
        case "ingredients":
            return .ingredients(toolCallID: call, listID: UUID(), listName: "Shopping", dish: "pancakes",
                                items: ["flour", "milk", "eggs", "butter", "sugar"], alreadyOpen: [1])
        case "parking":
            return .parking(toolCallID: call, spot: ParkingSpot(
                latitude: 52.2297, longitude: 21.0122, accuracyMeters: 12, savedAt: Date(), note: "level 2, row C"))
        case "changeEvent":
            let was = Date().addingTimeInterval(48 * hour)
            let now = Date().addingTimeInterval(72 * hour)
            let plan = EventChangePlan(
                before: CalendarEventSummary(title: "Dentist", start: was, end: was.addingTimeInterval(hour), allDay: false),
                after: CalendarEventSummary(title: "Dentist", start: now, end: now.addingTimeInterval(hour), allDay: false))
            return .changeEvent(toolCallID: call, plan: plan)
        case "deleteEvent":
            let start = Date().addingTimeInterval(48 * hour)
            return .deleteEvent(toolCallID: call, event: CalendarEventSummary(
                title: "Dentist", start: start, end: start.addingTimeInterval(hour), allDay: false))
        case "map":
            return .map(toolCallID: call, place: "Biedronka, ul. Hoża 9")
        case "shortcut":
            return .shortcut(toolCallID: call, name: "Good night")
        case "camera":
            return .camera(toolCallID: call)
        case "createList":
            return .createList(toolCallID: call, name: "Weekend shop", items: ["milk", "eggs", "bread"])
        case "askYes":
            return .ask(toolCallID: call, card: AskCard(
                title: "Search the web?", lines: ["“weather Kraków Saturday”"], confirmLabel: "Yes, search"),
                        needsTap: false, toolName: "web_search", parameters: Data("{}".utf8))
        case "askTap":
            return .ask(toolCallID: call, card: AskCard(
                title: "Add to Shopping?", lines: ["milk", "eggs"], confirmLabel: "Add"),
                        needsTap: true, toolName: "add_to_list", parameters: Data("{}".utf8))
        default:
            return nil
        }
    }

    /// The agent's own path: arguments as JSON, parsed by DoddyCore's real parser.
    private static func parse(_ name: String, _ fields: [String: Any]) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: params(fields))
    }

    private static func params(_ fields: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: fields)) ?? Data("{}".utf8)
    }

    /// "2026-11-03T18:00": local time, `days` from today, as the agent writes times.
    private static func when(_ days: Int, _ hour: Int, _ minute: Int) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02dT%02d:%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1, hour, minute)
    }

    // MARK: Shopping

    private static func seedDeals(homeCard: Bool) {
        guard let result = try? JSONDecoder().decode(DealsResult.self, from: Data(ScreenFixtureData.deals.utf8)) else { return }
        let request = DealsRequest(items: result.items.map(\.query), language: "pl")
        DealsModel.shared.seedForTesting(request: request, result: result, homeCard: homeCard)
    }

    private static func seedErrand() async {
        guard let result = try? JSONDecoder().decode(ErrandResult.self, from: Data(ScreenFixtureData.shoppingResult.utf8)) else { return }
        let draft = ErrandDraft(
            words: "Szukam cichej zmywarki do zabudowy, 45 cm, do 2000 zł. Najważniejsza cisza, potem cena, potem gwarancja.",
            brief: "Cicha zmywarka do zabudowy 45 cm, do 2000 zł; cisza, cena, gwarancja.",
            title: "Cicha zmywarka 45 cm", language: "pl", kind: .shopping, priorities: ["Cisza", "Cena", "Gwarancja"])
        let record = StoredErrand(id: UUID(), createdAt: Date(), state: .done, draft: draft, result: result, resultDigest: "fixture")
        _ = try? await AppEnvironment.shared.errandRepository.save(record)
        await ErrandsModel.shared.load()
        ErrandsModel.shared.seedUnseenForTesting([record.id])
    }
}

extension ScreenFixtures {
    /// The report the app writes for the fixture task (`ShoppingReport.temporaryFile`), drawn page by
    /// page, full screen: the pictures are the PDF's own pages.
    fileprivate static func presentReport() {
        guard let result = try? JSONDecoder().decode(ErrandResult.self, from: Data(ScreenFixtureData.shoppingResult.utf8)),
              let shopping = result.shopping else { return }
        let report = ShoppingReport(
            title: "Cicha zmywarka 45 cm",
            words: "Szukam cichej zmywarki do zabudowy, 45 cm, do 2000 zł. Najważniejsza cisza, potem cena, potem gwarancja.",
            result: result, shopping: shopping, language: .english, madeAt: Date())
        guard let url = try? report.temporaryFile() else { return }
        showFullScreen(ReportPictures(pages: rasterize(url)))
    }

    private static func rasterize(_ url: URL) -> [UIImage] {
        guard let document = CGPDFDocument(url as CFURL) else { return [] }
        var images: [UIImage] = []
        for number in 1...max(1, document.numberOfPages) {
            guard let page = document.page(at: number) else { continue }
            let box = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2
            let size = CGSize(width: box.width * scale, height: box.height * scale)
            images.append(UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.set()
                context.fill(CGRect(origin: .zero, size: size))
                let cg = context.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: scale, y: -scale)
                cg.drawPDFPage(page)
            })
        }
        return images
    }

    /// Any plain SwiftUI view on top of the app, full screen, for a picture.
    fileprivate static func showFullScreen<V: View>(_ view: V) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: false)
    }
}

private struct ReportPictures: View {
    let pages: [UIImage]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(pages.indices, id: \.self) { index in
                    Image(uiImage: pages[index])
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .shadow(radius: 3)
                        .accessibilityIdentifier("fixture.reportPage.\(index)")
                }
            }
            .padding(10)
        }
        .background(Color(white: 0.82))
        .accessibilityIdentifier("fixture.report")
    }
}

extension ScreenFixtures {
    private static var islandActivity: Activity<DoddyVoiceAttributes>?

    /// The real voice Live Activity in one real state. Statuses and moments are the ones a
    /// conversation sends (see `IslandScreenshotTests`); iOS draws the island and the Lock Screen card.
    fileprivate static func startIsland(_ id: String) {
        typealias State = DoddyVoiceAttributes.ContentState
        var state: State
        switch id {
        case "connecting": state = State(status: .connecting, isMuted: false)
        case "listening": state = State(status: .listening, isMuted: false)
        case "thinking": state = State(status: .thinking, isMuted: false)
        case "speaking": state = State(status: .speaking, isMuted: false)
        case "muted": state = State(status: .listening, isMuted: true)
        case "confirm": state = State(status: .needsConfirmation, isMuted: false)
        case "text":
            state = State(status: .needsConfirmation, isMuted: false)
            state.moment = .actionWaiting(.text)
        case "transfer":
            state = State(status: .needsConfirmation, isMuted: false)
            state.moment = .actionWaiting(.transfer)
        case "document":
            state = State(status: .speaking, isMuted: false)
            state.moment = .resultReady(.document)
        case "translator":
            state = State(status: .listening, isMuted: false)
            state.moment = .translating(from: "pl", to: "en", bothWays: true)
        default:
            return
        }
        state.language = Bundle.main.preferredLocalizations.first
        // The same attributes and content the conversation's activity sends, requested here with the
        // answer shown on screen: the first run's pictures (2 Nov) showed an empty island and no Lock
        // Screen card, and `VoiceLiveActivity.show` swallows the reason a request fails.
        var report = "activities enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled)"
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                let activity = try Activity.request(
                    attributes: DoddyVoiceAttributes(startedAt: .now),
                    content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(900)),
                    pushType: nil)
                islandActivity = activity
                report += "; started \(activity.id.prefix(8)) (\(id))"
            } catch {
                report += "; request failed: \(error)"
            }
        }
        showIslandReport(report)
    }

    /// The outcome as a label on the app's own screen (read by the test, kept with the pictures).
    private static func showIslandReport(_ text: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) else { return }
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.accessibilityIdentifier = "fixture.island.report"
        label.frame = CGRect(x: 8, y: window.safeAreaInsets.top + 70, width: window.bounds.width - 16, height: 64)
        window.addSubview(label)
    }
}

/// Stands in for the voice provider: every call is accepted and nothing is sent anywhere.
@MainActor
private final class FixtureLink: LiveVoiceLink {
    func sendToolResult(for toolCallId: String, result: String, isError: Bool) async throws {}
    func setMuted(_ muted: Bool) async throws {}
    func sendMessage(_ text: String) async throws {}
    func updateContext(_ context: String) async throws {}
    func endConversation() async {}
    func setAgentVolume(_ volume: Double) -> Double? { nil }
}
#endif

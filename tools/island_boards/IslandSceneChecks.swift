import Foundation

/// What the island shows for each real conversation state (run by IslandArtCheck).
enum IslandSceneChecks {
    typealias State = DoddyVoiceAttributes.ContentState

    static func run() -> Int {
        var failures = 0
        func expect(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: scene: \(message)"); failures += 1 }
        }

        // Live listening on every style: orange allowed, bars, Doddy listening.
        for style in IslandStyle.allCases {
            var s = State(status: .listening, isMuted: false)
            s.islandStyle = style
            let scene = s.islandScene(isStale: false)
            expect(scene.board == style.board, "\(style) uses its board")
            expect(scene.live, "\(style) listening is live")
            expect(scene.face == .listening, "\(style) listening face")
            expect(scene.minimalSign == .bars, "\(style) minimal bars")
        }

        // Muted: not live, calm face, mic-slash, Lean In's hand gone.
        let muted = State(status: .listening, isMuted: true).islandScene(isStale: false)
        expect(!muted.live && muted.face == .calm && !muted.showsHands, "muted")
        expect(muted.compactSign == .symbol("mic.slash.fill", .secondary), "muted symbol")

        // Connecting is not live (no orange before the conversation is up).
        expect(!State(status: .connecting, isMuted: false).islandScene(isStale: false).live, "connecting not live")

        // Stale: warning, never live, whatever the state said.
        let stale = State(status: .speaking, isMuted: false).islandScene(isStale: true)
        expect(!stale.live && stale.subtitleIsWarning && stale.title.hasPrefix("Lost"), "stale")

        // Speaking face; Here With You thinking uses its second board.
        expect(State(status: .speaking, isMuted: false).islandScene(isStale: false).face == .speaking, "speaking face")
        var thinking = State(status: .thinking, isMuted: false)
        thinking.islandStyle = .hereWithYou
        expect(thinking.islandScene(isStale: false).scenario == 1, "here with you thinking board")

        // "Hey Doddy" waiting (ADR-254) is not a conversation, on every style: not live, no timer,
        // its own label; a stale one says nothing is listening any more.
        for style in IslandStyle.allCases {
            var s = State.wakeListening
            s.islandStyle = style
            let scene = s.islandScene(isStale: false)
            expect(scene.board == style.board && !scene.live, "\(style) wake listening not live")
            expect(scene.label == "HEY DODDY" && scene.time == .text(""), "\(style) wake label, no timer")
            expect(scene.title == "Say “Hey Doddy”", "\(style) wake title")
        }
        let wakeStale = State.wakeListening.islandScene(isStale: true)
        expect(wakeStale.title == "Not listening — open Doddy" && !wakeStale.live, "wake stale")
        expect(State.wakePaused.islandScene(isStale: false).title == "“Hey Doddy” paused", "wake paused")
        // The greeting replaces Connecting and Listening only; Muted and Thinking win over it.
        var greeted = State(status: .connecting, isMuted: false, greeting: "Hey Pat, what's up?")
        expect(greeted.islandScene(isStale: false).title == "Hey Pat, what's up?", "greeting while connecting")
        expect(greeted.islandScene(isStale: false).label == "VOICE", "greeting is a conversation")
        greeted.status = .thinking
        expect(greeted.islandScene(isStale: false).title == "Thinking…", "greeting gone once thinking")
        let greetedMuted = State(status: .listening, isMuted: true, greeting: "Hey Pat, what's up?")
        expect(greetedMuted.islandScene(isStale: false).title == "Muted", "muted beats greeting")
        let wakeConversation = State(
            status: .listening, isMuted: false, greeting: "Hej Pat, co słychać?",
            conversationStartedAt: Date(timeIntervalSince1970: 5))
        if let data = try? JSONEncoder().encode(wakeConversation) {
            expect((try? JSONDecoder().decode(State.self, from: data)) == wakeConversation, "greeting round trip")
        } else {
            expect(false, "encode greeting")
        }

        // Moments.
        var note = State(status: .needsConfirmation, isMuted: false)
        note.moment = .noteWaiting
        let noteScene = note.islandScene(isStale: false)
        expect(noteScene.board == .thoughtPocket && !noteScene.live, "note waiting: pocket, not live")
        var saved = State(status: .listening, isMuted: false)
        saved.moment = .noteSaved
        expect(saved.islandScene(isStale: false).scenario == 1, "note saved board")
        var plan = State(status: .listening, isMuted: false)
        plan.moment = .planRunning(step: 2, of: 3)
        expect(plan.islandScene(isStale: false).compactSign == .text("2/3"), "plan running counts")
        var reminder = State(status: .listening, isMuted: false)
        reminder.moment = .reminderSet
        expect(reminder.islandScene(isStale: false).board == .reminderKnot, "reminder set")
        // A stale island never shows a moment.
        expect(reminder.islandScene(isStale: true).board == .leanIn, "stale hides moment")

        // Old content (no moment / style) still decodes; an unknown style falls back to Lean In.
        let old = #"{"status":"listening","isMuted":false}"#
        let decodedOld = try? JSONDecoder().decode(State.self, from: Data(old.utf8))
        expect(decodedOld?.islandStyle == .leanIn && decodedOld?.moment == nil, "old content decodes")
        let future = #"{"status":"listening","isMuted":false,"islandStyle":"somethingNew"}"#
        expect((try? JSONDecoder().decode(State.self, from: Data(future.utf8)))?.islandStyle == .leanIn, "unknown style")

        // Round trip keeps style and moment.
        var round = State(status: .speaking, isMuted: false)
        round.islandStyle = .orbit
        round.moment = .planWaiting(steps: 4)
        if let data = try? JSONEncoder().encode(round) {
            expect((try? JSONDecoder().decode(State.self, from: data)) == round, "round trip")
        } else {
            expect(false, "encode")
        }
        failures += translating()
        failures += tools()
        return failures
    }

    /// Every word the island can draw for a scene: label, time, status, signs and art labels.
    static func words(_ scene: IslandScene) -> [String] {
        func sign(_ s: IslandSign) -> String? {
            if case .text(let t) = s { return t }
            if case .symbol(let name, _) = s { return name }
            return nil
        }
        var out = [scene.label, scene.title, scene.subtitle]
        if case .text(let t) = scene.time { out.append(t) }
        if case .text(let t)? = scene.bigTitle { out.append(t) }
        if case .bigText(let t)? = scene.bigTitle { out.append(t) }
        out += [scene.expandedSign, scene.compactSign, scene.minimalSign].compactMap(sign)
        out += scene.artLabels.map(\.text)
        return out
    }

    /// Translator mode on Language Bridge (ADR-244). Private: the pair only, as codes.
    static func translating() -> Int {
        var failures = 0
        func expect(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: translating scene: \(message)"); failures += 1 }
        }

        // Face to face, English and French: both ways.
        var both = State(status: .listening, isMuted: false)
        both.moment = .translating(from: "en", to: "fr", bothWays: true)
        let b = both.islandScene(isStale: false)
        expect(b.board == .languageBridge && b.scenario == 0, "language bridge, first board")
        expect(b.label == "TRANSLATE" && b.title == "Translating", "label and title")
        expect(b.subtitle == "EN ⇄ FR", "face to face pair, got \(b.subtitle)")
        expect(b.artLabels.map(\.text) == ["EN", "FR"], "bubbles EN and FR")
        expect(b.compactSign == .text("⇄ FR") && b.minimalSign == .text("FR"), "compact and minimal")
        expect(b.live, "listening while translating is live")

        // Listen only: one way, as on the board ("EN → FR").
        var listen = State(status: .speaking, isMuted: false)
        listen.moment = .translating(from: "en", to: "fr", bothWays: false)
        let l = listen.islandScene(isStale: false)
        expect(l.subtitle == "EN → FR" && l.compactSign == .text("→ FR"), "listen only pair")

        // Their language not known yet.
        var unknown = State(status: .listening, isMuted: false)
        unknown.moment = .translating(from: "pl", to: "?", bothWays: true)
        expect(unknown.islandScene(isStale: false).subtitle == "PL ⇄ ?", "unknown language")

        // Never the second board ("Translation ready / Hear it"), whatever the state.
        for status in [State.Status.connecting, .listening, .thinking, .speaking, .needsConfirmation] {
            for muted in [false, true] {
                var s = State(status: status, isMuted: muted)
                s.moment = .translating(from: "de", to: "it", bothWays: true)
                let scene = s.islandScene(isStale: false)
                expect(scene.board == .languageBridge && scene.scenario == 0, "\(status) muted \(muted): board 0")
                expect(!words(scene).contains { $0.contains("ready") || $0.contains("Hear it") }, "no ready step")
            }
        }

        // Muted (hold-to-talk between turns): not live, so the orange line turns grey.
        var muted = State(status: .listening, isMuted: true)
        muted.moment = .translating(from: "en", to: "fr", bothWays: true)
        expect(!muted.islandScene(isStale: false).live, "muted translating not live")

        // Private: a phrase in place of a code is never drawn, anywhere on the island.
        let phrase = "Where is the station"
        var leak = State(status: .listening, isMuted: false)
        leak.moment = .translating(from: phrase, to: "Il treno parte alle otto", bothWays: true)
        let leaked = leak.islandScene(isStale: false)
        expect(leaked.subtitle == "? ⇄ ?" && leaked.artLabels.map(\.text) == ["?", "?"], "phrase shown as ?")
        for word in ["Where", "station", "treno", "otto"] {
            expect(!words(leaked).contains { $0.lowercased().contains(word.lowercased()) }, "\"\(word)\" never on the island")
        }
        for code in ["e", "engl", "e1", "é", "en fr", ""] {
            expect(IslandLanguageCode.shown(code) == "?", "\"\(code)\" is not a code")
        }
        expect(IslandLanguageCode.shown("pl") == "PL" && IslandLanguageCode.shown("ast") == "AST", "codes")

        // Stale: the warning, not the translator board.
        expect(both.islandScene(isStale: true).board == .leanIn, "stale hides translating")

        // Round trip; an older build without the case drops the moment, not the island.
        if let data = try? JSONEncoder().encode(both) {
            expect((try? JSONDecoder().decode(State.self, from: data)) == both, "round trip")
        } else {
            expect(false, "encode")
        }
        let newer = #"{"status":"listening","isMuted":false,"moment":{"somethingNew":{}}}"#
        let decoded = try? JSONDecoder().decode(State.self, from: Data(newer.utf8))
        expect(decoded != nil && decoded?.moment == nil, "unknown moment dropped")
        return failures
    }

    /// Whole Doddy (ADR-264): one pose per state, the same rules for every conversation.
    static func wholeDoddy() -> Int {
        var failures = 0
        func expect(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: whole doddy: \(message)"); failures += 1 }
        }
        func pose(_ state: State, stale: Bool = false) -> IslandPose? {
            var s = state
            s.islandStyle = .wholeDoddy
            return s.islandScene(isStale: stale).pose
        }
        expect(pose(State(status: .connecting, isMuted: false)) == .yawnStretch, "connecting stretches")
        expect(pose(State(status: .listening, isMuted: false)) == .listening, "listening")
        expect(pose(State(status: .thinking, isMuted: false)) == .kneelingInspect, "thinking")
        expect(pose(State(status: .speaking, isMuted: false)) == .shrug, "speaking")
        expect(pose(State(status: .listening, isMuted: true)) == .shush, "muted beats listening")
        expect(pose(State(status: .speaking, isMuted: false), stale: true) == .facepalm, "stale")
        expect(pose(State.wakeListening) == .crosslegged, "hey doddy waiting")
        expect(pose(State.wakePaused) == .leaning, "hey doddy paused")
        expect(pose(State(status: .connecting, isMuted: false, greeting: "Hey Pat, what's up?")) == .onelegBalance, "greeting")
        expect(pose(State(status: .speaking, isMuted: false, greeting: "Hey Pat, what's up?")) == .shrug, "greeting gone once speaking")
        expect(pose(State(status: .listening, isMuted: true, greeting: "Hey Pat, what's up?")) == .shush, "muted beats greeting")
        var ended = State(status: .ended, isMuted: false)
        ended.savedCount = 1
        expect(pose(ended) == .fistpump, "ended")
        let moments: [(State.Moment, IslandPose?)] = [
            (.noteWaiting, .reachingHigh), (.noteSaved, .fistpump), (.reminderWaiting, .reachingHigh),
            (.reminderAdding, .reachingHigh), (.reminderSet, .fistpump), (.planWaiting(steps: 3), .tiptoe),
            (.planRunning(step: 1, of: 3), .tiptoe), (.translating(from: "en", to: "pl", bothWays: true), nil)
        ]
        for (moment, expected) in moments {
            var s = State(status: .listening, isMuted: false)
            s.moment = moment
            expect(pose(s) == expected, "\(moment)")
        }
        // Translating keeps Language Bridge's own drawing; a stale moment is the stale pose.
        var translating = State(status: .listening, isMuted: false)
        translating.moment = .translating(from: "en", to: "pl", bothWays: true)
        translating.islandStyle = .wholeDoddy
        expect(translating.islandScene(isStale: false).board == .languageBridge, "translating board")
        var saved = State(status: .listening, isMuted: false)
        saved.moment = .noteSaved
        expect(pose(saved, stale: true) == .facepalm, "stale moment")
        // Every other style draws its board, never a pose.
        for style in IslandStyle.allCases where style != .wholeDoddy {
            var s = State(status: .listening, isMuted: false)
            s.islandStyle = style
            expect(s.islandScene(isStale: false).pose == nil, "\(style) has no pose")
        }
        // The style round-trips and an unknown one still falls back to Lean In.
        var styled = State(status: .listening, isMuted: false)
        styled.islandStyle = .wholeDoddy
        if let data = try? JSONEncoder().encode(styled) {
            expect((try? JSONDecoder().decode(State.self, from: data))?.islandStyle == .wholeDoddy, "style round trip")
        }
        // Pictures: each figure box inside its picture; every face pose has a head inside it.
        for p in IslandPose.allCases {
            let b = p.figure
            expect(b.x >= 0 && b.y >= 0 && b.x + b.width <= 1 && b.y + b.height <= 1 && b.width > 0.2 && b.height > 0.3, "\(p) figure box")
            guard let head = p.facePose.head else { expect(false, "\(p) face pose \(p.facePose) has no head"); continue }
            expect(head.diameter > 0.2 && head.diameter < 0.7 && head.x > 0.2 && head.x < 0.8 && head.y > 0 && head.y < 0.5, "\(p) head")
        }
        return failures
    }

    static func tools() -> Int {
        var failures = 0
        func expect(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: tool scene: \(message)"); failures += 1 }
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let end = now.addingTimeInterval(600)
        let focus = DoddyToolAttributes(kind: .focus, startedAt: now, duration: 1500)

        let running = focus.islandScene(.init(isPaused: false, endsAt: end, label: "Write"), isStale: false, now: now)
        expect(running.board == .tinyPromise && running.scenario == 0 && running.live, "focus running")
        expect(running.bigTitle == .countdown(end) && running.subtitle == "Write", "focus countdown and label")
        expect(running.time == .text("25 min"), "focus length")

        let paused = focus.islandScene(.init(isPaused: true, endsAt: nil, remaining: 768), isStale: false, now: now)
        expect(paused.scenario == 1 && !paused.live && paused.bigTitle == .bigText("12:48"), "focus paused 12:48")
        expect(paused.minimalSign == .text("13m"), "focus paused minimal rounds up")

        // Its stale date is the end time, so stale means the time is up, never "still running".
        let due = focus.islandScene(.init(isPaused: false, endsAt: end), isStale: true, now: now)
        expect(due.title == "Time's up" && !due.live, "focus time up")

        let breathing = DoddyToolAttributes(kind: .breathing, startedAt: now, duration: 120)
        let b = breathing.islandScene(.init(isPaused: false, endsAt: end), isStale: false, now: now)
        expect(b.board == .calmTide && b.time == .countdown(end), "breathing")
        expect(!b.title.contains("in") || b.title == "Breathing", "breathing shows no phase")

        let read = DoddyToolAttributes(kind: .readAloud, startedAt: now, duration: 0)
        expect(read.islandScene(.init(isPaused: false), isStale: false, now: now).compactSign == .bars, "reading")
        let lost = read.islandScene(.init(isPaused: false), isStale: true, now: now)
        expect(!lost.live && lost.subtitleIsWarning, "read aloud lost")
        expect(DoddyToolAttributes.clock(3725) == "1:02:05" && DoddyToolAttributes.clock(59.2) == "1:00", "clock")
        return failures
    }
}

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

    /// Translator mode on Language Bridge (ADR-227). Private: the pair only, as codes.
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

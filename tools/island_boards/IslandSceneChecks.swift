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
        // ADR-570: Doddy's first message is the greeting, so the island shows it while he says it
        // (the moment the island opens up), not "Speaking".
        greeted.status = .speaking
        expect(greeted.islandScene(isStale: false).title == "Hey Pat, what's up?", "greeting while he says it")
        expect(greeted.islandScene(isStale: false).live, "greeting while speaking is live")
        greeted.status = .thinking
        expect(greeted.islandScene(isStale: false).title == "Working on it…", "greeting gone once thinking")
        var answered = State(status: .speaking, isMuted: false)
        expect(answered.islandScene(isStale: false).title == "Speaking", "no greeting: Speaking")
        answered.isMuted = true
        expect(answered.islandScene(isStale: false).title == "Muted", "muted while speaking")
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
        expect(pose(State(status: .connecting, isMuted: false, greeting: "Hey Pat, what's up?")) == .wave, "greeting waves")
        expect(pose(State(status: .listening, isMuted: false, greeting: "Hey Pat, what's up?")) == .wave, "greeting waves until you speak")
        // ADR-570: the greeting is his first message, so he waves while he says it too.
        expect(pose(State(status: .speaking, isMuted: false, greeting: "Hey Pat, what's up?")) == .wave, "waves while saying the greeting")
        expect(pose(State(status: .thinking, isMuted: false, greeting: "Hey Pat, what's up?")) == .kneelingInspect, "greeting gone once thinking")
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
        // The default (ADR-267): Whole Doddy until the user picks a style; a picked one is kept.
        expect(IslandStyle.preferredDefault == .wholeDoddy, "default is whole doddy")
        expect(IslandStyle.stored(nil) == .wholeDoddy && IslandStyle.stored("not-a-style") == .wholeDoddy, "nothing stored")
        expect(IslandStyle.stored("leanIn") == .leanIn && IslandStyle.stored("orbit") == .orbit, "a picked style is kept")
        expect(IslandStyle.allCases.first == .wholeDoddy, "listed first in Settings")
        // Pictures: each figure box inside its picture; every face pose has a head inside it.
        for p in IslandPose.allCases {
            let b = p.figure
            expect(b.x >= 0 && b.y >= 0 && b.x + b.width <= 1 && b.y + b.height <= 1 && b.width > 0.2 && b.height > 0.3, "\(p) figure box")
            guard let head = p.facePose.head else { expect(false, "\(p) face pose \(p.facePose) has no head"); continue }
            expect(head.diameter > 0.2 && head.diameter < 0.7 && head.x > 0.2 && head.x < 0.8 && head.y > 0 && head.y < 0.5, "\(p) head")
        }
        return failures
    }

    /// The voice screen's Doddy (ADR-299): the island's pose for the same moment, talking frames
    /// while he speaks.
    static func voiceScreen() -> Int {
        var failures = 0
        func expect(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: voice screen: \(message)"); failures += 1 }
        }
        func art(_ phase: VoiceScreenArt.Phase, muted: Bool = false, waiting: Bool = false, plan: Bool = false) -> VoiceScreenArt {
            VoiceScreenArt.shown(phase, muted: muted, awaitingConfirmation: waiting, planRunning: plan)
        }
        // In the app he walks in while connecting and runs while a plan's steps run (ADR-313).
        expect(art(.connecting) == .motion(.walk), "connecting walks")
        expect(art(.listening, plan: true) == .motion(.run), "a plan runs")
        expect(art(.thinking, plan: true) == .motion(.run), "a plan runs while thinking")
        expect(art(.speaking, plan: true) == .talking, "talking beats running")
        expect(art(.listening, waiting: true, plan: true) == .pose(.reachingHigh), "a card waiting beats running")
        expect(art(.connecting, plan: true) == .motion(.walk), "connecting before any plan")
        expect(art(.listening) == .pose(.listening), "listening")
        expect(art(.thinking) == .pose(.kneelingInspect), "thinking")
        expect(art(.speaking) == .talking, "speaking talks")
        expect(art(.speaking, muted: true) == .pose(.shush), "muted")
        expect(art(.listening, waiting: true) == .pose(.reachingHigh), "a card waits for a tap")
        expect(art(.ended, waiting: true) == .pose(.fistpump), "ended")
        expect(art(.failed, muted: true) == .pose(.facepalm), "failed beats muted")
        expect(art(.microphoneOff) == .pose(.shush), "no microphone")
        // The same poses as the island for the same moments (ADR-264).
        let pairs: [(VoiceScreenArt.Phase, State.Status)] = [(.listening, .listening), (.thinking, .thinking)]
        for (phase, status) in pairs {
            let island = State(status: status, isMuted: false).wholeDoddyPose(stale: false)
            expect(art(phase) == .pose(island ?? .wave), "\(phase) matches the island")
        }
        // Frames loop 1...6 and every frame shows for the same time.
        let d = VoiceScreenArt.talkingFrameDuration
        let frames = (0..<13).map { VoiceScreenArt.talkingFrame(at: Double($0) * d + d / 2) }
        expect(frames == [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6, 1], "frames loop: \(frames)")
        expect(VoiceScreenArt.talkingFrame(at: -5) == 1, "a time before zero")
        let box = VoiceScreenArt.talkingFigure
        expect(box.x >= 0 && box.y >= 0 && box.x + box.width <= 1 && box.y + box.height <= 1, "talking box")
        failures += motions()
        return failures
    }

    /// The strips (ADR-313): loops loop, once-only strips rest on their last frame, every box fits.
    static func motions() -> Int {
        var failures = 0
        func expect(_ ok: Bool, _ message: String) {
            if !ok { print("FAIL: motion: \(message)"); failures += 1 }
        }
        let walk = DoddyMotion.walk, d = walk.frameDuration
        expect((0..<17).map { walk.frame(at: Double($0) * d + d / 2) } == Array(1...8) + Array(1...8) + [1], "walk loops")
        let pop = DoddyMotion.pop
        expect(pop.frame(at: 0) == 1 && pop.frame(at: pop.duration + 5) == 4, "pop plays once and rests on frame 4")
        expect(DoddyMotion.jump.frame(at: 100) == 5 && DoddyMotion.jump.stillFrame == 5, "jump ends standing")
        expect(DoddyMotion.run.stillFrame == 1 && DoddyMotion.walk.stillFrame == 1, "a loop's still is its first frame")
        expect(DoddyMotion.turn.frames == [1, 2, 3] && DoddyMotion.turn.frame(at: 9) == 3 && DoddyMotion.turn.stillFrame == 3,
               "turn plays 1-3 once and rests turned (ADR-323)")
        expect(DoddyMotion.sit.frame(at: 0) == 1 && DoddyMotion.sit.frame(at: 9) == 5 && DoddyMotion.sit.stillFrame == 5,
               "sit ends seated on the box")
        expect(DoddyMotion.sit.figure.y + DoddyMotion.sit.figure.height == DoddyMotion.idle.figure.y + DoddyMotion.idle.figure.height,
               "sit and idle stand on the same floor")
        expect(DoddyMotion.idle.frame(at: -1) == 1, "a time before zero")
        expect(DoddyMotion.allCases.filter(\.loops) == [.walk, .run], "only walk and run loop")
        for m in DoddyMotion.allCases {
            let b = m.figure
            expect(b.x >= 0 && b.y >= 0 && b.x + b.width <= 1 && b.y + b.height <= 1 && b.height > 0.5, "\(m) box")
            expect(m.duration < 3, "\(m) is short")
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
        // Whole Doddy reads lying on his front (ADR-299); other styles and older builds keep the board.
        func readPose(_ state: DoddyToolAttributes.ContentState, stale: Bool = false) -> IslandPose? {
            var s = state
            s.islandStyle = .wholeDoddy
            return read.islandScene(s, isStale: stale, now: now).pose
        }
        expect(readPose(.init(isPaused: false)) == .bellyReading, "whole doddy reads")
        expect(readPose(.init(isPaused: true)) == .crosslegged, "whole doddy paused")
        expect(readPose(.init(isPaused: false, isFinished: true)) == .fistpump, "whole doddy finished reading")
        expect(readPose(.init(isPaused: false), stale: true) == .facepalm, "whole doddy lost")
        expect(read.islandScene(.init(isPaused: false), isStale: false, now: now).pose == nil, "no style, no pose")
        var leanIn = DoddyToolAttributes.ContentState(isPaused: false)
        leanIn.islandStyle = .leanIn
        expect(read.islandScene(leanIn, isStale: false, now: now).pose == nil, "lean in keeps the board")
        // Focus dribbles and breathing balances (ADR-313); paused waits, done is the fist pump.
        let wholeFocus = { (s: DoddyToolAttributes.ContentState, stale: Bool) in
            var s = s
            s.islandStyle = .wholeDoddy
            return focus.islandScene(s, isStale: stale, now: now).pose
        }
        expect(wholeFocus(.init(isPaused: false, endsAt: end), false) == .basketballDribble, "focus dribbles")
        expect(wholeFocus(.init(isPaused: true, endsAt: nil, remaining: 300), false) == .crosslegged, "focus paused")
        expect(wholeFocus(.init(isPaused: false, endsAt: end), true) == .fistpump, "focus time up")
        var breathe = DoddyToolAttributes.ContentState(isPaused: false, endsAt: end)
        breathe.islandStyle = .wholeDoddy
        expect(breathing.islandScene(breathe, isStale: false, now: now).pose == .onelegBalance, "breathing balances")
        breathe.isFinished = true
        expect(breathing.islandScene(breathe, isStale: false, now: now).pose == .fistpump, "breathing done")
        expect(focus.islandScene(.init(isPaused: false, endsAt: end), isStale: false, now: now).pose == nil,
               "focus without a style keeps its board")
        expect(focus.islandScene(.init(isPaused: false, endsAt: end), isStale: false, now: now).board == .tinyPromise,
               "focus board unchanged")
        // Content from an older build (no style) still decodes.
        let old = Data(#"{"isPaused":false,"remaining":0,"isFinished":false}"#.utf8)
        let decoded = try? JSONDecoder().decode(DoddyToolAttributes.ContentState.self, from: old)
        expect(decoded != nil && decoded?.islandStyle == nil, "older content decodes")
        expect(DoddyToolAttributes.clock(3725) == "1:02:05" && DoddyToolAttributes.clock(59.2) == "1:00", "clock")
        return failures
    }
}

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
        failures += tools()
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

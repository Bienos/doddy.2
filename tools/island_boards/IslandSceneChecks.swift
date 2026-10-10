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
        return failures
    }
}

import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// The call rehearsal streams the microphone to OpenAI, so it needs that provider's voice consent
/// before it claims the audio session, asks for the microphone or fetches a token (7 Nov 2026
/// engineering audit). App-target test: hosted Mac job only.
final class CallRehearsalSessionTests: XCTestCase {
    @MainActor
    func testWithoutTheOpenAIConsentNothingStarts() async throws {
        let key = VoiceProviderConsent.key(for: CallRehearsal.provider)
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let preview = try JSONDecoder().decode(CallPreview.self, from: Data(Self.previewJSON.utf8))
        let session = CallRehearsalSession()
        await session.start(preview: preview)

        XCTAssertEqual(session.state, .needsConsent, "the screen shows the consent step instead of connecting")
        XCTAssertFalse(session.isRunning)
        XCTAssertTrue(session.lines.isEmpty)
        XCTAssertFalse(AudioSessionOwner.shared.microphoneInUse)
    }

    func testTheRehearsalAsksForTheOpenAIConsentNotTheChosenVoices() {
        // Whatever voice the user picked for conversations, the rehearsal runs on OpenAI.
        XCTAssertEqual(CallRehearsal.provider, .openAIRealtime)
        XCTAssertEqual(VoiceProviderConsent.key(for: CallRehearsal.provider), "voice.providerConsent.openai.v1")
    }

    /// The same card as `CallCaseTests.previewJSON` in DoddyCore.
    static let previewJSON = """
    {"caseId":"3ff77017-4163-417c-ae47-958d3dfdf213","digest":"\(String(repeating: "a", count: 64))","approvableUntil":"2026-10-19T09:30:00.000Z",
     "callee":{"name":"Serwis Laptop","phone":"22 123 45 67","destinationKind":"geographic","source":"contacts","sourceLabel":"Serwis"},
     "principal":{"name":"Anna","genitive":"Anny"},"goal":"Sprawdzić laptop.",
     "openingLine":"Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: Czy laptop jest gotowy?",
     "question":"Czy laptop jest gotowy?","facts":[{"kind":"reference","text":"Zlecenie 12345"}],
     "forbidden":["Nie płaci i nie podaje danych do płatności."],"callbackLine":"Sprawdzę to u Anny i oddzwonię.",
     "maxDurationSecs":240,"notice":"off","recordsAudio":false,"callableNow":true}
    """
}

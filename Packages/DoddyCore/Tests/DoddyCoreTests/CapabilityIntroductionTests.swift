import XCTest
@testable import DoddyCore

/// The onboarding "What I can do" paragraph must match the build it describes.
final class CapabilityIntroductionTests: XCTestCase {
    func testShippingBuildMentionsRemindersAndConfirmationNotTheOldDenial() {
        for serverConfigured in [true, false] {
            let text = CapabilityIntroduction.text(for: .shipping(serverConfigured: serverConfigured))
            XCTAssertTrue(text.hasPrefix("I'm a digital companion powered by AI, not a person."))
            XCTAssertTrue(text.contains("I can add a reminder"))
            XCTAssertTrue(text.contains("only after you confirm each one on screen"))
            // ADR-578: apps are allowed from the conversation, the first time one is needed.
            XCTAssertTrue(text.contains("I ask you on screen to allow it"))
            XCTAssertFalse(text.contains("Settings › Connections"))
            XCTAssertTrue(text.contains("ElevenLabs"))
            XCTAssertFalse(text.contains("can't add reminders"))
            XCTAssertFalse(text.contains("can't set reminders"))
        }
    }

    func testBuildWithoutRemindersOrVoiceSaysSo() {
        let text = CapabilityIntroduction.text(for: .m0)
        XCTAssertTrue(text.contains("I can't add reminders or use other apps in this build."))
        XCTAssertFalse(text.contains("ElevenLabs"))
        XCTAssertFalse(text.contains("I can add a reminder"))
    }

    func testAlwaysPointsToTheDataFlowScreen() {
        for catalog in [CapabilityCatalog.m0, .v1Voice, .shipping(serverConfigured: true)] {
            // The screen moved off Home's menu on 9 Nov 2026; the paragraph names where it is now.
            XCTAssertTrue(CapabilityIntroduction.text(for: catalog).hasSuffix("Settings › Privacy › What leaves this iPhone shows everything that is sent, and where."))
        }
    }

    func testPolishSaysTheSameThings() {
        let english = CapabilityIntroduction.text(for: .shipping(serverConfigured: true))
        let polish = CapabilityIntroduction.text(for: .shipping(serverConfigured: true), language: .polish)
        XCTAssertNotEqual(polish, english)
        XCTAssertTrue(polish.hasPrefix("Tu Doddy, cyfrowy towarzysz oparty na AI, nie człowiek."))
        XCTAssertTrue(polish.contains("ElevenLabs"))
        XCTAssertTrue(polish.contains("potwierdzasz na ekranie"))
        XCTAssertTrue(polish.hasSuffix("Ustawienia › Prywatność › Co opuszcza tego iPhone’a pokazuje wszystko, co jest wysyłane, i dokąd."))
        XCTAssertTrue(CapabilityIntroduction.text(for: .m0, language: .polish)
            .contains("W tej wersji nie mogę dodawać przypomnień ani korzystać z innych aplikacji."))
        XCTAssertFalse(CapabilityIntroduction.text(for: .m0, language: .polish).contains("ElevenLabs"))
    }

    /// Doddy is an AI character: the Polish never uses a gendered first-person form ("sam", "byłem", "byłam").
    func testPolishHasNoGenderedFirstPerson() {
        for catalog in [CapabilityCatalog.m0, .shipping(serverConfigured: true)] {
            let words = CapabilityIntroduction.text(for: catalog, language: .polish)
                .split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() }
            // Gendered forms Doddy could slip into here. A suffix rule would also catch the present tense
            // ("wysyłam"), so the forms are listed.
            let gendered: Set<String> = ["sam", "sama", "byłem", "byłam", "mogłem", "mogłam", "dodałem", "dodałam",
                                         "gotowy", "gotowa", "pewien", "pewna", "asystentem", "asystentką",
                                         "towarzyszem", "towarzyszką"]
            for word in words { XCTAssertFalse(gendered.contains(word), word) }
        }
    }
}

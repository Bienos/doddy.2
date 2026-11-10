import Foundation

/// The opening paragraph of "What I can do" (Home › ••• › What I can do). Built from the same catalog as the
/// rows under it (`WhatICanDo`), so it can't promise or deny something the build doesn't match. Doddy speaks
/// in the first person here; the Polish avoids gendered first-person verb forms (decision 2026-11-09-what-i-can-do).
public enum CapabilityIntroduction {
    public static func text(for catalog: CapabilityCatalog, language: NotificationLanguage = .english) -> String {
        let polish = language == .polish
        var sentences = polish
            ? ["Jestem AI, nie człowiekiem.", "Twoje notatki są przechowywane na tym iPhonie."]
            : ["I'm an AI assistant, not a person.", "Your notes are kept on this iPhone."]
        if isBuilt(.voiceInput, in: catalog) {
            sentences.append(polish
                ? "Kiedy rozmawiamy, Twój głos i notatki, z których korzystam, trafiają do ElevenLabs, który obsługuje rozmowę."
                : "When we talk, your voice and the notes I use go to ElevenLabs to run the conversation.")
        }
        if isBuilt(.reminders, in: catalog) {
            // ADR-578: the first time an app is needed, the conversation asks for it on screen.
            sentences.append(polish
                ? "Mogę dodać przypomnienie albo wydarzenie w kalendarzu i pomóc w kilku innych aplikacjach, ale każdą rzecz najpierw potwierdzasz na ekranie. Gdy pierwszy raz potrzebuję którejś z Twoich aplikacji, proszę Cię na ekranie o zgodę."
                : "I can add a reminder or a calendar event and help with a few other apps, but only after you confirm each one on screen. The first time I need one of your apps, I ask you on screen to allow it.")
            sentences.append(polish ? "Nigdy nie wysyłam wiadomości. To zawsze robisz Ty." : "I never send a message myself.")
        } else {
            sentences.append(polish
                ? "W tej wersji nie mogę dodawać przypomnień ani korzystać z innych aplikacji."
                : "I can't add reminders or use other apps in this build.")
        }
        // What is sent and where is the Privacy Policy's job (owner, 10 Nov 2026); the sheet links to it.
        sentences.append(polish
            ? "Co wysyłam i dokąd, opisuje Polityka prywatności."
            : "What I send, and where, is in the Privacy Policy.")
        return sentences.joined(separator: " ")
    }

    private static func isBuilt(_ capability: Capability, in catalog: CapabilityCatalog) -> Bool {
        if case .notImplemented = catalog.status(of: capability) { return false }
        return true
    }
}

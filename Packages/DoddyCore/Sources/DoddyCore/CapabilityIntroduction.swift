import Foundation

/// The opening paragraph of "What I can do" (onboarding). Built from the same catalog as the
/// "What's built" list under it, so it can't promise or deny something the build doesn't match.
public enum CapabilityIntroduction {
    public static func text(for catalog: CapabilityCatalog) -> String {
        var sentences = ["I'm an AI assistant, not a person.", "Your notes are kept on this iPhone."]
        if isBuilt(.voiceInput, in: catalog) {
            sentences.append("When we talk, your voice and the notes I use go to ElevenLabs to run the conversation.")
        }
        if isBuilt(.reminders, in: catalog) {
            sentences.append("I can add a reminder or a calendar event and help with a few other apps, but only after you confirm each one on screen, and only for the apps you turn on in Settings › Connections.")
            sentences.append("I never send a message myself.")
        } else {
            sentences.append("I can't add reminders or use other apps in this build.")
        }
        sentences.append("Settings › What leaves this iPhone shows everything that is sent, and where.")
        return sentences.joined(separator: " ")
    }

    private static func isBuilt(_ capability: Capability, in catalog: CapabilityCatalog) -> Bool {
        if case .notImplemented = catalog.status(of: capability) { return false }
        return true
    }
}

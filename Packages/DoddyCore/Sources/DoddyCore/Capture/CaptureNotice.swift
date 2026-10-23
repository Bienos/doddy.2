import Foundation

/// The notice shown once before Doddy records anything (ADR-579), and required before ANY start, so a
/// start from Siri, the Action Button or a control cannot be the first a person hears of it.
///
/// The wording is a draft for the owner and a lawyer to settle. It states facts about what Doddy does
/// and points at the user's own responsibility; it does not state what any country's law says,
/// because that was not checked.
public enum CaptureNotice {
    /// Raise when the wording changes in substance: everyone then reads it again.
    public static let version = 1
    public static let preferenceKey = "capture.noticeAcceptedVersion"

    public static func isAccepted(storedVersion: Int) -> Bool { storedVersion >= version }

    public static func title(_ language: NotificationLanguage) -> String {
        language == .polish ? "Zanim zaczniesz nagrywać" : "Before you record"
    }

    public static func points(_ language: NotificationLanguage) -> [String] {
        if language == .polish {
            return [
                "Doddy nagrywa tylko wtedy, gdy to uruchomisz, i zawsze to pokazuje: pomarańczowa kropka mikrofonu iOS oraz Aktywność na żywo są włączone przez cały czas nagrywania. Możesz je zatrzymać w każdej chwili.",
                "Prawo o nagrywaniu innych osób bywa różne w różnych krajach i sytuacjach. To Ty odpowiadasz za to, żeby wolno Ci było nagrywać, i za poinformowanie osób, które nagrywasz.",
                "Dźwięk i jego zapis słowny zostają na tym iPhonie. Doddy nigdzie ich nie wysyła.",
                "Nagranie nie staje się wspomnieniem Doddy’ego samo. Zapamiętuje tylko to, co sam wskażesz i zapiszesz.",
            ]
        }
        return [
            "Doddy records only when you start it, and always shows it: iOS's orange microphone dot and the Live Activity stay on for as long as it records. You can stop it at any time.",
            "The law on recording other people differs between countries and situations. It is up to you to make sure you may record, and to tell the people you record.",
            "The audio and its written-out words stay on this iPhone. Doddy doesn't send them anywhere.",
            "A recording does not become something Doddy remembers by itself. He remembers only what you pick and save.",
        ]
    }

    public static func accept(_ language: NotificationLanguage) -> String {
        language == .polish ? "Rozumiem, nagrywaj" : "I understand, record"
    }

    public static func decline(_ language: NotificationLanguage) -> String {
        language == .polish ? "Nie teraz" : "Not now"
    }
}

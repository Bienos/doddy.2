import Foundation

/// The App Group folder the Mac menu bar app shares with its desktop widget (ADR-439). Compiled
/// into both. The group's name is `DoddyMacAppGroup` in both Info.plists; a build signed without
/// the App Group gets no folder it can write, so the widget shows no count.
enum MacGroupFolder {
    static var url: URL? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DoddyMacAppGroup") as? String,
              !id.isEmpty, !id.hasPrefix(".") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

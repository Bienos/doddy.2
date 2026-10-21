import Foundation

// Photos and Camera (ADR-568, owner 21 Oct: "both", after Doddy offered Photos or Camera next).
// This replaces ADR-218's "never the camera or the whole photo library" and ADR-224's "no camera
// capture" for these two features only:
//
// - find_photos: "How many photos did I take on Saturday?" Doddy counts the photos and videos in
//   the user's library for a day or a span of at most 31 days, after the user's yes (ASK-01). The
//   pictures show on the user's screen only; the agent hears the counts and the first and last
//   times, never what is in them, and nothing leaves the iPhone otherwise.
// - open_camera: "Take a photo." A card first; on the tap Doddy's camera opens, and a photo the
//   user keeps goes into a new note that they check and save themselves, like a picked photo
//   (ADR-218's reading and storage rules). Doddy never saves to the photo library.

extension VoiceToolName {
    public static let findPhotos = "find_photos"
    public static let openCamera = "open_camera"
}

/// Whole days to look through: from the start of `firstDay`, `days` long.
public struct PhotoSearchRequest: Equatable, Sendable {
    public let firstDay: Date
    public let days: Int

    /// At most a month at a time.
    public static let maxDays = 31

    public init?(firstDay: Date, days: Int) {
        guard (1...Self.maxDays).contains(days) else { return nil }
        self.firstDay = firstDay
        self.days = days
    }

    /// From midnight of the first day to midnight after the last (or now, for a span ending today).
    public func range(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: firstDay)
        let after = calendar.date(byAdding: .day, value: days, to: start) ?? now
        return (start, min(after, max(now, start)))
    }

    /// "2026-10-18", or "2026-10-12 to 2026-10-18".
    public func text(calendar: Calendar) -> String {
        let first = VoiceToolReply.localText(firstDay, hasTime: false, calendar: calendar)
        guard days > 1, let last = calendar.date(byAdding: .day, value: days - 1, to: firstDay) else { return first }
        return "\(first) to \(VoiceToolReply.localText(last, hasTime: false, calendar: calendar))"
    }
}

/// What the app found. Counts and times only: what is in the pictures never leaves the screen.
public struct PhotoSearchSummary: Equatable, Sendable {
    public let photos: Int
    public let videos: Int
    public let first: Date?
    public let last: Date?
    /// The user let Doddy see only the photos they picked (iOS's limited access).
    public let limited: Bool

    public init(photos: Int, videos: Int, first: Date?, last: Date?, limited: Bool) {
        self.photos = photos
        self.videos = videos
        self.first = first
        self.last = last
        self.limited = limited
    }
}

extension VoiceToolRequest {
    /// `day` ("today", "yesterday" or YYYY-MM-DD), or `from` and `to` (YYYY-MM-DD, both included).
    static func parsePhotoSearch(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        let today = calendar.startOfDay(for: now)
        func date(_ text: String) -> Date? {
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "today": return today
            case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
            default:
                let parts = text.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 3 else { return nil }
                return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            }
        }
        let first: Date, last: Date
        if let from = args.text("from") {
            guard let start = date(from), let end = date(args.text("to") ?? from) else {
                return .invalid(name: name, reason: "from and to must be dates written YYYY-MM-DD")
            }
            (first, last) = (start, end)
        } else {
            guard let day = date(args.text("day") ?? "today") else {
                return .invalid(name: name, reason: "day must be today, yesterday or a date written YYYY-MM-DD")
            }
            (first, last) = (day, day)
        }
        guard first <= last else { return .invalid(name: name, reason: "from must not be after to") }
        guard last <= today else { return .invalid(name: name, reason: "a day in the future has no photos") }
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        guard let request = PhotoSearchRequest(firstDay: first, days: days) else {
            return .invalid(name: name, reason: "at most \(PhotoSearchRequest.maxDays) days at a time")
        }
        return .findPhotos(request)
    }
}

extension VoiceToolReply {
    /// The counts and times, never what the pictures show (they are on the user's screen only).
    public static func photosFound(_ summary: PhotoSearchSummary, request: PhotoSearchRequest, calendar: Calendar) -> String {
        let span = request.text(calendar: calendar)
        var lines: [String]
        if summary.photos == 0 && summary.videos == 0 {
            lines = ["No photos or videos in the user's photo library for \(span). Say so; do not guess."]
        } else {
            lines = ["Found \(summary.photos) photo\(summary.photos == 1 ? "" : "s") and \(summary.videos) video\(summary.videos == 1 ? "" : "s") in the user's photo library for \(span)."]
            if let first = summary.first, let last = summary.last {
                lines.append("The first was taken \(localText(first, hasTime: true, calendar: calendar)), the last \(localText(last, hasTime: true, calendar: calendar)).")
            }
            lines.append("They are on the user's screen. You can't see them: never describe what is in them, only the counts and times.")
        }
        if summary.limited {
            lines.append("The user let Doddy see only some of their photos, so there may be more.")
        }
        return lines.joined(separator: "\n")
    }

    public static let cameraOpened = "opened: Doddy's camera is open on the user's screen. A photo they keep goes into a new note that they check and save themselves. Never say a photo was taken or saved."
    public static let cameraDeclined = "declined: the user chose not to open the camera. Nothing was opened."
    public static let cameraUnavailable = "unavailable: this device has no camera Doddy can use. Nothing was opened. Tell the user in one short sentence."
}

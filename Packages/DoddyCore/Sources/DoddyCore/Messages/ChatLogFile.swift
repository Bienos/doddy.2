import Foundation

/// The Messages thread on disk (ADR-582): one JSON file. A write is only reported as kept when
/// the file was read back and holds what was written (constitution: never claim saved without a
/// verified storage operation). The thread keeps the newest `limit` messages; older ones are
/// dropped when a new one is added, and the user can delete the whole thread.
public struct ChatLogFile: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// The file couldn't be written, or what was read back is not what was written.
        case notKept
        case unreadable
    }

    public static let defaultLimit = 500

    public let url: URL
    public let limit: Int

    public init(url: URL, limit: Int = ChatLogFile.defaultLimit) {
        self.url = url
        self.limit = limit
    }

    /// The thread, oldest first. A missing file is an empty thread; a file that can't be read is
    /// an error, never an empty thread (it would be overwritten by the next message).
    public func load() throws -> [ChatMessage] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        guard let messages = try? Self.decoder.decode([ChatMessage].self, from: data) else { throw Failure.unreadable }
        return messages
    }

    /// The thread with `message` added (and the oldest dropped past the limit), written and read
    /// back. Returns what is now kept, or throws and leaves the file as it was.
    @discardableResult
    public func append(_ message: ChatMessage) throws -> [ChatMessage] {
        var messages = try load()
        guard !messages.contains(where: { $0.id == message.id }) else { return messages }
        messages.append(message)
        if messages.count > limit { messages.removeFirst(messages.count - limit) }
        try write(messages)
        return messages
    }

    /// Deletes the thread. Checked: the file is gone afterwards.
    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch { throw Failure.notKept }
        }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.notKept }
    }

    private func write(_ messages: [ChatMessage]) throws {
        let data: Data
        do { data = try Self.encoder.encode(messages) } catch { throw Failure.notKept }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw Failure.notKept
        }
        guard let back = try? Self.decoder.decode([ChatMessage].self, from: Data(contentsOf: url)),
              back == messages else { throw Failure.notKept }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension Array where Element == ChatMessage {
    /// Messages from Doddy after `date`: what the user hasn't seen. Nil `date` means never opened.
    func unreadCount(since date: Date?) -> Int {
        filter { message in message.sender == .doddy && (date.map { message.sentAt > $0 } ?? true) }.count
    }
}

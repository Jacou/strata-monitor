import Foundation
import Observation

/// Conversations in `Application Support/StrataMonitor/chat.json`, newest last, the last 20 kept.
///
/// A file we cannot read is an empty chat history, never a crash — the same rule the rest of the
/// app follows for data it does not control.
@Observable @MainActor
public final class ChatStore {
    nonisolated public static let maxConversations = 20

    public private(set) var conversations: [ChatConversation]
    /// Set when a read or write fails, so the screen can say so instead of losing work quietly.
    public private(set) var lastError: String?

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        let url = fileURL ?? Self.defaultFileURL()
        self.fileURL = url
        self.conversations = Self.read(url)
    }

    public var mostRecent: ChatConversation? { conversations.last }

    public func conversation(_ id: UUID) -> ChatConversation? {
        conversations.first { $0.id == id }
    }

    /// Insert or replace, then keep only the 20 newest.
    public func save(_ conversation: ChatConversation) {
        var updated = conversation
        updated.updatedAt = .now

        var all = conversations
        if let index = all.firstIndex(where: { $0.id == updated.id }) {
            all[index] = updated
        } else {
            all.append(updated)
        }
        all.sort { $0.updatedAt < $1.updatedAt }
        if all.count > Self.maxConversations {
            all.removeFirst(all.count - Self.maxConversations)
        }

        conversations = all
        write(all)
    }

    public func delete(_ id: UUID) {
        let all = conversations.filter { $0.id != id }
        conversations = all
        write(all)
    }

    public func clearAll() {
        conversations = []
        write([])
    }

    // MARK: - file

    nonisolated public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("StrataMonitor", isDirectory: true)
            .appendingPathComponent("chat.json")
    }

    private nonisolated static func read(_ url: URL) -> [ChatConversation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let decoded = Self.decodeConversations(data) else { return [] }
        return decoded.sorted { $0.updatedAt < $1.updatedAt }.suffix(Self.maxConversations).map { $0 }
    }

    private func write(_ conversations: [ChatConversation]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(Self.dateString(from: date))
            }
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(conversations).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Dates are written ISO 8601, so a file survives a restart of the app.
    /// One unreadable conversation is dropped rather than losing the rest.
    nonisolated public static func decodeConversations(_ data: Data) -> [ChatConversation]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = Self.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date: \(text)")
            }
            return date
        }
        if let all = try? decoder.decode([ChatConversation].self, from: data) { return all }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        var kept: [ChatConversation] = []
        for element in raw {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let conversation = try? decoder.decode(ChatConversation.self, from: elementData)
            else { continue }
            kept.append(conversation)
        }
        return kept
    }

    private nonisolated static func dateString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Fractional seconds if the file has them, plain seconds if it does not — a hand-edited
    /// file still reads.
    private nonisolated static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

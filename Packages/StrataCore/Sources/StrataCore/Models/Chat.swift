import Foundation

/// Who wrote a message. `system` is never shown in the list — it is only sent.
public enum ChatRole: String, Codable, Sendable, Equatable, CaseIterable {
    case system
    case user
    case assistant
}

/// One message in a conversation.
///
/// `reasoning`, `thinkSecs`, `meta`, `error` and `stopped` are what the stream left behind, so a
/// conversation reloaded after a restart reads exactly as it did while it streamed.
public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var role: ChatRole
    /// The answer (or the question).
    public var text: String
    /// `delta.reasoning_content`, kept apart from the answer so it can collapse.
    public var reasoning: String
    public var time: Date
    /// How long the model thought, in seconds — nil when it never thought.
    public var thinkSecs: Double?
    /// "128 tokens · 41.2 tok/s", the web page's meta line.
    public var meta: String?
    /// A failure the engine reported, shown in the bubble instead of an answer.
    public var error: String?
    public var stopped: Bool

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String = "",
        reasoning: String = "",
        time: Date = .now,
        thinkSecs: Double? = nil,
        meta: String? = nil,
        error: String? = nil,
        stopped: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.time = time
        self.thinkSecs = thinkSecs
        self.meta = meta
        self.error = error
        self.stopped = stopped
    }

    public var hasReasoning: Bool { !reasoning.isEmpty }
    public var hasAnswer: Bool { !text.isEmpty }
    public var isUser: Bool { role == .user }

    /// Nothing to draw: an assistant turn that produced neither an answer nor a thought.
    public var isEmpty: Bool { text.isEmpty && reasoning.isEmpty && error == nil }
}

/// A conversation, as it is written to Application Support.
public struct ChatConversation: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [ChatMessage]

    public init(id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date = .now, messages: [ChatMessage] = []) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// The label in the "Chats" list: the first question, cut to one line.
    public var title: String {
        guard let question = messages.first(where: { $0.role == .user && !$0.text.isEmpty })?.text else {
            return "New chat"
        }
        let line = question.split(separator: "\n").first.map(String.init) ?? question
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    public var isEmpty: Bool { messages.isEmpty }

    /// The turns the API needs: no system row, no failed assistant turn, no empty answer —
    /// `apiMessages()` in docs/reference-app.js.
    public var history: [ChatAPIMessage] {
        Self.history(messages: messages)
    }

    public static func history(messages: [ChatMessage]) -> [ChatAPIMessage] {
        var out: [ChatAPIMessage] = []
        for message in messages {
            switch message.role {
            case .system: break                       // the system prompt is added by the request builder
            case .user: out.append(ChatAPIMessage(role: .user, content: message.text))
            case .assistant:
                // A turn that only errored never goes back to the model.
                if message.error == nil, !message.text.isEmpty {
                    out.append(ChatAPIMessage(role: .assistant, content: message.text))
                }
            }
        }
        return out
    }
}

/// One `{role, content}` pair in the request body. v1 is text only — no image parts.
public struct ChatAPIMessage: Codable, Sendable, Equatable {
    public var role: ChatRole
    public var content: String

    public init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
    }
}

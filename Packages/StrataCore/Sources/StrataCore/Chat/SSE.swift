import Foundation

// The SSE side of `POST /v1/chat/completions`, line by line, exactly as the web page reads it
// (docs/reference-app.js ~line 800): keep only `data:` lines, ignore `: keep-alive` comments
// while a long prompt is being read, stop at `[DONE]`, and never let a junk line kill the stream.

/// One wire line.
public enum SSELine: Sendable, Equatable {
    /// A `data:` payload worth parsing.
    case data(String)
    /// `data: [DONE]` — the stream is over.
    case done
    /// A comment, a blank line, an `event:`/`id:` line, or an empty payload.
    case ignore
}

public enum SSEParser {
    public static func parse(_ line: String) -> SSELine {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return .ignore }
        if payload == "[DONE]" { return .done }
        return .data(payload)
    }
}

/// One `data:` object. Every field is optional: servers differ, and most chunks carry only a delta.
public struct ChatChunk: Decodable, Sendable, Equatable {
    public struct Delta: Codable, Sendable, Equatable {
        public var content: String?
        public var reasoningContent: String?

        public init(content: String? = nil, reasoningContent: String? = nil) {
            self.content = content
            self.reasoningContent = reasoningContent
        }

        public var isEmpty: Bool { content == nil && reasoningContent == nil }

        private enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }

    public struct Usage: Codable, Sendable, Equatable {
        public var completionTokens: Int?
        public var promptTokens: Int?
        public var totalTokens: Int?

        public init(completionTokens: Int? = nil, promptTokens: Int? = nil, totalTokens: Int? = nil) {
            self.completionTokens = completionTokens
            self.promptTokens = promptTokens
            self.totalTokens = totalTokens
        }

        private enum CodingKeys: String, CodingKey {
            case completionTokens = "completion_tokens"
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }

    public var delta: Delta?
    public var usage: Usage?
    /// `j.error` mid-stream: the engine's own words.
    public var errorMessage: String?

    public init(delta: Delta? = nil, usage: Usage? = nil, errorMessage: String? = nil) {
        self.delta = delta
        self.usage = usage
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let choices = c.decodeArray(DeltaCarrier.self, forKey: .choices) {
            delta = choices.first?.delta
        }
        usage = try? c.decode(Usage.self, forKey: .usage)

        // `{"error": {"message": "…"}}`, or the short `{"error": "…"}` an older server sends.
        if let nested = try? c.decode(ServerErrorPayload.self, forKey: .error) {
            errorMessage = nested.message
        } else if let plain = c.decodeString(forKey: .error) {
            errorMessage = plain
        }
    }

    private enum CodingKeys: String, CodingKey {
        case choices, usage, error
    }

    /// Only `choices[0].delta` matters here; `finish_reason` and the rest are ignored.
    private struct DeltaCarrier: Decodable {
        var delta: Delta?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            delta = try? c.decode(Delta.self, forKey: .delta)
        }

        private enum CodingKeys: String, CodingKey {
            case delta
        }
    }

    private struct ServerErrorPayload: Decodable {
        var message: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = c.decodeString(forKey: .message)
        }

        private enum CodingKeys: String, CodingKey {
            case message
        }
    }

    public static func decode(_ payload: String) -> ChatChunk? {
        try? JSONDecoder().decode(ChatChunk.self, from: Data(payload.utf8))
    }

    /// What one chunk means for the answer, in the order the web page applies it.
    public var events: [ChatEvent] {
        var out: [ChatEvent] = []
        if let errorMessage { out.append(.error(errorMessage)) }
        if let usage { out.append(.usage(usage)) }
        if let reasoning = delta?.reasoningContent, !reasoning.isEmpty { out.append(.reasoning(reasoning)) }
        if let content = delta?.content, !content.isEmpty { out.append(.content(content)) }
        return out
    }
}

/// What the stream hands the chat screen.
public enum ChatEvent: Sendable, Equatable {
    case reasoning(String)
    case content(String)
    case usage(ChatChunk.Usage)
    /// A `j.error` in the middle of the stream.
    case error(String)
}

extension ChatEvent {
    /// The web page's fallback when the engine reports an error without saying why.
    public static let engineErrorMessage = "the engine reported an error"
}

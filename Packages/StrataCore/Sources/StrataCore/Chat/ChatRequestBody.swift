import Foundation

/// The body of `POST /v1/chat/completions`, built the way `send()` builds it
/// (docs/reference-app.js ~line 778): which fields are present is the behaviour, not a detail.
public struct ChatRequestBody: Codable, Sendable, Equatable {
    /// `health.model`, or "strata" — the web page's own placeholder — when /health has not answered.
    public static let fallbackModel = "strata"

    public var model: String
    public var messages: [ChatAPIMessage]
    public var stream: Bool
    public var reasoningEffort: ReasoningEffort
    public var temperature: Double
    /// Absent when temperature is 0: greedy ignores them.
    public var topP: Double?
    public var topK: Int?
    public var maxTokens: Int?
    public var seed: Int?

    public init(
        model: String,
        messages: [ChatAPIMessage],
        stream: Bool = true,
        reasoningEffort: ReasoningEffort = .high,
        temperature: Double = 0.6,
        topP: Double? = nil,
        topK: Int? = nil,
        maxTokens: Int? = nil,
        seed: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.seed = seed
    }

    /// The whole request from the conversation and the settings.
    public static func build(
        model: String?,
        messages: [ChatMessage],
        settings: ChatSamplingSettings
    ) -> ChatRequestBody {
        var history = ChatConversation.history(messages: messages)
        let prompt = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            history.insert(ChatAPIMessage(role: .system, content: prompt), at: 0)
        }

        var body = ChatRequestBody(
            model: model?.isEmpty == false ? model! : fallbackModel,
            messages: history,
            reasoningEffort: settings.effort,
            temperature: settings.temperature
        )

        // temperature > 0 sends the sampling trio; 0 sends only `temperature: 0`.
        if settings.temperature > 0 {
            body.topP = settings.topP
            body.topK = settings.topK
        }

        // `if (settings.seed)` / `if (settings.max)`: an empty field sends nothing, and 0 reads
        // as empty in the web page's inputs, so it is not sent either.
        if let seed = settings.seed, seed != 0 { body.seed = seed }
        if let maxTokens = settings.maxTokens, maxTokens != 0 { body.maxTokens = maxTokens }

        return body
    }

    /// The JSON exactly as the web page sends it: no `top_p` / `top_k` / `seed` / `max_tokens`
    /// key when that field is not set.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encode(reasoningEffort.wireValue, forKey: .reasoningEffort)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(seed, forKey: .seed)
    }

    public static func decode(_ data: Data) -> ChatRequestBody? {
        try? JSONDecoder().decode(ChatRequestBody.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, seed
        case reasoningEffort = "reasoning_effort"
        case topP = "top_p"
        case topK = "top_k"
        case maxTokens = "max_tokens"
    }
}

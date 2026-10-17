import Foundation
import Observation

/// The chat screen's model: the conversation on screen, the stream being written into it, and the
/// timings the meta line needs. Mirrors `send()` in docs/reference-app.js (~line 760).
@Observable @MainActor
public final class ChatViewModel {
    public private(set) var conversation: ChatConversation
    public var draft = "" {
        didSet { lastError = nil }
    }

    public private(set) var isStreaming = false
    /// The assistant message the stream is writing into — the one that shows the cursor.
    public private(set) var streamingMessageID: UUID?
    /// A problem with the screen itself (no server address), not with one answer.
    public private(set) var lastError: String?

    public let settings: ChatSettings
    private let store: ChatStore

    private var streamTask: Task<Void, Never>?
    // Stream state lives on the model, not in captured locals: the read loop runs in its own task.
    private var firstTokenAt: TimeInterval?
    private var thinkStart: TimeInterval?
    private var usage: ChatChunk.Usage?
    private var streamStopped = false
    private var streamErrorMessage: String?

    public init(store: ChatStore, settings: ChatSettings) {
        self.store = store
        self.settings = settings
        self.conversation = store.mostRecent ?? ChatConversation()
    }

    // MARK: - what the screen draws

    public var messages: [ChatMessage] { conversation.messages }
    public var conversations: [ChatConversation] { store.conversations }
    public var isEmpty: Bool { conversation.messages.isEmpty }
    public var canSend: Bool { !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var canStop: Bool { isStreaming }

    public var streamingMessage: ChatMessage? {
        guard let id = streamingMessageID else { return nil }
        return conversation.messages.first { $0.id == id }
    }

    /// True while the model is thinking and has not started answering.
    public var isThinking: Bool {
        guard let message = streamingMessage else { return false }
        return message.text.isEmpty && message.hasReasoning
    }

    // MARK: - sending

    /// Ask, then stream the answer into the conversation. `model` is `/health`'s model name.
    public func send(client: StrataClient, model: String?) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        draft = ""
        lastError = nil
        resetStreamState()

        conversation.messages.append(ChatMessage(role: .user, text: text))
        let assistant = ChatMessage(role: .assistant)
        conversation.messages.append(assistant)
        isStreaming = true
        streamingMessageID = assistant.id

        let body = ChatRequestBody.build(
            model: model,
            messages: conversation.messages,
            settings: settings.sampling
        )
        await readStream(client: client, body: body, assistantID: assistant.id)
        finish(assistantID: assistant.id)
    }

    /// Stop cancels the request; the answer keeps what it got and says so.
    public func stop() {
        streamTask?.cancel()
    }

    private func resetStreamState() {
        firstTokenAt = nil
        thinkStart = nil
        usage = nil
        streamStopped = false
        streamErrorMessage = nil
    }

    private func readStream(client: StrataClient, body: ChatRequestBody, assistantID: UUID) async {
        let task = Task {
            do {
                for try await event in try await client.chatStream(body) {
                    if Task.isCancelled { break }
                    apply(event, to: assistantID)
                }
            } catch is CancellationError {
                streamStopped = true
            } catch let error as StrataError {
                streamErrorMessage = Self.message(for: error)
            } catch {
                streamErrorMessage = Self.message(for: error)
            }
            if Task.isCancelled { streamStopped = true }
        }
        streamTask = task
        await task.value
        streamTask = nil
    }

    private func apply(_ event: ChatEvent, to id: UUID) {
        let now = Self.monotonicNow()
        switch event {
        case .reasoning(let piece):
            if firstTokenAt == nil { firstTokenAt = now }
            if thinkStart == nil { thinkStart = now }
            mutate(id) { $0.reasoning += piece }
        case .content(let piece):
            if firstTokenAt == nil { firstTokenAt = now }
            if let thinkStart {
                mutate(id) { $0.thinkSecs = $0.thinkSecs ?? (now - thinkStart) }
            }
            mutate(id) { $0.text += piece }
        case .usage(let value):
            usage = value
        case .error(let message):
            // The web page throws out of the read loop here; the answer keeps what it already got.
            streamErrorMessage = message.isEmpty ? ChatEvent.engineErrorMessage : message
        }
    }

    /// The web page's `thinkSecs` / `meta`, computed once the stream is over.
    private func finish(assistantID: UUID) {
        let now = Self.monotonicNow()
        mutate(assistantID) { message in
            if let thinkStart, message.thinkSecs == nil {
                message.thinkSecs = now - thinkStart
            }
            message.meta = ChatMeta.line(
                tokens: usage?.completionTokens,
                firstTokenAt: firstTokenAt,
                endedAt: now,
                stopped: streamStopped
            )
            message.stopped = streamStopped
            message.error = streamErrorMessage
        }

        isStreaming = false
        streamingMessageID = nil
        store.save(conversation)
    }

    private func mutate(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&conversation.messages[index])
    }

    // MARK: - conversations

    /// "New chat": the current one is kept (unless it is empty), and a blank one opens.
    public func newChat() {
        guard !isStreaming else { return }
        if !conversation.isEmpty { store.save(conversation) }
        conversation = ChatConversation()
    }

    public func open(_ id: UUID) {
        guard !isStreaming, let saved = store.conversation(id) else { return }
        if !conversation.isEmpty { store.save(conversation) }
        conversation = saved
    }

    public func delete(_ id: UUID) {
        guard !isStreaming else { return }
        store.delete(id)
        if conversation.id == id { conversation = store.mostRecent ?? ChatConversation() }
    }

    /// Wipes the stored history and the screen.
    public func deleteAll() {
        guard !isStreaming else { return }
        store.clearAll()
        conversation = ChatConversation()
    }

    // MARK: - words

    /// Plain words for what went wrong, like the web page's toast: it shows the server's own
    /// message when there is one.
    public static func message(for error: any Error) -> String {
        if error is CancellationError { return "Stopped" }
        if let server = error as? StrataServerError { return server.message }
        if let strata = error as? StrataError {
            switch strata {
            case .unauthorized: return "This server needs an API key: add it under Settings."
            case .unreachable: return "The server did not answer."
            case .http(let status): return "HTTP \(status)"
            case .decoding(let detail): return "The server's reply did not read as JSON. \(detail)"
            }
        }
        return error.localizedDescription
    }

    /// `performance.now()`: monotonic, so a clock change cannot distort tok/s.
    public static func monotonicNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

import XCTest
@testable import StrataCore

/// The chat screen's model, driven by a canned stream: what lands in the conversation, and what
/// the bubble says when the stream stops, fails, or is cancelled.
@MainActor
final class ChatViewModelTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.10:8081")!

    /// A scratch chat file per model, in the system temp directory.
    private func file() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("chat.json")
    }

    private func makeModel(_ transport: StubChatTransport) -> ChatViewModel {
        ChatViewModel(store: ChatStore(fileURL: file()), settings: ChatSettings(defaults: suite()))
    }

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "ChatViewModelTests-\(UUID().uuidString)")!
    }

    private func client(_ transport: StubChatTransport) -> StrataClient {
        StrataClient(baseURL: base, apiKey: "k", transport: StubTransport.responding("{}"), streamTransport: transport)
    }

    private func settle(_ seconds: TimeInterval = 0.05) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func waitUntil(_ body: () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if body() { return true }
            await settle(0.01)
        }
        return body()
    }

    private let answerLines = [
        ": keep-alive",
        #"data: {"choices":[{"delta":{"reasoning_content":"Let me think about that."}}]}"#,
        #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#,
        #"data: {"choices":[{"delta":{"content":" there."}}]}"#,
        #"data: {"choices":[],"usage":{"completion_tokens":14,"prompt_tokens":6,"total_tokens":20}}"#,
        "data: [DONE]",
    ]

    // MARK: - an exchange

    func testSendStreamsTheAnswerIntoTheConversation() async throws {
        let transport = StubChatTransport.sse(answerLines)
        let model = makeModel(transport)
        model.draft = "  Hi  "

        await model.send(client: client(transport), model: "qwen3.8-flash")

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages[0].role, .user)
        XCTAssertEqual(model.messages[0].text, "Hi", "the draft is trimmed before it is sent")
        XCTAssertEqual(model.draft, "", "the composer empties as the question goes out")

        let answer = model.messages[1]
        XCTAssertEqual(answer.role, .assistant)
        XCTAssertEqual(answer.text, "Hello there.")
        XCTAssertEqual(answer.reasoning, "Let me think about that.")
        XCTAssertNotNil(answer.thinkSecs)
        XCTAssertEqual(answer.meta, "14 tokens")   // the fake stream is far under 0.25 s
        XCTAssertNil(answer.error)
        XCTAssertFalse(answer.stopped)

        XCTAssertFalse(model.isStreaming)
        XCTAssertNil(model.streamingMessageID)
    }

    func testTheConversationIsPersisted() async throws {
        let transport = StubChatTransport.sse(answerLines)
        let url = file()
        let model = ChatViewModel(store: ChatStore(fileURL: url), settings: ChatSettings(defaults: suite()))

        model.draft = "Hi"
        await model.send(client: client(transport), model: "m")

        let reloaded = ChatStore(fileURL: url)
        XCTAssertEqual(reloaded.conversations.count, 1)
        XCTAssertEqual(reloaded.conversations.first?.messages.map(\.text), ["Hi", "Hello there."])
    }

    func testEmptyDraftSendsNothing() async throws {
        let transport = StubChatTransport.sse(answerLines)
        let model = makeModel(transport)
        model.draft = "   \n "

        await model.send(client: client(transport), model: "m")

        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(model.isStreaming)
    }

    func testTheRequestBodyCarriesTheHealthModelAndTheHistory() async throws {
        let transport = StubChatTransport.sse(answerLines)
        let model = makeModel(transport)
        model.settings.sampling.effort = .medium
        model.settings.sampling.maxTokens = 64

        model.draft = "one"
        await model.send(client: client(transport), model: "qwen3.8-flash-next")
        model.draft = "two"
        await model.send(client: client(transport), model: "qwen3.8-flash-next")

        XCTAssertEqual(transport.requests.count, 2)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: transport.requests[1].httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "qwen3.8-flash-next")
        XCTAssertEqual(body["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(body["max_tokens"] as? Int, 64)

        let messages = body["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual(messages.map { $0["content"] as? String }, ["one", "Hello there.", "two"])
    }

    func testNoModelFromHealthStillAsksForOne() async throws {
        let transport = StubChatTransport.sse(["data: [DONE]"])
        let model = makeModel(transport)
        model.draft = "hi"
        await model.send(client: client(transport), model: nil)

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: transport.requests[0].httpBody ?? Data()) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "strata")
    }

    // MARK: - while it streams

    func testThinkingIsSeparateFromTheAnswerWhileItStreams() async throws {
        let transport = StubChatTransport { request in
            ChatLineStream(
                response: httpResponse(request.url!, 200),
                lines: AsyncThrowingStream { continuation in
                    let task = Task {
                        continuation.yield(#"data: {"choices":[{"delta":{"reasoning_content":"thinking…"}}]}"#)
                        try await Task.sleep(nanoseconds: 40_000_000)
                        continuation.yield(#"data: {"choices":[{"delta":{"content":"answer"}}]}"#)
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            )
        }
        let model = makeModel(transport)
        model.draft = "hi"

        let send = Task { await model.send(client: client(transport), model: "m") }
        let sawThinking = await waitUntil { model.isThinking }
        XCTAssertTrue(sawThinking, "reasoning arrives before the answer")
        XCTAssertEqual(model.streamingMessage?.reasoning, "thinking…")
        XCTAssertEqual(model.streamingMessage?.text, "")

        await send.value
        XCTAssertFalse(model.isThinking)
        XCTAssertEqual(model.messages.last?.text, "answer")
    }

    // MARK: - stopping

    func testStopKeepsWhatArrivedAndSaysStopped() async throws {
        let transport = StubChatTransport.endless()
        let model = makeModel(transport)
        model.draft = "hi"

        let send = Task { await model.send(client: client(transport), model: "m") }
        let sawText = await waitUntil { model.messages.last?.text.isEmpty == false }
        XCTAssertTrue(sawText)

        model.stop()
        await send.value

        let answer = try XCTUnwrap(model.messages.last)
        XCTAssertTrue(answer.stopped)
        XCTAssertEqual(answer.meta, "Stopped", "no usage block, so only the mark")
        XCTAssertFalse(answer.text.isEmpty)
        XCTAssertNil(answer.error)
        XCTAssertFalse(model.isStreaming)
    }

    func testStopWhileIdleDoesNothing() {
        let model = makeModel(StubChatTransport.sse([]))
        model.stop()
        XCTAssertFalse(model.isStreaming)
    }

    // MARK: - failures

    func testErrorMidStreamGoesInTheBubble() async throws {
        let transport = StubChatTransport.sse([
            #"data: {"choices":[{"delta":{"content":"half an"}}]}"#,
            #"data: {"error":{"message":"the engine dropped the request"}}"#,
        ])
        let model = makeModel(transport)
        model.draft = "hi"

        await model.send(client: client(transport), model: "m")

        let answer = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(answer.text, "half an", "what already arrived stays")
        XCTAssertEqual(answer.error, "the engine dropped the request")
    }

    func testMissingAPIKeyIsSaidInPlainWords() async throws {
        let transport = StubChatTransport.failing(StrataError.unauthorized)
        let model = makeModel(transport)
        model.draft = "hi"

        await model.send(client: client(transport), model: "m")

        XCTAssertEqual(model.messages.last?.error, "This server needs an API key: add it under Settings.")
        XCTAssertFalse(model.isStreaming)
    }

    func testUnreachableServerAndRejectedBody() async throws {
        let unreachableTransport = StubChatTransport.failing(StrataError.unreachable)
        let unreachable = makeModel(unreachableTransport)
        unreachable.draft = "hi"
        await unreachable.send(client: unreachableTransport.client(), model: "m")
        XCTAssertEqual(unreachable.messages.last?.error, "The server did not answer.")

        let rejectedTransport = StubChatTransport.failing(StrataServerError(message: "max_tokens is too large", statusCode: 400))
        let rejected = makeModel(rejectedTransport)
        rejected.draft = "hi"
        await rejected.send(client: rejectedTransport.client(), model: "m")
        XCTAssertEqual(rejected.messages.last?.error, "max_tokens is too large", "the server's own words")
    }

    func testAFailedAnswerIsNotSentBackToTheServer() async throws {
        let transport = StubChatTransport.sse([#"data: {"error":{"message":"boom"}}"#])
        let model = makeModel(transport)
        model.draft = "first"
        await model.send(client: client(transport), model: "m")

        let again = StubChatTransport.sse(["data: [DONE]"])
        model.draft = "second"
        await model.send(client: client(again), model: "m")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: again.requests[0].httpBody ?? Data()) as? [String: Any])
        let messages = body["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "user"])
    }

    // MARK: - conversations

    func testNewChatKeepsTheOldOneAndOpensABlankOne() async throws {
        let transport = StubChatTransport.sse(answerLines)
        let store = ChatStore(fileURL: file())
        let model = ChatViewModel(store: store, settings: ChatSettings(defaults: suite()))

        model.draft = "first question"
        await model.send(client: client(transport), model: "m")

        model.newChat()
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(store.conversations.count, 1)

        model.draft = "second question"
        await model.send(client: client(transport), model: "m")
        XCTAssertEqual(store.conversations.count, 2)
        XCTAssertEqual(store.conversations.map(\.title), ["first question", "second question"])
    }

    func testNewChatOnAnEmptyConversationAddsNothing() {
        let model = makeModel(StubChatTransport.sse([]))
        model.newChat()
        model.newChat()
        XCTAssertTrue(model.conversations.isEmpty)
    }

    func testOpeningAndDeletingAConversation() async throws {
        let transport = StubChatTransport.sse(answerLines)
        let store = ChatStore(fileURL: file())
        let model = ChatViewModel(store: store, settings: ChatSettings(defaults: suite()))

        model.draft = "first"
        await model.send(client: client(transport), model: "m")
        let firstID = model.conversation.id

        model.newChat()
        model.draft = "second"
        await model.send(client: client(transport), model: "m")

        model.open(firstID)
        XCTAssertEqual(model.conversation.id, firstID)
        XCTAssertEqual(model.messages.first?.text, "first")

        model.delete(firstID)
        XCTAssertNil(model.conversation.messages.first(where: { $0.text == "first" }))
        XCTAssertEqual(store.conversations.count, 1)

        model.deleteAll()
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertTrue(model.isEmpty)
    }

    func testAStoredConversationIsWhereTheAppStarts() async throws {
        let url = file()
        let store = ChatStore(fileURL: url)
        store.save(ChatConversation(messages: [ChatMessage(role: .user, text: "kept")]))

        let model = ChatViewModel(store: store, settings: ChatSettings(defaults: suite()))
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.messages.first?.text, "kept")
    }
}

private extension StubChatTransport {
    func client() -> StrataClient {
        StrataClient(baseURL: URL(string: "http://192.168.1.10:8081")!, apiKey: "k",
                     transport: StubTransport.responding("{}"), streamTransport: self)
    }
}

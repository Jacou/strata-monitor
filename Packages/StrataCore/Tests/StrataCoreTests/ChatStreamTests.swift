import XCTest
@testable import StrataCore

/// The SSE half of the chat: line → event, mirroring the read loop in docs/reference-app.js.
final class ChatStreamTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.10:8081")!

    // MARK: - line parsing

    func testOnlyDataLinesCount() {
        XCTAssertEqual(SSEParser.parse(#"data: {"choices":[]}"#), .data(#"{"choices":[]}"#))
        XCTAssertEqual(SSEParser.parse("data:{\"choices\":[]}"), .data(#"{"choices":[]}"#))
        XCTAssertEqual(SSEParser.parse("data:  {\"a\":1}  "), .data(#"{"a":1}"#))
    }

    func testKeepAliveCommentsAndBlankLinesAreIgnored() {
        // What the server sends while a long prompt is being read.
        XCTAssertEqual(SSEParser.parse(": keep-alive"), .ignore)
        XCTAssertEqual(SSEParser.parse(":"), .ignore)
        XCTAssertEqual(SSEParser.parse(""), .ignore)
        XCTAssertEqual(SSEParser.parse("   "), .ignore)
        XCTAssertEqual(SSEParser.parse("event: message"), .ignore)
        XCTAssertEqual(SSEParser.parse("id: 4"), .ignore)
        XCTAssertEqual(SSEParser.parse("data:"), .ignore)
    }

    func testDoneEndsTheStream() {
        XCTAssertEqual(SSEParser.parse("data: [DONE]"), .done)
        XCTAssertEqual(SSEParser.parse("data:[DONE]"), .done)
    }

    // MARK: - chunk decoding

    func testContentDelta() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"choices":[{"delta":{"content":"Hello"}}]}"#))
        XCTAssertEqual(chunk.delta?.content, "Hello")
        XCTAssertNil(chunk.delta?.reasoningContent)
        XCTAssertEqual(chunk.events, [.content("Hello")])
    }

    func testReasoningDeltaIsItsOwnEvent() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"choices":[{"delta":{"reasoning_content":"hmm"}}]}"#))
        XCTAssertEqual(chunk.delta?.reasoningContent, "hmm")
        XCTAssertEqual(chunk.events, [.reasoning("hmm")])
    }

    func testReasoningAndContentInOneChunkKeepTheirOrder() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(
            #"{"choices":[{"delta":{"reasoning_content":"thought","content":"answer"}}]}"#
        ))
        XCTAssertEqual(chunk.events, [.reasoning("thought"), .content("answer")])
    }

    func testUsageChunk() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(
            #"{"choices":[],"usage":{"completion_tokens":128,"prompt_tokens":41,"total_tokens":169}}"#
        ))
        XCTAssertEqual(chunk.usage?.completionTokens, 128)
        XCTAssertEqual(chunk.usage?.promptTokens, 41)
        XCTAssertEqual(chunk.usage?.totalTokens, 169)
        XCTAssertEqual(chunk.events, [.usage(ChatChunk.Usage(completionTokens: 128, promptTokens: 41, totalTokens: 169))])
    }

    func testEmptyDeltasProduceNoEvents() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"choices":[{"delta":{"role":"assistant","content":""}}]}"#))
        XCTAssertTrue(chunk.events.isEmpty)
    }

    func testFinishReasonChunkCarriesNothing() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#))
        XCTAssertTrue(chunk.events.isEmpty)
    }

    func testErrorChunkIsAnEvent() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"error":{"message":"engine exploded","type":"server_error"}}"#))
        XCTAssertEqual(chunk.errorMessage, "engine exploded")
        XCTAssertEqual(chunk.events, [.error("engine exploded")])
    }

    func testErrorAsBareString() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"error":"nope"}"#))
        XCTAssertEqual(chunk.errorMessage, "nope")
    }

    func testErrorWithoutMessageStillReads() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"error":{"type":"server_error"}}"#))
        XCTAssertNil(chunk.errorMessage)
        XCTAssertTrue(chunk.events.isEmpty)
    }

    func testNullAndJunkFieldsDecode() throws {
        let chunk = try XCTUnwrap(ChatChunk.decode(#"{"choices":[{"delta":{"content":null,"reasoning_content":null}}],"usage":null}"#))
        XCTAssertTrue(chunk.events.isEmpty)
        XCTAssertNotNil(ChatChunk.decode("{}"))
        XCTAssertNotNil(ChatChunk.decode(#"{"id":"1","model":12,"created":"now"}"#))
        XCTAssertNil(ChatChunk.decode("not json at all"))
    }

    // MARK: - lines → events

    private func events(from lines: [String]) async throws -> [ChatEvent] {
        try await collect(StrataClient.eventStream(from: StubChatTransport.finished(lines)))
    }

    func testWholeStream() async throws {
        let got = try await events(from: [
            ": keep-alive",
            #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#,
            #"data: {"choices":[{"delta":{"reasoning_content":"Let me think."}}]}"#,
            #"data: {"choices":[{"delta":{"reasoning_content":" about it."}}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" there"}}]}"#,
            #"data: {"choices":[],"usage":{"completion_tokens":12,"prompt_tokens":5,"total_tokens":17}}"#,
            "data: [DONE]",
            #"data: {"choices":[{"delta":{"content":"never delivered"}}]}"#,
        ])

        XCTAssertEqual(got, [
            .reasoning("Let me think."),
            .reasoning(" about it."),
            .content("Hello"),
            .content(" there"),
            .usage(ChatChunk.Usage(completionTokens: 12, promptTokens: 5, totalTokens: 17)),
        ])
    }

    func testJunkLineDoesNotKillTheStream() async throws {
        let got = try await events(from: [
            #"data: {"choices":[{"delta":{"content":"a"}}]}"#,
            "data: {{{ broken",
            #"data: {"choices":[{"delta":{"content":"b"}}]}"#,
        ])
        XCTAssertEqual(got, [.content("a"), .content("b")])
    }

    func testStreamEndsWithoutDone() async throws {
        let got = try await events(from: [#"data: {"choices":[{"delta":{"content":"tail"}}]}"#])
        XCTAssertEqual(got, [.content("tail")])
    }

    func testErrorMidStreamIsAnEventNotACrash() async throws {
        let got = try await events(from: [
            #"data: {"choices":[{"delta":{"content":"half"}}]}"#,
            #"data: {"error":{"message":"the engine reported an error"}}"#,
        ])
        XCTAssertEqual(got, [.content("half"), .error("the engine reported an error")])
    }

    // MARK: - the request the client builds

    func testChatRequestShape() async throws {
        let transport = StubChatTransport.sse(["data: [DONE]"])
        let client = StrataClient(baseURL: base, apiKey: "key", transport: StubTransport.responding("{}"), streamTransport: transport)

        _ = try await collect(await client.chatStream(
            ChatRequestBody.build(model: "strata-model", messages: [ChatMessage(role: .user, text: "hi")], settings: .defaults)
        ))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        // A chat request waits for prefill; the 5 s metrics timeout would cut it off.
        XCTAssertEqual(request.timeoutInterval, URLSessionChatStreamTransport.defaultTimeout)

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "strata-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testFailedRequestMapsToTheServersOwnWords() {
        // The status → error mapping `URLSessionChatStreamTransport` does before the first line.
        XCTAssertEqual(
            URLSessionChatStreamTransport.error(forStatus: 500, body: #"{"error":{"message":"no GPU"}}"#) as? StrataServerError,
            StrataServerError(message: "no GPU", statusCode: 500)
        )
        XCTAssertEqual(
            URLSessionChatStreamTransport.error(forStatus: 400, body: #"{"error":"bad request"}"#) as? StrataServerError,
            StrataServerError(message: "bad request", statusCode: 400)
        )
        XCTAssertEqual(URLSessionChatStreamTransport.error(forStatus: 401, body: "") as? StrataError, .unauthorized)
        XCTAssertEqual(URLSessionChatStreamTransport.error(forStatus: 503, body: "not json") as? StrataError, .http(503))
    }

    func testFailedRequestThrowsBeforeTheFirstToken() async throws {
        let client = StrataClient(
            baseURL: base,
            apiKey: "k",
            transport: StubTransport.responding("{}"),
            streamTransport: StubChatTransport.failing(StrataServerError(message: "no GPU", statusCode: 500))
        )

        do {
            _ = try await client.chatStream(ChatRequestBody(model: "m", messages: []))
            XCTFail("expected a failure")
        } catch let error as StrataServerError {
            XCTAssertEqual(error.message, "no GPU")
            XCTAssertEqual(error.statusCode, 500)
        }
    }

    func testUnauthorizedChatRequest() async throws {
        let client = StrataClient(
            baseURL: base,
            apiKey: "wrong",
            transport: StubTransport.responding("{}"),
            streamTransport: StubChatTransport.failing(StrataError.unauthorized)
        )

        do {
            _ = try await client.chatStream(ChatRequestBody(model: "m", messages: []))
            XCTFail("expected 401")
        } catch let error as StrataError {
            XCTAssertEqual(error, .unauthorized)
        }
    }
}

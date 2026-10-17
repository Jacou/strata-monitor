import XCTest
@testable import StrataCore

/// Which fields a chat request carries — `send()` in docs/reference-app.js (~line 778).
final class ChatRequestTests: XCTestCase {
    private func json(_ body: ChatRequestBody) -> [String: Any] {
        let data = try! JSONEncoder().encode(body)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - defaults

    func testDefaultsMatchTheWebPage() {
        let settings = ChatSamplingSettings.defaults
        XCTAssertEqual(settings.effort, .high)
        XCTAssertEqual(settings.temperature, 0.6)
        XCTAssertEqual(settings.topP, 0.95)
        XCTAssertEqual(settings.topK, 20)
        XCTAssertNil(settings.maxTokens)
        XCTAssertNil(settings.seed)
        XCTAssertTrue(settings.showsThinking)
    }

    func testDefaultBody() {
        let body = ChatRequestBody.build(
            model: "qwen3.8-flash",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: .defaults
        )
        let got = json(body)

        XCTAssertEqual(got["model"] as? String, "qwen3.8-flash")
        XCTAssertEqual(got["stream"] as? Bool, true)
        XCTAssertEqual(got["reasoning_effort"] as? String, "high")
        XCTAssertEqual(got["temperature"] as? Double, 0.6)
        XCTAssertEqual(got["top_p"] as? Double, 0.95)
        XCTAssertEqual(got["top_k"] as? Int, 20)
        XCTAssertNil(got["max_tokens"])
        XCTAssertNil(got["seed"])

        let messages = got["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "hi")
    }

    // MARK: - field presence

    func testGreedySendsOnlyTemperature() {
        let body = ChatRequestBody.build(
            model: "m",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: ChatSamplingSettings(temperature: 0, topP: 0.95, topK: 20)
        )
        let got = json(body)

        XCTAssertEqual(got["temperature"] as? Double, 0)
        XCTAssertNil(got["top_p"], "greedy ignores top_p")
        XCTAssertNil(got["top_k"], "greedy ignores top_k")
    }

    func testMaxTokensAndSeedAppearWhenSet() {
        let body = ChatRequestBody.build(
            model: "m",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: ChatSamplingSettings(maxTokens: 512, seed: 7)
        )
        let got = json(body)
        XCTAssertEqual(got["max_tokens"] as? Int, 512)
        XCTAssertEqual(got["seed"] as? Int, 7)
    }

    func testZeroIsTheWebPagesEmptyField() {
        // `if (settings.seed)` / `if (settings.max)`: 0 in those inputs sends nothing.
        let body = ChatRequestBody.build(
            model: "m",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: ChatSamplingSettings(maxTokens: 0, seed: 0)
        )
        let got = json(body)
        XCTAssertNil(got["max_tokens"])
        XCTAssertNil(got["seed"])
    }

    func testEveryThinkingChoiceIsSentByItsName() {
        for effort in ReasoningEffort.allCases {
            let body = ChatRequestBody.build(
                model: "m",
                messages: [ChatMessage(role: .user, text: "hi")],
                settings: ChatSamplingSettings(effort: effort)
            )
            XCTAssertEqual(json(body)["reasoning_effort"] as? String, effort.rawValue)
        }
    }

    func testUnknownModelFallsBackToTheWebPagesPlaceholder() {
        XCTAssertEqual(ChatRequestBody.build(model: nil, messages: [], settings: .defaults).model, "strata")
        XCTAssertEqual(ChatRequestBody.build(model: "", messages: [], settings: .defaults).model, "strata")
    }

    // MARK: - the history that goes back (`apiMessages()`)

    func testSystemPromptGoesFirst() {
        let body = ChatRequestBody.build(
            model: "m",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: ChatSamplingSettings(systemPrompt: "  Be brief.  ")
        )
        XCTAssertEqual(body.messages.first?.role, .system)
        XCTAssertEqual(body.messages.first?.content, "Be brief.")
        XCTAssertEqual(body.messages.count, 2)
    }

    func testBlankSystemPromptIsNotSent() {
        let body = ChatRequestBody.build(
            model: "m",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: ChatSamplingSettings(systemPrompt: " \n ")
        )
        XCTAssertFalse(body.messages.contains { $0.role == .system })
    }

    func testConversationOrderIsKeptAndFailedAnswersAreDropped() {
        var failed = ChatMessage(role: .assistant, text: "partial")
        failed.error = "the engine reported an error"
        var empty = ChatMessage(role: .assistant)
        empty.text = ""

        let history = ChatConversation.history(messages: [
            ChatMessage(role: .user, text: "one"),
            ChatMessage(role: .assistant, text: "answer one"),
            failed,
            empty,
            ChatMessage(role: .user, text: "two"),
        ])

        XCTAssertEqual(history.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(history.map(\.content), ["one", "answer one", "two"])
    }

    func testThinkingIsNotSentBackAsAnAnswer() {
        let reasoned = ChatMessage(role: .assistant, text: "answer", reasoning: "a long chain of thought")
        let onlyReasoning = ChatMessage(role: .assistant, reasoning: "thought but never answered")

        let history = ChatConversation.history(messages: [reasoned, onlyReasoning])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content, "answer")
    }

    func testBodyRoundTripsThroughJSON() {
        let body = ChatRequestBody.build(
            model: "m",
            messages: [ChatMessage(role: .user, text: "hi")],
            settings: ChatSamplingSettings(topP: 0.5, topK: 8, maxTokens: 100, seed: 3)
        )
        let data = try! JSONEncoder().encode(body)
        XCTAssertEqual(ChatRequestBody.decode(data), body)
    }
}

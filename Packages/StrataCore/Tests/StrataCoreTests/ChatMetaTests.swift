import XCTest
@testable import StrataCore

/// The lines under an answer, from `send()` / `updateAssistant()` in docs/reference-app.js.
final class ChatMetaTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    // MARK: - "N tokens · X tok/s"

    func testTokensAndSpeed() {
        XCTAssertEqual(
            ChatMeta.line(tokens: 128, firstTokenAt: 10, endedAt: 14, stopped: false, locale: en),
            "128 tokens · 32.0 tok/s"
        )
    }

    func testGroupedTokenCount() {
        XCTAssertEqual(
            ChatMeta.line(tokens: 12_345, firstTokenAt: 0, endedAt: 1, stopped: false, locale: en),
            "12,345 tokens · 12,345.0 tok/s"
        )
    }

    func testUnderAQuarterSecondPrintsNoSpeed() {
        // The web page: `secs > 0.25` — a faster number than that is measurement noise.
        XCTAssertEqual(
            ChatMeta.line(tokens: 4, firstTokenAt: 10, endedAt: 10.2, stopped: false, locale: en),
            "4 tokens"
        )
    }

    func testStoppedAppendsItsOwnMark() {
        XCTAssertEqual(
            ChatMeta.line(tokens: 40, firstTokenAt: 1, endedAt: 3, stopped: true, locale: en),
            "40 tokens · 20.0 tok/s · stopped"
        )
        XCTAssertEqual(
            ChatMeta.line(tokens: 3, firstTokenAt: 1, endedAt: 1.1, stopped: true, locale: en),
            "3 tokens · stopped"
        )
    }

    func testNoTokensIsJustStopped() {
        // `const n = usage ? usage.completion_tokens : null; if (n && firstAt)` — 0 counts as nothing.
        XCTAssertEqual(ChatMeta.line(tokens: nil, firstTokenAt: 1, endedAt: 5, stopped: true, locale: en), "Stopped")
        XCTAssertEqual(ChatMeta.line(tokens: 0, firstTokenAt: 1, endedAt: 5, stopped: true, locale: en), "Stopped")
        XCTAssertNil(ChatMeta.line(tokens: nil, firstTokenAt: nil, endedAt: 5, stopped: false, locale: en))
        XCTAssertNil(ChatMeta.line(tokens: 0, firstTokenAt: nil, endedAt: 5, stopped: false, locale: en))
    }

    func testTokensWithoutAMeasuredStartPrintNothing() {
        // `if (n && firstAt)`: no first token means no seconds to divide by, and the web page
        // leaves the meta line empty rather than guessing.
        XCTAssertNil(ChatMeta.line(tokens: 7, firstTokenAt: nil, endedAt: 5, stopped: false, locale: en))
    }

    // MARK: - the Thinking block's title

    func testThinkTitle() {
        XCTAssertNil(ChatMeta.thinkTitle(reasoning: "", thinkSecs: nil, streaming: true))
        XCTAssertNil(ChatMeta.thinkTitle(reasoning: "", thinkSecs: 3, streaming: false))

        XCTAssertEqual(ChatMeta.thinkTitle(reasoning: "hmm", thinkSecs: nil, streaming: true), "Thinking…")
        XCTAssertEqual(ChatMeta.thinkTitle(reasoning: "hmm", thinkSecs: 4.2, streaming: true), "Thinking…")
        XCTAssertEqual(ChatMeta.thinkTitle(reasoning: "hmm", thinkSecs: 4.2, streaming: false), "Thought for 4.2 s")
        XCTAssertEqual(ChatMeta.thinkTitle(reasoning: "hmm", thinkSecs: nil, streaming: false), "Thoughts")
    }
}

import XCTest
@testable import StrataCore

/// Prose and fenced code, split the way `markdown()` does in docs/reference-app.js (~line 541).
final class ChatMarkdownTests: XCTestCase {
    func testPlainProseIsOneBlock() {
        XCTAssertEqual(ChatMarkdown.blocks("Hello **there**."), [.text("Hello **there**.")])
        XCTAssertEqual(ChatMarkdown.blocks("line one\nline two"), [.text("line one\nline two")])
    }

    func testEmptyAnswer() {
        XCTAssertTrue(ChatMarkdown.blocks("").isEmpty)
    }

    func testOneFencedBlock() {
        XCTAssertEqual(
            ChatMarkdown.blocks("before\n```swift\nlet x = 1\n```\nafter"),
            [.text("before"), .code("let x = 1", language: "swift"), .text("after")]
        )
    }

    func testFenceAtTheStartAndAtTheEnd() {
        XCTAssertEqual(
            ChatMarkdown.blocks("```\ncode\n```"),
            [.code("code", language: nil)]
        )
        XCTAssertEqual(
            ChatMarkdown.blocks("```\ncode\n```\ntail"),
            [.code("code", language: nil), .text("tail")]
        )
        XCTAssertEqual(
            ChatMarkdown.blocks("head\n```c\ncode\n```"),
            [.text("head"), .code("code", language: "c")]
        )
    }

    func testUnterminatedFenceIsCodeWhileItStreams() {
        XCTAssertEqual(
            ChatMarkdown.blocks("here is the patch:\n```python\ndef f():\n    pass\n"),
            [.text("here is the patch:"), .code("def f():\n    pass\n", language: "python")]
        )
    }

    func testFenceWithNoNewlineYetIsStillProse() {
        // The web page's open-fence regex needs the newline after the info string.
        XCTAssertEqual(ChatMarkdown.blocks("text\n```"), [.text("text\n```")])
        XCTAssertEqual(ChatMarkdown.blocks("text\n```py"), [.text("text\n```py")])
    }

    func testFenceMidLineIsNotAFence() {
        XCTAssertEqual(ChatMarkdown.blocks("use ``` inside a sentence"), [.text("use ``` inside a sentence")])
        XCTAssertEqual(
            ChatMarkdown.blocks("use ``` inside\n```\nreal code\n```"),
            [.text("use ``` inside"), .code("real code", language: nil)]
        )
    }

    func testTwoBlocks() {
        XCTAssertEqual(
            ChatMarkdown.blocks("a\n```js\none\n```\nb\n```js\ntwo\n```\nc"),
            [.text("a"), .code("one", language: "js"), .text("b"), .code("two", language: "js"), .text("c")]
        )
    }

    func testClosingFenceWithTrailingSpaces() {
        XCTAssertEqual(
            ChatMarkdown.blocks("```\ncode\n```   \ntail"),
            [.code("code", language: nil), .text("tail")]
        )
    }

    func testClosingFenceAtTheVeryEndWithoutANewline() {
        XCTAssertEqual(ChatMarkdown.blocks("```\ncode\n```"), [.code("code", language: nil)])
    }

    func testEmptyCodeBlockIsDropped() {
        XCTAssertEqual(ChatMarkdown.blocks("a\n```\n```\nb"), [.text("a"), .text("b")])
    }

    func testCodeKeepsItsOwnFencesAndBlankLines() {
        XCTAssertEqual(
            ChatMarkdown.blocks("```\nline\n\n  indented\n```"),
            [.code("line\n\n  indented", language: nil)]
        )
    }

    func testInfoStringWithBackticksIsNotAFence() {
        // `[^\n`]*`: a weird info string leaves the text as prose.
        XCTAssertEqual(
            ChatMarkdown.blocks("```\n``x``\n```"),
            [.code("``x``", language: nil)]
        )
    }
}

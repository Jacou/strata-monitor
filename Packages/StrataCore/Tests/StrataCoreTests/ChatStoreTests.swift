import XCTest
@testable import StrataCore

/// Conversations written to a file and read back — the last 20, newest last.
@MainActor
final class ChatStoreTests: XCTestCase {
    /// A scratch file per test, in the system temp directory (the folder is made up front, so a
    /// test can write the file itself).
    private func file() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("chat.json")
    }

    private func conversation(_ text: String, at date: Date = .now) -> ChatConversation {
        ChatConversation(
            createdAt: date,
            updatedAt: date,
            messages: [
                ChatMessage(role: .user, text: text, time: date),
                ChatMessage(role: .assistant, text: "answer to \(text)", reasoning: "thinking", time: date,
                            thinkSecs: 2.5, meta: "12 tokens · 4.8 tok/s"),
            ]
        )
    }

    // MARK: - round trip

    func testRoundTripKeepsEveryField() throws {
        let url = file()
        let store = ChatStore(fileURL: url)
        let saved = conversation("hello")
        store.save(saved)

        let reloaded = ChatStore(fileURL: url)
        XCTAssertEqual(reloaded.conversations.count, 1)
        let got = try XCTUnwrap(reloaded.conversations.first)
        XCTAssertEqual(got.messages.count, 2)
        XCTAssertEqual(got.messages[0].role, .user)
        XCTAssertEqual(got.messages[0].text, "hello")
        XCTAssertEqual(got.messages[1].text, "answer to hello")
        XCTAssertEqual(got.messages[1].reasoning, "thinking")
        XCTAssertEqual(got.messages[1].thinkSecs, 2.5)
        XCTAssertEqual(got.messages[1].meta, "12 tokens · 4.8 tok/s")
        XCTAssertEqual(got.messages[1].stopped, false)
        XCTAssertNil(got.messages[1].error)
        // Dates survive to the second, which is all the meta line and the Chats list need.
        XCTAssertEqual(got.messages[0].time.timeIntervalSince1970,
                       saved.messages[0].time.timeIntervalSince1970, accuracy: 0.01)
    }

    func testSaveReplacesTheSameConversation() {
        let url = file()
        let store = ChatStore(fileURL: url)
        var conversation = conversation("hello")
        store.save(conversation)

        conversation.messages.append(ChatMessage(role: .user, text: "again"))
        store.save(conversation)

        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.conversations.first?.messages.count, 3)
        XCTAssertEqual(ChatStore(fileURL: url).conversations.first?.messages.count, 3)
    }

    func testNewestLast() {
        let store = ChatStore(fileURL: file())
        let older = conversation("older", at: Date(timeIntervalSince1970: 1_000))
        let newer = conversation("newer", at: Date(timeIntervalSince1970: 2_000))
        store.save(newer)
        store.save(older)

        XCTAssertEqual(store.conversations.map(\.title), ["newer", "older"])
        XCTAssertEqual(store.mostRecent?.title, "older")   // "older" was touched last
    }

    // MARK: - the 20 conversation cap

    func testOnlyTheLast20AreKept() {
        let url = file()
        let store = ChatStore(fileURL: url)
        for index in 0..<25 {
            let date = Date(timeIntervalSince1970: 1_000 + Double(index))
            store.save(conversation("chat \(index)", at: date))
        }

        XCTAssertEqual(store.conversations.count, ChatStore.maxConversations)
        XCTAssertEqual(store.conversations.first?.title, "chat 5")
        XCTAssertEqual(store.conversations.last?.title, "chat 24")
        XCTAssertEqual(ChatStore(fileURL: url).conversations.count, ChatStore.maxConversations)
    }

    // MARK: - damage

    func testMissingFileIsAnEmptyHistory() {
        let store = ChatStore(fileURL: file().appendingPathComponent("nope.json"))
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertNil(store.lastError)
    }

    func testUnreadableFileIsAnEmptyHistoryNotACrash() throws {
        let url = file()
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)

        let store = ChatStore(fileURL: url)
        XCTAssertTrue(store.conversations.isEmpty)
    }

    func testAPartialConversationIsDroppedRatherThanEndingTheRead() throws {
        // Hand-written JSON: one good conversation and one with dates the file never writes.
        let url = file()
        let text = """
        [{"id":"11111111-1111-1111-1111-111111111111","createdAt":"2026-01-01T00:00:00Z",\
        "updatedAt":"2026-01-01T00:00:00Z","messages":[{"id":"22222222-2222-2222-2222-222222222222",\
        "role":"user","text":"kept","reasoning":"","time":"2026-01-01T00:00:00Z","stopped":false}]},\
        {"id":"33333333-3333-3333-3333-333333333333","createdAt":"nonsense","updatedAt":"nonsense","messages":[]}]
        """
        try text.write(to: url, atomically: true, encoding: .utf8)

        let store = ChatStore(fileURL: url)
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.conversations.first?.messages.first?.text, "kept")
    }

    // MARK: - deleting

    func testDeleteAndClear() {
        let url = file()
        let store = ChatStore(fileURL: url)
        store.save(conversation("one"))
        store.save(conversation("two"))

        store.delete(store.conversations.first!.id)
        XCTAssertEqual(store.conversations.map(\.title), ["two"])
        XCTAssertEqual(ChatStore(fileURL: url).conversations.map(\.title), ["two"])

        store.clearAll()
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertTrue(ChatStore(fileURL: url).conversations.isEmpty)
    }

    // MARK: - the file's home

    func testDefaultFileLivesInApplicationSupport() {
        let url = ChatStore.defaultFileURL()
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertEqual(url.lastPathComponent, "chat.json")
    }

    func testTitleIsTheFirstQuestionOnOneLine() {
        XCTAssertEqual(conversation("What is the GPU doing?").title, "What is the GPU doing?")
        XCTAssertEqual(ChatConversation(messages: [ChatMessage(role: .user, text: "first\nsecond")]).title, "first")
        XCTAssertEqual(ChatConversation().title, "New chat")

        let long = ChatConversation(messages: [ChatMessage(role: .user, text: String(repeating: "x", count: 120))])
        XCTAssertEqual(long.title.count, 60)
        XCTAssertTrue(long.title.hasSuffix("…"))
    }
}

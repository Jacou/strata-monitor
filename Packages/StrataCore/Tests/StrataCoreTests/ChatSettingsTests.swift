import XCTest
@testable import StrataCore

@MainActor
final class ChatSettingsTests: XCTestCase {
    /// A defaults suite per test, so nothing leaks into the app's own.
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "ChatSettingsTests-\(UUID().uuidString)")!
    }

    func testFreshSettingsAreTheWebPagesDefaults() {
        let settings = ChatSettings(defaults: suite())
        XCTAssertEqual(settings.sampling, .defaults)
        XCTAssertEqual(settings.sampling.effort.hint, "thorough (default)")
    }

    func testChangesSurviveARestart() {
        let defaults = suite()
        let settings = ChatSettings(defaults: defaults)
        settings.sampling.effort = .low
        settings.sampling.temperature = 0
        settings.sampling.topK = 40
        settings.sampling.maxTokens = 1_024
        settings.sampling.seed = 12
        settings.sampling.systemPrompt = "Answer in one line."
        settings.sampling.showsThinking = false

        let reloaded = ChatSettings(defaults: defaults)
        XCTAssertEqual(reloaded.sampling, settings.sampling)
        XCTAssertEqual(reloaded.sampling.effort, .low)
        XCTAssertEqual(reloaded.sampling.maxTokens, 1_024)
        XCTAssertEqual(reloaded.sampling.seed, 12)
        XCTAssertEqual(reloaded.sampling.systemPrompt, "Answer in one line.")
        XCTAssertFalse(reloaded.sampling.showsThinking)
    }

    func testResetGoesBackToTheDefaults() {
        let defaults = suite()
        let settings = ChatSettings(defaults: defaults)
        settings.sampling.temperature = 1.2
        settings.reset()

        XCTAssertEqual(settings.sampling, .defaults)
        XCTAssertEqual(ChatSettings(defaults: defaults).sampling, .defaults)
    }

    func testJunkInDefaultsFallsBackToTheDefaults() {
        let defaults = suite()
        defaults.set(Data("not json".utf8), forKey: "chat.sampling")
        XCTAssertEqual(ChatSettings(defaults: defaults).sampling, .defaults)
    }

    func testHalfWrittenBlobFallsBackToTheDefaults() {
        let defaults = suite()
        defaults.set(Data(#"{"temperature":"warm"}"#.utf8), forKey: "chat.sampling")
        XCTAssertEqual(ChatSettings(defaults: defaults).sampling, .defaults)
    }

    func testGreedyIsRecognised() {
        var settings = ChatSamplingSettings.defaults
        XCTAssertFalse(settings.isGreedy)
        XCTAssertEqual(settings.temperatureLabel, "0.60")

        settings.temperature = 0
        XCTAssertTrue(settings.isGreedy)
        XCTAssertEqual(settings.temperatureLabel, "0 · greedy")
    }

    func testEmptyFieldsReadAsServerDefaultAndRandom() {
        let settings = ChatSamplingSettings.defaults
        XCTAssertEqual(settings.maxTokensLabel, "server default")
        XCTAssertEqual(settings.seedLabel, "random")
        XCTAssertFalse(settings.hasSystemPrompt)

        let set = ChatSamplingSettings(maxTokens: 256, seed: 1, systemPrompt: " hi ")
        XCTAssertEqual(set.maxTokensLabel, "256")
        XCTAssertEqual(set.seedLabel, "1")
        XCTAssertTrue(set.hasSystemPrompt)
    }

    func testThinkingChoicesAreTheWebPagesValues() {
        XCTAssertEqual(ReasoningEffort.allCases.map(\.rawValue), ["none", "low", "medium", "high"])
        XCTAssertEqual(
            ReasoningEffort.allCases.map(\.hint),
            ["answers right away", "short", "medium", "thorough (default)"]
        )
    }
}

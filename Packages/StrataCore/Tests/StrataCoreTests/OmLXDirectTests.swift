import XCTest
@testable import StrataCore

/// oMLX read straight from its admin API: the log parser that replaced the stats proxy's journal,
/// the new payloads, and the Monitor model built from them.
@MainActor
final class OmLXDirectTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!
    private let model = "DeepSeek-V4.1-Flash-1017-oQ2.5e-ngram-mtp"

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Fixtures.data(name, testClass: Self.self))
    }

    // MARK: - log parsing

    func testFinishedRequestsFromTheLogTail() throws {
        let tail = try decode(OmLXLogTail.self, "omlx_logs")
        let found = OmLXLogParser.finishedRequests(
            in: tail.numberedLines.map { $0.text },
            windows: [model: 1_048_576],
            timeZone: utc
        )
        XCTAssertEqual(found.count, 2)

        let newest = try XCTUnwrap(found.first)
        XCTAssertEqual(newest.outputTokens, 12, "newest first")
        XCTAssertEqual(newest.finish, "stop")
        XCTAssertNil(newest.ttftS, "a request that was not streamed logs no TTFT")

        let streamed = try XCTUnwrap(found.last)
        XCTAssertEqual(streamed.model, model)
        XCTAssertEqual(streamed.promptTokens, 97_480)
        XCTAssertEqual(streamed.outputTokens, 601)
        XCTAssertEqual(streamed.durationS, 9.81)
        XCTAssertEqual(streamed.tokS, 74.3)
        XCTAssertEqual(streamed.finish, "tool_calls")
        XCTAssertEqual(streamed.maxTokens, 65_536)
        XCTAssertEqual(streamed.ttftS, 1.71)
        XCTAssertEqual(streamed.contextUsed, 98_081)
        XCTAssertEqual(streamed.contextWindow, 1_048_576)
        // 2026-11-21 21:30:01.123 UTC
        XCTAssertEqual(try XCTUnwrap(streamed.finishedAt), 1_795_296_601.123, accuracy: 0.001)
    }

    func testDiffusionSpeedTextStillParses() {
        let line = "2026-11-21 21:30:01,123 - omlx.server - INFO - Chat completion: model=D, 12 tokens in 0.50s "
            + "(24.0 tok/s e2e, output=30.1 tok/s), prompt: 30, finish_reason=stop, max_tokens=4096, "
            + "request_max_tokens=None, stream_model_ttft=unavailable, stream_visible_ttft=unavailable"
        let found = OmLXLogParser.finishedRequests(in: [line], timeZone: utc)
        XCTAssertEqual(found.first?.tokS, 24.0)
        XCTAssertNil(found.first?.ttftS)
    }

    func testLogTailNumbersLinesFromTheEndOfTheFile() throws {
        let tail = try decode(OmLXLogTail.self, "omlx_logs")
        let batch = OmLXLogParser.batch(tail, timeZone: utc)
        XCTAssertEqual(batch.last, 1206)
        XCTAssertEqual(batch.lines.count, 6)
        XCTAssertEqual(batch.lines.last?.id, 1206, "the last line is the file's last")
        XCTAssertEqual(batch.lines.first?.id, 1201)

        let warning = batch.lines[2]
        XCTAssertEqual(warning.level, .warn)
        XCTAssertEqual(warning.source, "omlx.process_memory_enforcer")
        XCTAssertEqual(warning.message, "Memory pressure: soft")

        let traceback = batch.lines[3]
        XCTAssertEqual(traceback.level, .info, "a line without the header is kept as it is")
        XCTAssertEqual(traceback.message, "Traceback (most recent call last):")
        XCTAssertNil(traceback.time)

        XCTAssertEqual(batch.lines[5].level, .err)
    }

    func testLogFeedReadsTheOMLXTail() async throws {
        let body = try String(contentsOf: Fixtures.url("omlx_logs", testClass: Self.self), encoding: .utf8)
        let transport = StubTransport { request in (Data(body.utf8), httpResponse(request.url!, 200)) }
        let feed = LogFeed()
        feed.engine = .omlx
        await feed.fetch(StrataClient(baseURL: URL(string: "http://mac:8000")!, apiKey: "k", transport: transport))
        XCTAssertEqual(feed.lines.count, 6)
        XCTAssertNil(feed.errorText)
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/admin/api/logs")
        XCTAssertEqual(url.query, "lines=\(LogFeed.omlxTailLines)")

        // The same tail again adds nothing.
        await feed.fetch(StrataClient(baseURL: URL(string: "http://mac:8000")!, apiKey: "k", transport: transport))
        XCTAssertEqual(feed.lines.count, 6)
    }

    // MARK: - journal

    func testMergeKeepsNewestFirstWithoutDuplicates() {
        func item(_ t: Double, _ out: Double) -> OmLXFinishedRequest {
            var item = OmLXFinishedRequest()
            item.finishedAt = t
            item.model = "m"
            item.outputTokens = out
            item.promptTokens = 1
            return item
        }
        let held = [item(20, 2), item(10, 1)]
        let merged = MetricsPoller.merge(journal: held, with: [item(10, 1), item(20, 2), item(30, 3)])
        XCTAssertEqual(merged.map { $0.finishedAt }, [30, 20, 10])

        let many = (0..<80).map { item(Double($0), 1) }
        let capped = MetricsPoller.merge(journal: [], with: many)
        XCTAssertEqual(capped.count, MetricsPoller.journalLimit)
        XCTAssertEqual(capped.first?.finishedAt, 79)
    }

    func testFinishedRowIDsStayPutAsNewRequestsArrive() {
        var first = OmLXFinishedRequest()
        first.finishedAt = 100.5
        first.model = "m"
        var second = first
        second.finishedAt = 101.25
        let before = OmLXSnapshot(activity: OmLXActivity(), recent: OmLXRecent(requests: [first], windows: nil, slots: nil))
        let after = OmLXSnapshot(activity: OmLXActivity(), recent: OmLXRecent(requests: [second, first], windows: nil, slots: nil))
        XCTAssertEqual(before.finishedRows().first?.id, after.finishedRows().last?.id)
        XCTAssertNotEqual(after.finishedRows()[0].id, after.finishedRows()[1].id)
    }

    // MARK: - payloads

    func testModelsGiveContextWindows() throws {
        let list = try decode(OmLXModelList.self, "omlx_models")
        XCTAssertEqual(list.models.count, 3)
        XCTAssertEqual(list.windows[model], 1_048_576)
        XCTAssertEqual(list.windows["GLM-5.3-Flash-oQ4e-mtp"], 202_752)
        XCTAssertNil(list.windows["embed-small"], "a null length is not a window")
    }

    func testGlobalSettingsGiveTheLaneCount() throws {
        XCTAssertEqual(try decode(OmLXGlobalSettings.self, "omlx_global_settings").maxConcurrentRequests, 4)
    }

    func testRuntimeCacheAndRates() throws {
        let stats = try decode(OmLXStats.self, "omlx_stats")
        let cache = try XCTUnwrap(stats.runtimeCache)
        XCTAssertEqual(cache.totalNumFiles, 96)
        XCTAssertEqual(cache.diskMaxBytes, 85_899_345_920)
        XCTAssertFalse(cache.hasMemoryTier)
        let rates = cache.rates()
        XCTAssertEqual(rates.prefixHits, 2)
        XCTAssertEqual(rates.prefixMisses, 4)
        XCTAssertEqual(try XCTUnwrap(rates.prefixHitRate), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(rates.memoryHitRate, 0, "38 disk loads, no memory hits")
        XCTAssertEqual(cache.rates(model: model), rates, "one model loaded: the same counters")
        XCTAssertEqual(cache.rates(model: "nope"), OmLXCacheRates())
    }

    func testUsageBarsByHourForOneDay() throws {
        let usage = try decode(OmLXUsage.self, "omlx_usage_today")
        let bars = usage.bars
        XCTAssertEqual(bars.count, 24)
        XCTAssertEqual(bars[10].label, "10")
        XCTAssertEqual(bars[10].tokens, 340_500)
        XCTAssertEqual(usage.totals?.totalTokens, 558_581)
        XCTAssertEqual(usage.models?.first?.modelID, model)
    }

    func testUsageBarsByDayForAWeek() {
        var usage = OmLXUsage()
        usage.heatmap = [
            OmLXUsageDay(date: "2026-11-20", tokens: [1, 2, 3]),
            OmLXUsageDay(date: "2026-11-21", tokens: [10]),
        ]
        XCTAssertEqual(usage.bars.map(\.label), ["20", "21"])
        XCTAssertEqual(usage.bars.map(\.tokens), [6, 10])
    }

    // MARK: - requests

    func testStatsQueryCarriesScopeAndModel() async throws {
        let body = try String(contentsOf: Fixtures.url("omlx_stats", testClass: Self.self), encoding: .utf8)
        let transport = StubTransport { request in (Data(body.utf8), httpResponse(request.url!, 200)) }
        let client = StrataClient(baseURL: URL(string: "http://mac:8000")!, apiKey: "k", transport: transport)
        _ = try await client.omlxStats(scope: .alltime, model: "a b")
        let url = try XCTUnwrap(transport.requests.first?.url)
        XCTAssertEqual(url.path, "/admin/api/stats")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, "alltime")
        XCTAssertEqual(items.first { $0.name == "model" }?.value, "a b")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    // MARK: - the Monitor model

    func testMonitorModelFromTheFixtures() throws {
        let activity = try decode(OmLXActivity.self, "omlx_activity_generating")
        let stats = try decode(OmLXStats.self, "omlx_stats")
        let monitor = OmLXMonitorModel(
            activity: activity,
            stats: stats,
            scopedStats: stats,
            scope: .session,
            modelFilter: nil,
            usage: try decode(OmLXUsage.self, "omlx_usage_today"),
            usageRange: .today,
            modelList: try decode(OmLXModelList.self, "omlx_models"),
            slots: 4,
            locale: locale
        )

        XCTAssertTrue(monitor.live.isDecoding)
        XCTAssertTrue(monitor.live.detail.contains("4 lanes"), monitor.live.detail)
        XCTAssertEqual(monitor.models.count, 1)
        let row = try XCTUnwrap(monitor.models.first)
        XCTAssertEqual(row.id, model)
        XCTAssertEqual(row.contextText, "1M context")
        XCTAssertFalse(row.requests.isEmpty)
        XCTAssertEqual(monitor.modelsSummary, "1 loaded")

        let serving = try XCTUnwrap(monitor.serving)
        XCTAssertFalse(serving.isLoading)
        XCTAssertEqual(serving.tiles.first { $0.id == "requests" }?.value, "16")
        XCTAssertEqual(serving.tiles.first { $0.id == "efficiency" }?.value, "97.7")
        XCTAssertNotNil(serving.footnote, "session scope shows the uptime")

        let usage = try XCTUnwrap(monitor.usage)
        XCTAssertEqual(usage.bars.count, 24)
        XCTAssertEqual(usage.axisLabel, "Hour")
        XCTAssertNil(usage.unavailableText)
        XCTAssertTrue(usage.facts.contains { $0.key == "GLM-5.3-Flash-oQ4e-mtp" }, "two models served: both listed")

        let cache = try XCTUnwrap(monitor.cache)
        XCTAssertEqual(cache.tiers.map(\.label), ["SSD"], "no memory tier configured")
        XCTAssertEqual(cache.facts.first { $0.key == "Prefix hit rate" }?.value, "33.3%")

        XCTAssertEqual(monitor.engines.first?.key, "mlx")
        XCTAssertEqual(monitor.filterChoices.first, model)
        XCTAssertTrue(monitor.filterChoices.contains("GLM-5.3-Flash-oQ4e-mtp"), "a model with usage history can be picked")
    }

    func testServingWaitsForAFreshScope() {
        let monitor = OmLXMonitorModel(
            activity: OmLXActivity(), stats: nil, scopedStats: nil, scope: .alltime, modelFilter: nil,
            usage: nil, usageRange: .today, modelList: nil, slots: nil, locale: locale
        )
        XCTAssertEqual(monitor.serving?.isLoading, true)
        XCTAssertNil(monitor.usage)
        XCTAssertNil(monitor.cache)
        XCTAssertEqual(monitor.live.detail, "No model loaded")
    }

    func testBigCounts() {
        XCTAssertEqual(OmLXMonitorModel.bigCount(950, locale: locale), "950")
        XCTAssertEqual(OmLXMonitorModel.bigCount(12_400, locale: locale), "12k")
        XCTAssertEqual(OmLXMonitorModel.bigCount(3_200_000, locale: locale), "3.2M")
        XCTAssertEqual(OmLXMonitorModel.bigCount(1_100_000_000, locale: locale), "1.1B")
    }
}

import XCTest
@testable import StrataCore

/// A real Basalt server's payloads (two RTX 5070 Ti, two parallel slots, both decoding).
@MainActor
final class BasaltTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Fixtures.data(name, testClass: Self.self))
    }

    private func metrics() throws -> Metrics { try decode(Metrics.self, "basalt_metrics_generating") }
    private func slots() throws -> [Slot] { try decode([Slot].self, "basalt_slots") }

    // MARK: - detection

    func testHealthSaysWhichEngine() throws {
        XCTAssertEqual(try decode(Health.self, "basalt_health").engine, .basalt)
        XCTAssertEqual(try decode(Health.self, "health").engine, .strata)
        XCTAssertEqual(Health().engine, .strata, "no service field: what every older server said")
        XCTAssertFalse(ServerEngine.basalt.hasRunConfig)
        XCTAssertTrue(ServerEngine.basalt.hasLogs)
        XCTAssertTrue(ServerEngine.strata.hasRunConfig)
    }

    // MARK: - totals from the per-GPU rows

    func testGPUTotalsAreWorkedOutLikeStrata() throws {
        let hw = try XCTUnwrap(try metrics().hardware)
        XCTAssertEqual(hw.gpuUtil, 98)                                   // mean of 99 and 97
        XCTAssertEqual(hw.gpuMemUsed, 16_360_538_112 + 16_892_166_144)   // summed
        XCTAssertEqual(hw.gpuMemTotal, 2 * 17_094_934_528)
        XCTAssertEqual(hw.gpuTemp, 53)                                   // the hotter card
        XCTAssertEqual(hw.gpuPowerLimit, 500)
        XCTAssertEqual(hw.gpuPcieGenMax, 4)
        XCTAssertEqual(hw.gpuPcieWidth, 4)    // the narrower link: 16 and 4 lanes
        XCTAssertNotNil(hw.gpuPower)
        XCTAssertNotNil(hw.gpuPcieRxMb)
    }

    func testTotalsTheServerSentAreKept() throws {
        let strata = try decode(Metrics.self, "metrics_generating")
        XCTAssertEqual(strata.hardware?.gpuUtil, 50)
        XCTAssertEqual(strata.hardware?.gpuPcieWidth, 4)
    }

    func testGPUNamesAndDriverFacts() throws {
        let st = try XCTUnwrap(try metrics().hardwareStatic)
        XCTAssertEqual(st.gpuName, "NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti")
        XCTAssertEqual(st.gpuCount, 2)
        XCTAssertEqual(st.driver, "610.57.04")
        XCTAssertEqual(st.cuda, "13.3")
    }

    func testTheGPUTilesNoLongerShowADash() throws {
        let vm = MonitorViewModel(metrics: try metrics(), locale: locale)
        for kind in [MonitorViewModel.MetricKind.gpu, .vram, .temp, .power, .pcie] {
            let tile = try XCTUnwrap(vm.metrics.first { $0.kind == kind })
            XCTAssertNotEqual(tile.value, notAvailable, "\(kind)")
        }
    }

    // MARK: - live, speed and context with two slots

    func testLiveCardCountsTheStreams() throws {
        let vm = MonitorViewModel(metrics: try metrics(), locale: locale, slots: try slots())
        XCTAssertEqual(vm.live.label, "2 requests running")
        XCTAssertEqual(vm.live.detail, "2 decoding · 79.0 tok/s total")
        let speed = try XCTUnwrap(vm.metrics.first { $0.kind == .speed })
        XCTAssertEqual(speed.value, "79.0")
        XCTAssertEqual(speed.sub, "Decode, 2 streams total")
    }

    /// What the phone showed: slot 0 decoding while slot 1 reads its prompt, and the engine's
    /// own state following the reading one.
    func testOneDecodingWhileTheOtherReads() throws {
        var m = try metrics()
        m.live?.state = .reading
        var mixed = try slots()
        mixed[0].tokS = 36.2
        mixed[1].state = .prefill
        let vm = MonitorViewModel(metrics: m, locale: locale, slots: mixed)
        XCTAssertEqual(vm.live.label, "2 requests running")
        XCTAssertEqual(vm.live.detail, "1 decoding · 1 reading a prompt · 36.2 tok/s total")
        let speed = try XCTUnwrap(vm.metrics.first { $0.kind == .speed })
        XCTAssertEqual(speed.value, "36.2", "the decoding slot, not the last request")
        XCTAssertEqual(speed.sub, "Decode now")
    }

    func testOneStreamReadsAsBefore() throws {
        var oneBusy = try slots()
        oneBusy[1].state = .idle
        oneBusy[1].isProcessing = false
        let vm = MonitorViewModel(metrics: try metrics(), locale: locale, slots: oneBusy)
        XCTAssertEqual(vm.live.label, "Generating")
        XCTAssertEqual(vm.live.detail, "3,214 tokens · 80.5 tok/s · 54 s")
    }

    func testContextShowsTheFullestSlot() throws {
        let vm = MonitorViewModel(metrics: try metrics(), locale: locale, slots: try slots())
        XCTAssertEqual(vm.context.percentText, "68%")   // 177,048 of 262,144
        XCTAssertTrue(vm.context.sub.hasSuffix("· slot 1"))
    }

    // MARK: - slots card

    func testSlotsCard() throws {
        let card = try XCTUnwrap(MonitorViewModel(metrics: try metrics(), locale: locale, slots: try slots()).slots)
        XCTAssertEqual(card.summary, "1 of 2 busy")   // live.slots.active as the server counted it
        XCTAssertEqual(card.note, "262k context each")
        XCTAssertEqual(card.rows.map(\.title), ["Slot 0", "Slot 1"])
        let first = card.rows[0]
        XCTAssertEqual(first.stateText, "Decoding")
        XCTAssertEqual(first.speedText, "39.5 tok/s")
        XCTAssertEqual(first.detail, "5,023 tokens")
        XCTAssertEqual(first.contextText, "87k / 262k")
        XCTAssertEqual(first.draftsText, "73% drafts accepted")
        XCTAssertEqual(card.rows[1].contextTone, .normal)
    }

    func testNoSlotsCardWithOneSlot() throws {
        var m = try metrics()
        m.live?.slots = LiveSlots(total: 1, active: 1)
        XCTAssertNil(MonitorViewModel(metrics: m, locale: locale, slots: try slots()).slots)
        XCTAssertNil(MonitorViewModel(metrics: try decode(Metrics.self, "metrics_generating"), locale: locale).slots)
    }

    // MARK: - queue

    func testQueueCardOnlyWhileSomethingWaits() throws {
        var m = try metrics()
        XCTAssertNil(MonitorViewModel(metrics: m, locale: locale).queue)

        var waiting = QueuedRequest()
        waiting.waitedS = 12.34
        waiting.api = "anthropic"
        waiting.model = "qwen"
        waiting.promptTokens = 82_433
        m.live?.queued = 5
        m.live?.queue = Array(repeating: waiting, count: 5)
        let card = try XCTUnwrap(MonitorViewModel(metrics: m, locale: locale).queue)
        XCTAssertEqual(card.summary, "5 waiting")
        XCTAssertEqual(card.rows.count, 3)
        XCTAssertEqual(card.rows[0].waitedText, "12.3 s")
        XCTAssertEqual(card.rows[0].source, "Anthropic · qwen")
        XCTAssertEqual(card.rows[0].promptText, "82,433 tokens")
        XCTAssertEqual(card.more, "+ 2 more")
    }

    // MARK: - expert sources

    func testExpertSourcesSplitTheLookups() throws {
        let sources = try XCTUnwrap(MonitorViewModel(metrics: try metrics(), locale: locale).expertSources)
        XCTAssertEqual(sources.parts.map(\.label), ["VRAM", "Peer GPU", "CPU"])
        // hit 0.517, peer 0.459 → 28.0% / 45.9% / 26.1%
        XCTAssertEqual(sources.parts.map(\.text), ["28.0%", "45.9%", "26.1%"])
        XCTAssertEqual(sources.parts.map(\.fraction).reduce(0, +), 1, accuracy: 0.0001)
    }

    func testNoExpertSourcesWithoutAHitRate() {
        XCTAssertNil(MonitorViewModel(metrics: Metrics(), locale: locale).expertSources)
    }

    // MARK: - requests

    func testRequestDetailNamesTheIDAndEndpoint() throws {
        let vm = MonitorViewModel(metrics: try metrics(), locale: locale)
        let facts = try XCTUnwrap(vm.requests.first?.detail.facts)
        XCTAssertEqual(facts.first { $0.key == "ID" }?.value, "r_1638")
        XCTAssertEqual(facts.first { $0.key == "Endpoint" }?.value, "/v1/chat/completions")
    }

    // MARK: - about

    func testAboutForBasalt() throws {
        let about = AboutViewModel(
            metrics: try metrics(),
            baseURL: URL(string: "http://192.168.1.82:8082/#stats"),
            health: try decode(Health.self, "basalt_health"),
            locale: locale
        )
        func fact(_ label: String) -> String? {
            about.sections.flatMap(\.facts).first { $0.label == label }?.value
        }
        XCTAssertEqual(fact("Engine"), "Basalt v0.0.1")
        XCTAssertEqual(fact("Weights"), "NVFP4")
        XCTAssertEqual(fact("Parallel requests"), "2 slots")
        XCTAssertEqual(fact("Images"), "on", "from /health when /metrics does not say")
        XCTAssertEqual(fact("GPU"), "NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti, 32 GB")
        XCTAssertEqual(fact("NVIDIA driver"), "610.57.04")
        XCTAssertEqual(fact("CUDA"), "13.3")
        XCTAssertEqual(fact("OpenAI base URL"), "http://192.168.1.82:8082/v1", "no #stats")
        XCTAssertNil(about.repositoryURL)
    }

    // MARK: - sampled sparklines

    func testSampledHistoryFillsOnlyWhatTheServerLeftOut() throws {
        var sampled = SampledHistory()
        let hw = try metrics().hardware
        for _ in 0..<(SampledHistory.capacity + 5) { sampled.record(hw) }
        let history = sampled.filling(try metrics().history)
        XCTAssertEqual(history.gpuUtil?.count, SampledHistory.capacity)
        XCTAssertEqual(history.gpuUtil?.last, 98)
        XCTAssertEqual(history.cpu?.last, 50.3)
        XCTAssertEqual(history.tokS?.count, 60, "the server's own series wins")
        XCTAssertEqual(history.tokS?.first, 62.61)
    }

    func testPollerSamplesAndFetchesSlots() async throws {
        let metricsData = try Fixtures.data("basalt_metrics_generating", testClass: Self.self)
        let slotsData = try Fixtures.data("basalt_slots", testClass: Self.self)
        let healthData = try Fixtures.data("basalt_health", testClass: Self.self)
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            let body = path.hasSuffix("/slots") ? slotsData : path.hasSuffix("/health") ? healthData : metricsData
            return (body, httpResponse(request.url!, 200))
        }
        let poller = MetricsPoller(client: StrataClient(baseURL: URL(string: "http://192.168.1.82:8082")!, transport: transport))
        await poller.pollOnce()
        await poller.pollOnce()
        XCTAssertEqual(poller.engine, .basalt)
        XCTAssertEqual(poller.slots.count, 2)
        XCTAssertEqual(poller.metrics?.history?.gpuUtil, [98, 98])
        XCTAssertTrue(transport.requests.contains { $0.url?.path == "/slots" })
    }

    // MARK: - client

    func testAFragmentInTheAddressIsDropped() {
        let client = StrataClient(baseURL: URL(string: "http://192.168.1.82:8082/#stats")!)
        XCTAssertEqual(client.request(path: "metrics")?.url?.absoluteString, "http://192.168.1.82:8082/metrics")
        XCTAssertEqual(
            client.request(path: "api/logs", query: [URLQueryItem(name: "after", value: "7")])?.url?.absoluteString,
            "http://192.168.1.82:8082/api/logs?after=7"
        )
    }

    // MARK: - logs

    func testLogFeedDecodesAndFilters() throws {
        let batch = try decode(LogBatch.self, "basalt_logs")
        let feed = LogFeed()
        feed.apply(batch)
        XCTAssertEqual(feed.lines.count, 6)
        XCTAssertEqual(feed.lines.first?.source, "srv")
        XCTAssertTrue(feed.lines.first?.message.hasPrefix("thinking:") == true)

        feed.filter = .warnings
        XCTAssertEqual(feed.shown.map(\.level), [.warn, .err])
        feed.filter = .errors
        XCTAssertEqual(feed.shown.map(\.level), [.err])
        feed.filter = .all
        feed.query = "TOK/S"
        XCTAssertEqual(feed.shown.count, 4, "case-insensitive text match")
    }

    func testLogFeedAppendsOnceAndStartsOverAfterARestart() throws {
        let feed = LogFeed()
        feed.apply(LogBatch(lines: [LogLine(id: 1, message: "a"), LogLine(id: 2, message: "b")], last: 2))
        feed.apply(LogBatch(lines: [LogLine(id: 2, message: "b"), LogLine(id: 3, message: "c")], last: 3))
        XCTAssertEqual(feed.lines.map(\.id), [1, 2, 3])

        feed.apply(LogBatch(lines: [LogLine(id: 1, message: "fresh")], last: 1))
        XCTAssertEqual(feed.lines.map(\.message), ["fresh"])
    }

    func testLogFeedKeepsTheNewestLines() {
        let feed = LogFeed()
        let many = (1...(LogFeed.maxLines + 20)).map { LogLine(id: $0, message: "\($0)") }
        feed.apply(LogBatch(lines: many, last: many.count))
        XCTAssertEqual(feed.lines.count, LogFeed.maxLines)
        XCTAssertEqual(feed.lines.first?.id, 21)
    }

    // MARK: - hover card

    func testHoverCardNamesBothStreams() throws {
        let card = HoverCard(
            metrics: try metrics(), status: .generating(tokS: 80.5), model: nil, lastUpdated: nil,
            slots: try slots(), locale: locale
        )
        XCTAssertEqual(card.pillText, "Generating · 2 streams")
        XCTAssertEqual(card.decode.text, "80.5")
        XCTAssertEqual(card.decode.caption, "40 + 40")
    }

    func testHoverCardWithoutAPhaseSaysGeneratingOnce() throws {
        let card = HoverCard(metrics: try metrics(), status: .generating(tokS: 80.5), model: nil, lastUpdated: nil, locale: locale)
        XCTAssertEqual(card.pillText, "Generating")
        XCTAssertEqual(card.decode.caption, "now")
    }
}

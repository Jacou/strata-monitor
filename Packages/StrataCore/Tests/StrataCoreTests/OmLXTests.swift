import XCTest
@testable import StrataCore

@MainActor
final class OmLXTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Fixtures.data(name, testClass: Self.self))
    }

    private func activity(_ name: String) throws -> OmLXActivity {
        try decode(OmLXActivity.self, name)
    }

    private func stats() throws -> OmLXStats {
        try decode(OmLXStats.self, "omlx_stats")
    }

    private func health() throws -> Health {
        try decode(Health.self, "omlx_health")
    }

    // MARK: - detection

    func testHealthDetectsOMLX() throws {
        let health = try health()
        XCTAssertEqual(health.engine, .omlx)
        XCTAssertTrue(health.isOK, "oMLX says healthy, not ok")
        XCTAssertEqual(health.model, "GLM-5.3-Flash-oQ4e-mtp", "default_model stands in for model")
        XCTAssertEqual(health.enginePool?.modelCount, 4)
        XCTAssertEqual(health.enginePool?.loadedCount, 1)
        XCTAssertEqual(health.loaded, true, "the pool's loaded count says a model is in")
    }

    /// The other two engines must not start reading as oMLX.
    func testDetectionLeavesStrataAndBasaltAlone() throws {
        XCTAssertEqual(try decode(Health.self, "health").engine, .strata)
        XCTAssertEqual(try decode(Health.self, "basalt_health").engine, .basalt)
    }

    func testEngineCapabilities() {
        XCTAssertFalse(ServerEngine.omlx.hasRunConfig)
        XCTAssertTrue(ServerEngine.omlx.hasLogs, "the app tails /admin/api/logs directly")
        XCTAssertTrue(ServerEngine.omlx.hasChat, "chat is on the same port and key as the admin API")
        XCTAssertFalse(ServerEngine.omlx.hasHardware, "no GPU, thermal, power, PCIe or CPU counters")
        XCTAssertTrue(ServerEngine.strata.hasChat)
        XCTAssertTrue(ServerEngine.strata.hasHardware)
        XCTAssertEqual(ServerEngine.omlx.name, "oMLX")
    }

    // MARK: - payloads

    func testActivityDecodes() throws {
        let activity = try activity("omlx_activity_generating")
        let models = try XCTUnwrap(activity.activeModels?.models)
        XCTAssertEqual(models.count, 1)
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(model.id, "DeepSeek-V4.1-Flash-1017-oQ2.5e-ngram-mtp")
        XCTAssertEqual(model.isLoading, false)
        XCTAssertEqual(activity.activeModels?.totalActiveRequests, 4)
        XCTAssertEqual(activity.activeModels?.totalWaitingRequests, 3)
        XCTAssertEqual(model.generating?.count, 2)
        XCTAssertEqual(model.prefilling?.count, 2)
        XCTAssertEqual(model.waiting?.count, 3)
    }

    func testPrefillAndGenerateFields() throws {
        let activity = try activity("omlx_activity_generating")
        let prefill = try XCTUnwrap(activity.activeModels?.models?.first?.prefilling?.first)
        XCTAssertNotNil(prefill.processed)
        XCTAssertNotNil(prefill.total)
        XCTAssertEqual(prefill.phase, "prefill")
        XCTAssertNotNil(prefill.promptTokens)

        let generate = try XCTUnwrap(activity.activeModels?.models?.first?.generating?.first)
        XCTAssertNotNil(generate.tokensPerSecond)
        XCTAssertNotNil(generate.lastActivityAgeSeconds)
        XCTAssertNotNil(generate.maxTokens)
        XCTAssertFalse(generate.isStalled)
    }

    func testStatsDecodes() throws {
        let stats = try stats()
        XCTAssertNotNil(stats.totalRequests)
        XCTAssertNotNil(stats.uptimeSeconds)
        XCTAssertEqual(stats.engines?["mlx"]?.name, "mlx")
        XCTAssertNotNil(stats.engines?["mlx"]?.version)
    }

    // MARK: - the adapter

    func testAdapterSumsLiveSpeeds() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"), stats: try stats())
        let metrics = snapshot.metrics()

        let expectedDecode = snapshot.generating.reduce(0) { $0 + ($1.tokensPerSecond ?? 0) }
        XCTAssertEqual(metrics.live?.tokS ?? 0, expectedDecode, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.live?.tokS ?? 0, 0)

        let expectedPrefill = snapshot.prefilling.reduce(0) { $0 + ($1.speed ?? 0) }
        XCTAssertEqual(metrics.live?.prefillTokSMean ?? 0, expectedPrefill, accuracy: 0.001)

        // Decoding wins over reading while both run.
        XCTAssertEqual(metrics.live?.state, .generating)
        XCTAssertEqual(metrics.live?.maxTokens, snapshot.generating.first?.maxTokens)
        XCTAssertEqual(metrics.engine?.model, snapshot.models.first?.id)
    }

    /// With work in flight the pill reports the speed; the queue is still on the card.
    func testQueueDoesNotHideTheSpeed() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"))
        let metrics = snapshot.metrics()
        XCTAssertNil(metrics.live?.queued, "a busy server does not lead with the queue")
        XCTAssertEqual(metrics.live?.queue?.count, 3)
        XCTAssertEqual(metrics.live?.queue?.first?.waitedS, snapshot.waiting.first?.elapsedSeconds)
        XCTAssertEqual(metrics.live?.queue?.first?.promptTokens, snapshot.waiting.first?.promptTokens)
    }

    func testSlotsMirrorTheInFlightRequests() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"))
        let slots = snapshot.slots()
        XCTAssertEqual(slots.count, 4, "2 decoding + 2 prefilling; waiting is not a lane")
        XCTAssertEqual(slots.filter { $0.state == .decoding }.count, 2)
        XCTAssertEqual(slots.filter { $0.state == .prefill }.count, 2)
        XCTAssertEqual(slots.filter { $0.isProcessing == true }.count, 4)
        XCTAssertEqual(slots.map(\.id), Array(0..<4))
        XCTAssertNil(slots.first?.nCtx, "no window until the journal arrives")
    }

    func testSlotsCardShowsEveryLane() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"), recent: recent)
        let slots = snapshot.slots()
        XCTAssertEqual(slots.count, 4)
        XCTAssertEqual(slots.compactMap(\.nCtx).first, 1_048_576)

        let model = MonitorViewModel(metrics: snapshot.metrics(), locale: locale, slots: slots, engine: .omlx)
        let card = try XCTUnwrap(model.slots)
        XCTAssertEqual(card.summary, "4 of 4 busy")
        XCTAssertEqual(card.note, "1M context each")
        XCTAssertEqual(card.rows.map(\.title), ["Slot 0", "Slot 1", "Slot 2", "Slot 3"])
        XCTAssertEqual(card.rows.filter { $0.isBusy }.count, 4)
    }

    func testIdleSlotsKeepTheirStatus() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_idle"), recent: recent)
        let slots = snapshot.slots()
        XCTAssertEqual(slots.count, 4)
        XCTAssertTrue(slots.allSatisfy { $0.isProcessing == false })

        let model = MonitorViewModel(metrics: snapshot.metrics(), locale: locale, slots: slots, engine: .omlx)
        let card = try XCTUnwrap(model.slots)
        XCTAssertEqual(card.summary, "0 of 4 busy")
        XCTAssertEqual(card.note, "1M context each")
        XCTAssertEqual(card.rows[0].contextText, "– / 1M")
    }

    func testRingFollowsTheBusiestSlot() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"), recent: recent)
        let model = MonitorViewModel(
            metrics: snapshot.metrics(), locale: locale, slots: snapshot.slots(), engine: .omlx
        )
        XCTAssertEqual(model.context.percentText, "0%")
        XCTAssertEqual(model.context.sub, "2.2k / 1M · slot 0")
    }

    func testRequestsCarryTheInFlightRows() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"))
        let rows = snapshot.metrics().requests ?? []
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.filter { ($0.decodeTokS ?? 0) > 0 }.count, 2)
        XCTAssertEqual(rows.filter { ($0.outputTokens ?? 0) > 0 }.count, 2)
    }

    // MARK: - the recent journal

    func testRecentDecodes() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let windows = try XCTUnwrap(recent.windows)
        XCTAssertEqual(windows["DeepSeek-V4.1-Flash-1017-oQ2.5e-ngram-mtp"], 1_048_576)
        XCTAssertEqual(windows["Qwen3.8-Flash-Next-Q8_0"], 262_144)
        XCTAssertEqual(recent.slots, 4, "scheduler.max_concurrent_requests")

        let rows = try XCTUnwrap(recent.requests)
        XCTAssertEqual(rows.count, 4)
        let newest = try XCTUnwrap(rows.first)
        XCTAssertEqual(newest.promptTokens, 97_480)
        XCTAssertEqual(newest.outputTokens, 601)
        XCTAssertEqual(newest.durationS ?? 0, 9.81, accuracy: 0.001)
        XCTAssertEqual(newest.tokS ?? 0, 74.3, accuracy: 0.001)
        XCTAssertEqual(newest.finish, "tool_calls")
        XCTAssertEqual(newest.ttftS ?? 0, 1.71, accuracy: 0.001)
        XCTAssertEqual(newest.contextUsed, 98_081)
        XCTAssertEqual(newest.contextWindow, 1_048_576)
    }

    func testRecentRowsComeFirstAndCarryTheirContext() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"), recent: recent)
        let rows = try XCTUnwrap(snapshot.metrics().requests)
        XCTAssertEqual(rows.count, 11, "4 finished + 7 in flight")

        let newest = try XCTUnwrap(rows.first)
        XCTAssertNotNil(newest.time, "a finished row has the log's timestamp")
        XCTAssertEqual(newest.finish, .toolCalls)
        XCTAssertEqual(newest.contextUsed, 98_081)
        XCTAssertEqual(newest.maxContext, 1_048_576)
        XCTAssertEqual(newest.decodeTokS ?? 0, 74.3, accuracy: 0.001)
        XCTAssertEqual(newest.durationS ?? 0, 9.81, accuracy: 0.001)

        // In-flight rows follow the journal, and still carry no time.
        XCTAssertNil(rows.last?.time)
        XCTAssertEqual(rows.last?.promptTokens, snapshot.waiting.last?.promptTokens)

        let model = MonitorViewModel(metrics: snapshot.metrics(), locale: locale, engine: .omlx)
        XCTAssertEqual(model.requests.first?.finishText, "Tool calls")
    }

    func testEngineContextWindowComesFromTheProxy() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"), recent: recent)
        XCTAssertEqual(snapshot.metrics().engine?.maxContext, 1_048_576)

        // Without the journal there is no window: the ring shows "–".
        let bare = OmLXSnapshot(activity: try activity("omlx_activity_generating"))
        XCTAssertNil(bare.metrics().engine?.maxContext)
    }

    func testContextRingFillsFromTheLastRequest() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_idle"), recent: recent)
        let model = MonitorViewModel(metrics: snapshot.metrics(), locale: locale, engine: .omlx)
        // The newest finished request read 97,480 + wrote 601 of a 1 M window: 9 %.
        XCTAssertEqual(model.context.percentText, "9%")
        XCTAssertEqual(model.context.sub, "98k / 1M")
        XCTAssertFalse(model.showsEngineBars, "oMLX has no expert cache or GPU temperature")
    }

    func testRequestSheetCarriesTheContext() throws {
        let recent = try decode(OmLXRecent.self, "omlx_recent")
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_idle"), recent: recent)
        let model = MonitorViewModel(metrics: snapshot.metrics(), locale: locale, engine: .omlx)
        let detail = try XCTUnwrap(model.requests.first?.detail)
        XCTAssertEqual(detail.facts.first { $0.key == "Context" }?.value, "98k / 1M")
    }

    func testTotalsAndSessionFromStats() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"), stats: try stats())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let metrics = snapshot.metrics(now: now)
        let totals = try XCTUnwrap(metrics.totals)
        XCTAssertEqual(totals.requests, snapshot.stats?.totalRequests)
        XCTAssertEqual(totals.outputTokens, snapshot.stats?.totalCompletionTokens)
        XCTAssertEqual(totals.reused, snapshot.stats?.totalCachedTokens)
        // `since` is worked back from the uptime.
        XCTAssertEqual(totals.since ?? 0, now.timeIntervalSince1970 - (snapshot.stats?.uptimeSeconds ?? 0), accuracy: 0.001)
        XCTAssertGreaterThan(totals.promptMs ?? 0, 0)
        XCTAssertGreaterThan(totals.decodeMs ?? 0, 0)

        let vm = MonitorViewModel(metrics: metrics, now: now, locale: locale, engine: .omlx)
        XCTAssertNotNil(vm.session)
    }

    func testRAMBarFromMemoryPressure() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_generating"))
        let metrics = snapshot.metrics()
        let pressure = snapshot.activity.activeModels?.memoryPressure
        XCTAssertEqual(metrics.hardware?.ramUsed, pressure?.currentBytes)
        XCTAssertEqual(metrics.hardware?.ramTotal, pressure?.hardBytes)

        let vm = MonitorViewModel(metrics: metrics, locale: locale, engine: .omlx)
        XCTAssertNotEqual(vm.ram.text, "–")
    }

    /// The queue card lists what waits while requests still run; the pill keeps the speed.
    func testQueueCardWhileRequestsRun() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_queued"))
        XCTAssertEqual(snapshot.activeCount, 2)
        XCTAssertEqual(snapshot.waitingCount, 4)
        let metrics = snapshot.metrics()
        XCTAssertEqual(metrics.live?.state, .generating)
        XCTAssertNil(metrics.live?.queued)

        let vm = MonitorViewModel(metrics: metrics, locale: locale, slots: snapshot.slots(), engine: .omlx)
        let queue = try XCTUnwrap(vm.queue)
        XCTAssertEqual(queue.summary, "4 waiting")
        XCTAssertEqual(queue.rows.count, 3, "the card lists the first three")
        XCTAssertEqual(queue.rows.first?.waitedText, "1.8 s")
        XCTAssertEqual(queue.rows.first?.promptText, "2,141 tokens")
        XCTAssertEqual(queue.more, "+ 1 more")
        XCTAssertNotNil(vm.slots, "2 running is more than one slot")
    }

    func testIdleActivity() throws {
        let snapshot = OmLXSnapshot(activity: try activity("omlx_activity_idle"), stats: try stats())
        let metrics = snapshot.metrics()
        XCTAssertEqual(metrics.live?.state, .idle)
        XCTAssertNil(metrics.live?.tokS)
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertTrue(snapshot.slots().isEmpty)
    }

    // MARK: - model swap

    func testLoadingBecomesItsOwnState() throws {
        let json = """
        {"active_models":{"models":[{"id":"M","is_loading":true,"loading_remaining_seconds_estimate":42,
          "active_requests":0,"waiting_requests":0,"prefilling":[],"generating":[],"waiting":[]}],
          "total_active_requests":0,"total_waiting_requests":0,
          "memory_pressure":{"current_bytes":1000,"hard_bytes":2000}}}
        """
        let activity = try JSONDecoder().decode(OmLXActivity.self, from: Fixtures.json(json))
        let snapshot = OmLXSnapshot(activity: activity)
        XCTAssertTrue(snapshot.isLoading)
        let metrics = snapshot.metrics()
        XCTAssertEqual(metrics.live?.state, .other("loading"))

        XCTAssertEqual(MetricsPoller.status(from: metrics, loaded: true), .modelLoading)
        XCTAssertEqual(MonitorStatus.modelLoading.text, "Loading model")
        XCTAssertEqual(MenuBarLabel.text(for: .modelLoading), "loading")
        XCTAssertNotEqual(MenuBarLabel.symbol(for: .modelLoading), MenuBarLabel.symbol(for: .modelUnloaded))
    }

    // MARK: - tiles

    func testOMLXShowsOnlyTheSpeedTile() throws {
        let metrics = OmLXSnapshot(activity: try activity("omlx_activity_generating")).metrics()
        let omLX = MonitorViewModel(metrics: metrics, locale: locale, engine: .omlx)
        XCTAssertEqual(omLX.metrics.map(\.kind), [.speed])

        // The same payload under Strata keeps the full grid (the values are dashes, not hidden).
        let strata = MonitorViewModel(metrics: metrics, locale: locale, engine: .strata)
        XCTAssertEqual(strata.metrics.count, MonitorViewModel.MetricKind.allCases.count)
    }

    /// oMLX sends no history at all, so the Speed tile's sparkline comes from the sampled polls.
    func testSpeedSparklineIsSampled() throws {
        var sampled = SampledHistory()
        for value in [50.0, 60.0, 70.0] {
            var live = Live()
            live.tokS = value
            live.prefillTokSMean = value * 2
            sampled.record(nil, live)
        }
        let history = sampled.filling(nil)
        XCTAssertEqual(history.tokS, [50, 60, 70])
        XCTAssertEqual(history.prefillTokSMean, [100, 120, 140])
    }

    // MARK: - the poll

    func testPollerReadsOMLXDirectlyWithTheKey() async throws {
        func body(_ name: String) throws -> String {
            try String(contentsOf: Fixtures.url(name, testClass: Self.self), encoding: .utf8)
        }
        let bodies: [String: String] = [
            "health": try body("omlx_health"),
            "activity": try body("omlx_activity_generating"),
            "stats": try body("omlx_stats"),
            "logs": try body("omlx_logs"),
            "models": try body("omlx_models"),
            "global-settings": try body("omlx_global_settings"),
            "usage": try body("omlx_usage_today"),
        ]

        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            guard let key = bodies.keys.first(where: { path.hasSuffix("/" + $0) }), let text = bodies[key] else {
                return (Data(#"{"error":"not found"}"#.utf8), httpResponse(request.url!, 404))
            }
            return (Data(text.utf8), httpResponse(request.url!, 200))
        }
        let client = StrataClient(baseURL: URL(string: "http://192.168.1.26:8000")!, apiKey: "main-key", transport: transport)
        let poller = MetricsPoller(client: client, interval: 0.05)
        poller.start()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, poller.metrics == nil || poller.omlxJournal.isEmpty {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        poller.stop()

        XCTAssertEqual(poller.engine, .omlx)
        XCTAssertGreaterThan(poller.metrics?.live?.tokS ?? 0, 0)
        XCTAssertEqual(poller.status, .generating(tokS: poller.metrics?.live?.tokS))
        XCTAssertEqual(poller.omlxSlots, 4, "from scheduler.max_concurrent_requests")
        XCTAssertEqual(poller.slots.count, 4)
        XCTAssertEqual(poller.omlxJournal.count, 2, "both Chat completion lines in the log tail")
        XCTAssertEqual(poller.omlxJournal.first?.outputTokens, 12, "newest first")
        XCTAssertEqual(poller.trendRequests.count, 2, "the trends card draws the journal")
        XCTAssertNotNil(poller.omlxUsage)
        XCTAssertNotNil(poller.omlxStats?.runtimeCache)
        XCTAssertEqual(poller.omlxScopedStats, poller.omlxStats, "session-wide is the same fetch")
        XCTAssertEqual(poller.chatModel, "DeepSeek-V4.1-Flash-1017-oQ2.5e-ngram-mtp", "the loaded model, not the default")

        let paths = transport.requests.compactMap { $0.url?.path }
        for path in ["activity", "stats", "logs", "models", "global-settings", "usage"] {
            XCTAssertTrue(paths.contains("/admin/api/" + path), path)
        }
        XCTAssertFalse(paths.contains("/admin/api/recent"), "no proxy endpoints")
        XCTAssertFalse(paths.contains("/metrics"), "oMLX has no /metrics")
        let admin = transport.requests.filter { $0.url?.path.hasPrefix("/admin/") == true }
        XCTAssertTrue(admin.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer main-key" })
    }

    func testPollerWithoutAKeySaysSo() async throws {
        let healthBody = try String(contentsOf: Fixtures.url("omlx_health", testClass: Self.self), encoding: .utf8)
        let transport = StubTransport { request in
            if request.url?.path == "/health" { return (Data(healthBody.utf8), httpResponse(request.url!, 200)) }
            return (Data(#"{"detail":"Not authenticated"}"#.utf8), httpResponse(request.url!, 401))
        }
        let poller = MetricsPoller(client: StrataClient(baseURL: URL(string: "http://192.168.1.26:8000")!, transport: transport))
        await poller.pollOnce()
        XCTAssertEqual(poller.engine, .omlx, "/health needs no key, so the engine is still known")
        XCTAssertEqual(poller.status, .unauthorized)
    }

    func testPollerTracksTheRememberedEngine() async throws {
        // An address last seen as oMLX opens as oMLX before /health answers.
        let base = URL(string: "http://192.168.1.26:8000")!
        UserDefaults.standard.set("omlx", forKey: "poller.engine.\(base.absoluteString)")
        defer { UserDefaults.standard.removeObject(forKey: "poller.engine.\(base.absoluteString)") }
        XCTAssertEqual(MetricsPoller.rememberedEngine(for: base), .omlx)
    }
}

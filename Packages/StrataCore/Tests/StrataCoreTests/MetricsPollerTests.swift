import XCTest
@testable import StrataCore

@MainActor
final class MetricsPollerTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.10:8081")!

    private func settle(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func waitUntil(_ body: () -> Bool, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if body() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return body()
    }

    private func makePoller(_ transport: some HTTPTransport, interval: TimeInterval = 0.05) -> MetricsPoller {
        MetricsPoller(client: StrataClient(baseURL: base, apiKey: "k", transport: transport), interval: interval)
    }

    // MARK: - polling

    func testPollsAndPublishes() async throws {
        let transport = StubTransport.responding(#"{"live":{"state":"generating","tok_s":91.4},"time":1}"#)
        let poller = makePoller(transport)
        poller.start()

        let gotMetrics = await waitUntil { poller.metrics != nil }
        XCTAssertTrue(gotMetrics)
        XCTAssertEqual(poller.metrics?.live?.tokS, 91.4)
        XCTAssertEqual(poller.status, .generating(tokS: 91.4))
        XCTAssertEqual(poller.status.text, "Generating · 91.4 tok/s")
        XCTAssertNotNil(poller.lastUpdated)
        XCTAssertNil(poller.lastError)

        let firstCount = transport.requests.count
        XCTAssertTrue(firstCount >= 1)
        let polledAgain = await waitUntil { transport.requests.count > firstCount }
        XCTAssertTrue(polledAgain, "it should keep polling")

        poller.stop()
    }

    func testDecodesTheRealFixture() async throws {
        let data = try Fixtures.data("metrics_idle", testClass: type(of: self))
        let transport = StubTransport.respondingData(data)
        let poller = makePoller(transport)
        poller.start()

        let gotMetrics = await waitUntil { poller.metrics?.requests?.count == 12 }
        XCTAssertTrue(gotMetrics)
        XCTAssertEqual(poller.status, .idle)
        XCTAssertEqual(poller.status.text, "Idle")
        poller.stop()
    }

    // MARK: - failures

    func testThreeFailuresShowUnreachable() async throws {
        let transport = StubTransport.failing(URLError(.cannotConnectToHost))
        let poller = makePoller(transport)
        poller.start()

        let gaveUp = await waitUntil { poller.status == .unreachable }
        XCTAssertTrue(gaveUp)
        XCTAssertGreaterThanOrEqual(poller.consecutiveFailures, 3)
        XCTAssertEqual(poller.lastError, .unreachable)
        XCTAssertNil(poller.metrics)
        XCTAssertEqual(poller.status.text, "Server not reachable")
        poller.stop()
    }

    func testAFirstFailureKeepsThePreviousPill() async throws {
        let transport = StubTransport.status(503)
        let poller = makePoller(transport, interval: 0.4)
        poller.start()
        // one failure only
        let sawFailure = await waitUntil { poller.consecutiveFailures == 1 }
        XCTAssertTrue(sawFailure)
        XCTAssertEqual(poller.status, .unknown)
        XCTAssertEqual(poller.lastError, .http(503))
        poller.stop()
    }

    func testUnauthorizedShowsAPIKeyNeeded() async throws {
        let transport = StubTransport.status(401)
        let poller = makePoller(transport)
        poller.start()

        let sawKeyProblem = await waitUntil { poller.status == .unauthorized }
        XCTAssertTrue(sawKeyProblem)
        XCTAssertEqual(poller.status.text, "API key needed")
        XCTAssertEqual(poller.lastError, .unauthorized)
        XCTAssertEqual(poller.consecutiveFailures, 0)  // a 401 is not a reachability failure
        poller.stop()
    }

    func testStaleMetricsSurviveAFailedPoll() async throws {
        let good = Data(#"{"live":{"state":"idle"},"time":1}"#.utf8)
        let health = Data(#"{"status":"ok"}"#.utf8)
        let url = URL(string: "http://192.168.1.10:8081/metrics")!
        let metricsCalls = CallCounter()
        // /health always answers; /metrics works every other time.
        let transport = StubTransport { request in
            if request.url?.path.hasSuffix("health") == true { return (health, httpResponse(url, 200)) }
            if metricsCalls.next() % 2 == 0 { throw URLError(.timedOut) }
            return (good, httpResponse(url, 200))
        }
        let poller = makePoller(transport)
        poller.start()

        let kept = await waitUntil { poller.metrics != nil && poller.consecutiveFailures >= 1 }
        XCTAssertTrue(kept)
        XCTAssertNotNil(poller.metrics)
        XCTAssertNotEqual(poller.status, .unreachable)  // one failure is not enough
        poller.stop()
    }

    // MARK: - foreground / background

    func testPollingPausesWhenInactive() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let poller = makePoller(transport)
        poller.start()

        let polled = await waitUntil { transport.requests.count >= 2 }
        XCTAssertTrue(polled)

        poller.setActive(false)
        await settle(0.2)
        let countWhilePaused = transport.requests.count
        await settle(0.4)
        XCTAssertEqual(transport.requests.count, countWhilePaused, "no polling while inactive")

        poller.setActive(true)
        let resumed = await waitUntil { transport.requests.count > countWhilePaused }
        XCTAssertTrue(resumed)
        poller.stop()
    }

    // MARK: - "Show all"

    func testShowAllSwitchesTheQuery() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let poller = makePoller(transport)
        poller.setAllRequests(true)
        poller.start()

        let askedForAll = await waitUntil {
            transport.requests.contains {
                (queryItems(of: $0) ?? []).contains { $0.name == "requests" && $0.value == "all" }
            }
        }
        XCTAssertTrue(askedForAll)

        poller.setAllRequests(false)
        let stopped = await waitUntil { transport.requests.last?.url?.query == nil }
        XCTAssertTrue(stopped)
        poller.stop()
    }

    func testUpdateClientPointsAtTheNewServer() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let poller = makePoller(StubTransport.responding(#"{"time":1}"#))
        poller.start()
        await settle(0.15)
        poller.stop()

        poller.update(client: StrataClient(baseURL: URL(string: "http://10.0.0.5:8081")!, transport: transport))
        let asked = await waitUntil { !transport.requests.isEmpty }
        XCTAssertTrue(asked)
        XCTAssertEqual(transport.requests.first?.url?.host, "10.0.0.5")
        poller.stop()
    }

    // MARK: - the pill, mirroring render()

    func testStatusFromPayload() throws {
        func status(_ json: String) -> MonitorStatus {
            MetricsPoller.status(from: try! JSONDecoder().decode(Metrics.self, from: Data(json.utf8)))
        }
        XCTAssertEqual(status(#"{"live":{"state":"idle"}}"#), .idle)
        XCTAssertEqual(status("{}"), .idle)
        XCTAssertEqual(status(#"{"live":{"state":"reading","prompt_read":664,"prompt_total":53262}}"#), .reading(percent: 1))
        XCTAssertEqual(status(#"{"live":{"state":"reading","prompt_read":26631,"prompt_total":53262}}"#), .reading(percent: 50))
        XCTAssertEqual(status(#"{"live":{"state":"reading"}}"#), .reading(percent: nil))
        XCTAssertEqual(status(#"{"live":{"state":"generating","tok_s":111.2}}"#), .generating(tokS: 111.2))
        XCTAssertEqual(status(#"{"live":{"state":"generating","queued":2,"tok_s":111.2}}"#), .queued(2))
        XCTAssertEqual(status(#"{"live":{"state":"idle","queued":3}}"#), .queued(3))
        XCTAssertEqual(status(#"{"live":{"state":"warming"}}"#), .idle)
    }

    // MARK: - /health cadence and the model load state

    func testHealthIsPolledEveryTenMetricsPolls() async throws {
        let transport = RoutingTransport(
            health: #"{"status":"ok","loaded":true}"#,
            metrics: #"{"live":{"state":"idle"},"time":1}"#
        )
        let poller = makePoller(transport, interval: 0.01)
        poller.start()

        let healthFirst = await waitUntil { transport.paths.contains("/health") }
        XCTAssertTrue(healthFirst, "the first poll also asks /health")

        let settled = await waitUntil { transport.paths.filter { $0.hasSuffix("metrics") }.count >= 21 }
        XCTAssertTrue(settled)
        let healthPolls = transport.paths.filter { $0.hasSuffix("health") }.count
        let metricsPolls = transport.paths.filter { $0.hasSuffix("metrics") }.count
        let expected = (metricsPolls + 9) / 10
        XCTAssertLessThanOrEqual(healthPolls, expected + 1, "one /health per ten /metrics, got \(healthPolls) of \(metricsPolls)")
        XCTAssertGreaterThanOrEqual(healthPolls, expected - 1, "one /health per ten /metrics, got \(healthPolls) of \(metricsPolls)")
        XCTAssertEqual(poller.health?.loaded, true)
        poller.stop()
    }

    func testAFailedHealthPollKeepsTheLastAnswer() async throws {
        let transport = RoutingTransport(health: "", healthStatus: 503, metrics: #"{"live":{"state":"idle"},"time":1}"#)
        let poller = makePoller(transport, interval: 0.01)
        poller.start()

        let polled = await waitUntil { poller.metrics != nil }
        XCTAssertTrue(polled)
        // The pill is published at the end of a poll, after /health has been tried.
        let settled = await waitUntil { poller.status == MonitorStatus.idle }
        XCTAssertTrue(settled, "a 503 from /health must not spoil the pill")
        XCTAssertNil(poller.health, "a 503 from /health is not a model state")
        poller.stop()
    }

    func testUnloadedModelShowsItsOwnPill() async throws {
        let transport = RoutingTransport(
            health: #"{"status":"ok","loaded":false}"#,
            metrics: #"{"live":{"state":"idle"},"time":1}"#
        )
        let poller = makePoller(transport, interval: 0.01)
        poller.start()

        let sawIt = await waitUntil { poller.status == .modelUnloaded }
        XCTAssertTrue(sawIt)
        XCTAssertEqual(poller.status.text, "Model unloaded")
        poller.stop()
    }

    func testStatusFromHealthLoadState() {
        let idle = try! JSONDecoder().decode(Metrics.self, from: Data(#"{"live":{"state":"idle"}}"#.utf8))
        XCTAssertEqual(MetricsPoller.status(from: idle, loaded: false), .modelUnloaded)
        XCTAssertEqual(MetricsPoller.status(from: idle, loaded: true), .idle)
        XCTAssertEqual(MetricsPoller.status(from: idle, loaded: nil), .idle, "no /health yet: assume the ordinary idle case")

        let busy = try! JSONDecoder().decode(Metrics.self, from: Data(#"{"live":{"state":"generating","tok_s":80}}"#.utf8))
        XCTAssertEqual(MetricsPoller.status(from: busy, loaded: false), .generating(tokS: 80),
                       "a request in flight means the model is resident")

        let queued = try! JSONDecoder().decode(Metrics.self, from: Data(#"{"live":{"state":"idle","queued":2}}"#.utf8))
        XCTAssertEqual(MetricsPoller.status(from: queued, loaded: false), .queued(2))
    }

    func testStatusText() {
        XCTAssertEqual(MonitorStatus.unknown.text, "Connecting…")
        XCTAssertEqual(MonitorStatus.idle.text, "Idle")
        XCTAssertEqual(MonitorStatus.reading(percent: 42).text, "Reading prompt · 42%")
        XCTAssertEqual(MonitorStatus.reading(percent: nil).text, "Reading prompt")
        XCTAssertEqual(MonitorStatus.generating(tokS: nil).text, "Generating · – tok/s")
        XCTAssertEqual(MonitorStatus.queued(12).text, "12 queued")
        XCTAssertEqual(MonitorStatus.modelUnloaded.text, "Model unloaded")
        XCTAssertEqual(MonitorStatus.unauthorized.text, "API key needed")
        XCTAssertEqual(MonitorStatus.unreachable.text, "Server not reachable")
    }

    // MARK: - the trends fetch (metrics?requests=all)

    func testRefreshTrendsFetchesEveryKeptRequest() async throws {
        let url = base
        let transport = StubTransport { request in
            let all = URLComponents(url: request.url ?? url, resolvingAgainstBaseURL: false)?.queryItems?
                .contains(URLQueryItem(name: "requests", value: "all")) ?? false
            let body = all
                ? #"{"requests":[{"time":1,"decode_tok_s":90},{"time":2,"decode_tok_s":91},{"time":3,"decode_tok_s":92}]}"#
                : #"{"live":{"state":"idle"},"requests":[{"time":3,"decode_tok_s":92}]}"#
            return (Data(body.utf8), httpResponse(url, 200))
        }
        let poller = makePoller(transport)

        await poller.refreshTrends()
        XCTAssertEqual(poller.trendRequests.count, 3)
        XCTAssertEqual(poller.trendRequests.map(\.decodeTokS), [90, 91, 92])
        XCTAssertNotNil(poller.trendsUpdated)
        XCTAssertEqual(transport.requests.first?.url?.query, "requests=all")

        // The 1 s poll stays on the ordinary payload: the card only needs a fresh series every 30 s.
        await poller.pollOnce()
        XCTAssertEqual(poller.metrics?.requests?.count, 1)
        XCTAssertNil(transport.requests.last?.url?.query)
    }

    func testRefreshTrendsKeepsTheChartWhenTheFetchFails() async throws {
        let data = try Fixtures.data("metrics_idle", testClass: type(of: self))
        let poller = makePoller(StubTransport.respondingData(data))
        await poller.refreshTrends()
        let before = poller.trendRequests
        let updatedBefore = poller.trendsUpdated
        XCTAssertFalse(before.isEmpty)

        poller.update(client: StrataClient(baseURL: base, apiKey: "k", transport: StubTransport.failing(URLError(.timedOut))))
        await poller.refreshTrends()

        XCTAssertEqual(poller.trendRequests, before, "a failed trends fetch must not blank the chart")
        XCTAssertEqual(poller.trendsUpdated, updatedBefore)
    }

    // MARK: - backoff

    private func failing() -> StubTransport {
        StubTransport { _ in throw URLError(.cannotConnectToHost) }
    }

    func testNoBackoffWithoutAPolicy() async throws {
        let poller = makePoller(failing(), interval: 0.05)
        poller.start()
        let failed = await waitUntil { poller.consecutiveFailures >= 4 }
        XCTAssertTrue(failed)
        XCTAssertEqual(poller.currentDelay, 0.05, accuracy: 0.0001)
        XCTAssertFalse(poller.isPaused)
        poller.stop()
    }

    func testBackoffDoublesUpToTheCeiling() {
        let poller = MetricsPoller(
            client: StrataClient(baseURL: base, apiKey: "k", transport: failing()),
            interval: 5,
            backoff: BackoffPolicy(maxInterval: 60, pauseAfterAttemptsAtMax: 3)
        )
        XCTAssertEqual(poller.currentDelay, 5)
        var delays: [TimeInterval] = []
        for _ in 1...7 {
            poller.recordFailureForTesting()
            delays.append(poller.currentDelay)
        }
        XCTAssertEqual(delays, [5, 10, 20, 40, 60, 60, 60])
        XCTAssertEqual(poller.attemptsAtMax, 3)
        XCTAssertTrue(poller.isPaused, "three misses at the ceiling stop the loop")
        XCTAssertEqual(poller.status, .unreachable)
    }

    func testResumeForgetsTheFailuresAndPollsAgain() async throws {
        let gate = CallCounter()      // 0 = the server is down; the test opens it after the pause
        let counter = CallCounter()
        let transport = StubTransport { request in
            _ = counter.next()
            if gate.count == 0 { throw URLError(.cannotConnectToHost) }
            let body = Data(#"{"live":{"state":"idle"},"time":1}"#.utf8)
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let poller = MetricsPoller(
            client: StrataClient(baseURL: base, apiKey: "k", transport: transport),
            interval: 0.01,
            backoff: BackoffPolicy(maxInterval: 0.02, pauseAfterAttemptsAtMax: 2)
        )
        poller.start()
        let paused = await waitUntil { poller.isPaused }
        XCTAssertTrue(paused)
        let countWhenPaused = counter.count
        await settle(0.1)
        XCTAssertEqual(counter.count, countWhenPaused, "a paused poller makes no requests")

        _ = gate.next()               // the server is back
        poller.resume()
        XCTAssertFalse(poller.isPaused)
        XCTAssertEqual(poller.consecutiveFailures, 0)
        let recovered = await waitUntil { poller.status == .idle }
        XCTAssertTrue(recovered)
        poller.stop()
    }

    func testInactiveStopsTheLoopAndWakeResumesAPausedOne() async throws {
        let poller = MetricsPoller(
            client: StrataClient(baseURL: base, apiKey: "k", transport: failing()),
            interval: 0.01,
            backoff: BackoffPolicy(maxInterval: 0.02, pauseAfterAttemptsAtMax: 1)
        )
        poller.start()
        let paused = await waitUntil { poller.isPaused }
        XCTAssertTrue(paused)
        poller.setActive(false)
        XCTAssertFalse(poller.isActive)
        poller.setActive(true)
        XCTAssertFalse(poller.isPaused, "a wake gives a paused poller one fresh try")
        poller.stop()
    }
}

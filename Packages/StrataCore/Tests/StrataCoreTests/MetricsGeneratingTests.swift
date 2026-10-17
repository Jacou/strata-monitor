import XCTest
@testable import StrataCore

/// The busy-state capture: `live` fully populated, GPUs working, and nulls inside the history series.
final class MetricsGeneratingTests: XCTestCase {
    private var metrics: Metrics!

    override func setUpWithError() throws {
        metrics = try Fixtures.metrics(named: "metrics_generating", testClass: type(of: self))
    }

    func testLiveGenerating() throws {
        let live = try XCTUnwrap(metrics.live)
        XCTAssertEqual(live.state, .generating)
        XCTAssertEqual(live.queued, 0)
        XCTAssertEqual(live.phase, "thinking")
        XCTAssertEqual(live.promptTokens, 4_891)
        XCTAssertNil(live.promptRead)    // null while generating
        XCTAssertNil(live.promptTotal)
        XCTAssertEqual(live.generated, 1)
        XCTAssertEqual(live.maxTokens, 32_768)
        XCTAssertEqual(live.elapsedS, 3.3)
        XCTAssertEqual(live.tokS, 4.0)
        XCTAssertEqual(live.tokSMean, 61.8)
        XCTAssertEqual(live.prefillTokSMean, 469.9)
        XCTAssertEqual(live.tokSWindowS, 2.0)
    }

    func testPillForAGeneratingServer() {
        let status = MetricsPoller.status(from: metrics)
        XCTAssertEqual(status, .generating(tokS: 4.0))
        XCTAssertEqual(status.text, "Generating · 4.0 tok/s")
    }

    func testRequests() throws {
        let requests = try XCTUnwrap(metrics.requests)
        XCTAssertEqual(requests.count, 12)
        XCTAssertEqual(metrics.requestsKept, 226)
        XCTAssertTrue(requests.allSatisfy { $0.finish == .stop })

        let first = try XCTUnwrap(requests.first)
        XCTAssertEqual(first.time, 1_792_199_514.3071606)
        XCTAssertEqual(first.durationS, 2.2)
        XCTAssertEqual(first.promptTokens, 3_275)
        XCTAssertEqual(first.reused, 2_780)
        XCTAssertEqual(first.outputTokens, 102)
        XCTAssertEqual(first.promptRead, 495)
        XCTAssertEqual(first.promptMs, 1_220.9)
        XCTAssertEqual(first.decodeMs, 948.3)
        XCTAssertEqual(first.decodeTokS, 107.6)
        XCTAssertEqual(first.hitRate, 0.915)
        XCTAssertEqual(first.pcieShare, 0.036)
        XCTAssertEqual(first.draftsOffered, 76)
        XCTAssertEqual(first.draftsAccepted, 69)
        XCTAssertNil(first.projection)
    }

    func testConversationCache() throws {
        let cache = try XCTUnwrap(metrics.conversationCache)
        XCTAssertEqual(cache.enabled, true)
        XCTAssertEqual(cache.parked, 1)
        XCTAssertEqual(cache.bytes, 1_729_089_144)
        XCTAssertEqual(cache.parks, 64)
        XCTAssertEqual(cache.restores, 26)
        XCTAssertEqual(cache.lastEvent, "restored")
        XCTAssertEqual(cache.lastTokens, 2_546)
        XCTAssertEqual(cache.lastAt, 1_792_199_519.5809786)
        XCTAssertEqual(cache.requests, 226)
        XCTAssertEqual(cache.requestsReused, 191)
        XCTAssertEqual(cache.reusedTokens, 9_543_736)
        XCTAssertEqual(cache.promptTokens, 9_863_817)
        XCTAssertEqual(cache.lastReused, 2_780)
        XCTAssertEqual(cache.lastPrompt, 3_275)
    }

    func testTotals() throws {
        let totals = try XCTUnwrap(metrics.totals)
        XCTAssertEqual(totals.requests, 226)
        XCTAssertEqual(totals.promptTokens, 9_863_817)
        XCTAssertEqual(totals.reused, 9_543_736)
        XCTAssertEqual(totals.outputTokens, 157_201)
        XCTAssertEqual(totals.promptMs, 422_697.59999999974)
        XCTAssertEqual(totals.decodeMs, 1_542_108.3999999994)
        XCTAssertEqual(totals.draftsOffered, 136_531)
        XCTAssertEqual(totals.draftsAccepted, 100_813)
    }

    func testHardwareWhileGenerating() throws {
        let hardware = try XCTUnwrap(metrics.hardware)
        XCTAssertEqual(hardware.gpuUtil, 50)
        XCTAssertEqual(hardware.gpuTemp, 43)
        XCTAssertEqual(hardware.gpuPower, 114.581)
        XCTAssertEqual(hardware.gpuPcieGen, 4)      // the link has ramped up
        XCTAssertEqual(hardware.gpuPcieGenMax, 4)
        XCTAssertEqual(hardware.gpuPcieRxMb, 35_423.197265625)
        XCTAssertEqual(hardware.gpuPcieTxMb, 2_901.7333984375)
        XCTAssertEqual(hardware.cpu, 6.6)
        XCTAssertEqual(hardware.diskReadMb, 0.03960689349471982)
        XCTAssertEqual(hardware.tokS, 0)            // the sample lags the live request
        XCTAssertEqual(hardware.prefillTokSMean, 531.8)
        XCTAssertTrue(hardware.isMultiGPU)

        let gpus = try XCTUnwrap(hardware.gpus)
        XCTAssertEqual(gpus.count, 2)
        XCTAssertEqual(gpus[0].util, 0)             // one card is doing the work
        XCTAssertEqual(gpus[1].util, 100)
        XCTAssertEqual(gpus[1].temp, 43)
        XCTAssertEqual(gpus[1].power, 65.917)
    }

    func testHistorySeries() throws {
        let history = try XCTUnwrap(metrics.history)
        for series in [history.tokS, history.prefillTokSMean, history.gpuUtil, history.gpuMemUsed,
                       history.gpuTemp, history.gpuPower, history.gpuPcieRxMb, history.cpu,
                       history.ramUsed, history.diskReadMb] {
            XCTAssertEqual(series?.count, 60)
        }

        // prefill_tok_s_mean carries nulls mid-series: they become 0 so the sparkline still draws
        XCTAssertEqual(history.prefillTokSMean?[53], 0)
        XCTAssertEqual(history.prefillTokSMean?[55], 0)
        XCTAssertEqual(history.prefillTokSMean?[57], 0)
        XCTAssertEqual(history.prefillTokSMean?[58], 0)
        XCTAssertEqual(history.prefillTokSMean?[59], 531.8)

        XCTAssertEqual(history.tokS?[54], 104.19)
        XCTAssertEqual(history.tokS?[56], 107.39)
        XCTAssertEqual(history.gpuUtil?[54], 51)
        XCTAssertEqual(history.gpuUtil?[55], 79.5)
        XCTAssertEqual(history.gpuUtil?[59], 50)
        XCTAssertEqual(history.gpuTemp?[58], 45)
        XCTAssertEqual(history.gpuPcieRxMb?[59], 35_423.2)
        XCTAssertEqual(history.ramUsed?[59], 57_141_690_368)
        XCTAssertEqual(history.diskReadMb?[57], 60.82)
    }

    func testEngineIsTheSameServer() throws {
        let engine = try XCTUnwrap(metrics.engine)
        XCTAssertEqual(engine.model, "qwen3.8-flash-next-iq3_xxs")
        XCTAssertEqual(engine.cvec?.raw, "0")
        XCTAssertEqual(engine.pcieFrac?.raw, "0.18")
    }

    func testTime() throws {
        XCTAssertEqual(metrics.time, 1_792_199_519.7743175)
    }
}

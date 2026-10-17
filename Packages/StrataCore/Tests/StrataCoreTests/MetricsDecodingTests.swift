import XCTest
@testable import StrataCore

/// Decodes the real server payloads the fixtures captured.
final class MetricsDecodingTests: XCTestCase {
    private var metrics: Metrics!
    private var health: Health!

    override func setUpWithError() throws {
        metrics = try Fixtures.metrics(testClass: type(of: self))
        health = try Fixtures.health(testClass: type(of: self))
    }

    // MARK: - /health

    func testHealthFixture() throws {
        XCTAssertEqual(health.status, "ok")
        XCTAssertTrue(health.isOK)
        XCTAssertEqual(health.model, "qwen3.8-flash-next-iq3_xxs")
        XCTAssertEqual(health.maxContext, 262_144)
        XCTAssertEqual(health.images, true)
        XCTAssertEqual(health.apiKey, true)
        XCTAssertEqual(health.loaded, true)
        XCTAssertEqual(health.service, "strata")
    }

    // MARK: - /metrics: engine

    func testEngineFixture() throws {
        let engine = try XCTUnwrap(metrics.engine)
        XCTAssertEqual(engine.model, "qwen3.8-flash-next-iq3_xxs")
        XCTAssertEqual(engine.maxContext, 262_144)
        XCTAssertEqual(engine.context, 262_144)
        XCTAssertEqual(engine.images, true)
        XCTAssertEqual(engine.version, "0.1.40")
        XCTAssertEqual(engine.engine, "0.1.40")
        XCTAssertEqual(engine.kv, "int8")
        XCTAssertEqual(engine.kvResident, 32_768)
        XCTAssertEqual(engine.expertSlots, 11_432)
        XCTAssertEqual(engine.expertCacheMib, 18_714)
        XCTAssertEqual(engine.expertSlotsPrimary, 6_465)
        XCTAssertEqual(engine.expertCachePrimaryMib, 9_520)
        XCTAssertEqual(engine.spec, 6)
        XCTAssertEqual(engine.mtpMax, 4)
        XCTAssertEqual(engine.lookup, 3)
        XCTAssertEqual(engine.vramFreeMib, 340)
        XCTAssertEqual(engine.arenaMib, 40_925)
        XCTAssertEqual(engine.poolWorkers, 7)
        XCTAssertEqual(engine.tailRoleToken, -1)
        XCTAssertEqual(engine.vramElastic, 0)
        XCTAssertEqual(engine.conversationCacheMib, 3_072)
        XCTAssertEqual(engine.conversationCacheSlots, 4)
        XCTAssertEqual(engine.conversationCacheMinFreeMib, 4_096)

        // numeric-looking strings stay strings, and read as numbers too
        XCTAssertEqual(engine.cvec?.raw, "0")
        XCTAssertEqual(engine.cvec?.isBlank, true)
        XCTAssertEqual(engine.pcieFrac?.raw, "0.18")
        XCTAssertEqual(engine.pcieFrac?.doubleValue, 0.18)
        XCTAssertEqual(engine.specMinP?.raw, "0.50")
        XCTAssertEqual(engine.specMinP?.doubleValue, 0.5)
    }

    // MARK: - /metrics: live

    func testLiveIdleFixture() throws {
        let live = try XCTUnwrap(metrics.live)
        XCTAssertEqual(live.state, .idle)
        XCTAssertEqual(live.queued, 0)
        XCTAssertEqual(live.queuedCount, 0)
        XCTAssertNil(live.phase)
        XCTAssertNil(live.promptTokens)
        XCTAssertNil(live.promptRead)
        XCTAssertNil(live.promptTotal)
        XCTAssertNil(live.generated)
        XCTAssertNil(live.maxTokens)
        XCTAssertNil(live.elapsedS)
        XCTAssertNil(live.tokS)
        XCTAssertNil(live.tokSMean)
        XCTAssertNil(live.prefillTokSMean)
        XCTAssertNil(live.tokSWindowS)
    }

    // MARK: - /metrics: requests

    func testRequestsFixture() throws {
        let requests = try XCTUnwrap(metrics.requests)
        XCTAssertEqual(requests.count, 12)
        XCTAssertEqual(metrics.requestsKept, 224)
        XCTAssertEqual(metrics.latestRequest?.id, requests.first?.id)

        let first = try XCTUnwrap(requests.first)
        XCTAssertEqual(first.time, 1_792_199_293.3580594)
        XCTAssertEqual(first.durationS, 7.1)
        XCTAssertEqual(first.finish, .stop)
        XCTAssertEqual(first.promptTokens, 53_262)
        XCTAssertEqual(first.reused, 52_598)
        XCTAssertEqual(first.outputTokens, 572)
        XCTAssertEqual(first.promptTotal, 53_262)
        XCTAssertEqual(first.promptRead, 664)
        XCTAssertEqual(first.reasoningRecoveries, 0)
        XCTAssertEqual(first.reasoningRepeatCoverage, 0)
        XCTAssertEqual(first.engineGenerated, 572)
        XCTAssertEqual(first.promptMs, 1_922.4)
        XCTAssertEqual(first.decodeMs, 5_154.2)
        XCTAssertEqual(first.decodeTokS, 111.0)
        XCTAssertEqual(first.hitRate, 0.96)
        XCTAssertEqual(first.pcieShare, 0.012)
        XCTAssertEqual(first.ramBlobs, 0)
        XCTAssertEqual(first.fileBlobs, 0)
        XCTAssertEqual(first.fileMb, 0)
        XCTAssertEqual(first.draftsOffered, 510)
        XCTAssertEqual(first.draftsAccepted, 346)
        XCTAssertNil(first.projection)  // null in the payload

        // Identifiable: one stable id per request
        XCTAssertEqual(Set(requests.map(\.id)).count, requests.count)
    }

    // MARK: - /metrics: conversation cache, totals

    func testConversationCacheFixture() throws {
        let cache = try XCTUnwrap(metrics.conversationCache)
        XCTAssertEqual(cache.enabled, true)
        XCTAssertEqual(cache.budgetMib, 3_072)
        XCTAssertEqual(cache.slots, 4)
        XCTAssertEqual(cache.parked, 2)
        XCTAssertEqual(cache.bytes, 2_543_222_320)
        XCTAssertEqual(cache.evictions, 22)
        XCTAssertEqual(cache.parks, 63)
        XCTAssertEqual(cache.restores, 25)
        XCTAssertEqual(cache.lastEvent, "parked")
        XCTAssertEqual(cache.lastTokens, 52_871)
        XCTAssertEqual(cache.lastAt, 1_792_199_432.5690875)
        XCTAssertEqual(cache.requests, 224)
        XCTAssertEqual(cache.requestsReused, 189)
        XCTAssertEqual(cache.reusedTokens, 9_538_410)
        XCTAssertEqual(cache.promptTokens, 9_857_845)
        XCTAssertEqual(cache.lastReused, 52_598)
        XCTAssertEqual(cache.lastPrompt, 53_262)
    }

    func testTotalsFixture() throws {
        let totals = try XCTUnwrap(metrics.totals)
        XCTAssertEqual(totals.since, 1_792_161_083.8982737)
        XCTAssertEqual(totals.requests, 224)
        XCTAssertEqual(totals.promptTokens, 9_857_845)
        XCTAssertEqual(totals.reused, 9_538_410)
        XCTAssertEqual(totals.outputTokens, 157_017)
        XCTAssertEqual(totals.promptMs, 420_446.59999999974)
        XCTAssertEqual(totals.decodeMs, 1_540_305.5999999994)
        XCTAssertEqual(totals.draftsOffered, 136_380)
        XCTAssertEqual(totals.draftsAccepted, 100_687)
        XCTAssertEqual(totals.toolCallsFromReasoning, 2)
    }

    // MARK: - /metrics: hardware

    func testHardwareFixture() throws {
        let hardware = try XCTUnwrap(metrics.hardware)
        let gpus = try XCTUnwrap(hardware.gpus)
        XCTAssertEqual(gpus.count, 2)
        XCTAssertTrue(hardware.isMultiGPU)

        XCTAssertEqual(gpus[0].index, 0)
        XCTAssertEqual(gpus[0].util, 0)
        XCTAssertEqual(gpus[0].memUsed, 16_803_364_864)
        XCTAssertEqual(gpus[0].memTotal, 17_094_934_528)
        XCTAssertEqual(gpus[0].temp, 41)
        XCTAssertEqual(gpus[0].power, 14.426)

        XCTAssertEqual(gpus[1].index, 1)
        XCTAssertEqual(gpus[1].temp, 39)
        XCTAssertEqual(gpus[1].power, 13.791)

        XCTAssertEqual(hardware.gpuUtil, 0)
        XCTAssertEqual(hardware.gpuMemUsed, 33_711_587_328)
        XCTAssertEqual(hardware.gpuMemTotal, 34_189_869_056)
        XCTAssertEqual(hardware.gpuTemp, 41)
        XCTAssertEqual(hardware.gpuPower, 28.217)
        XCTAssertEqual(hardware.gpuPowerLimit, 500)
        XCTAssertEqual(hardware.gpuPcieGen, 1)
        XCTAssertEqual(hardware.gpuPcieGenMax, 4)
        XCTAssertEqual(hardware.gpuPcieWidth, 4)
        XCTAssertEqual(hardware.gpuPcieRxMb, 1.15625)
        XCTAssertEqual(hardware.gpuPcieTxMb, 1.59375)
        XCTAssertEqual(hardware.cpu, 0.9)
        XCTAssertEqual(hardware.ramUsed, 57_925_148_672)
        XCTAssertEqual(hardware.ramTotal, 65_189_642_240)
        XCTAssertEqual(hardware.diskReadMb, 0)
        XCTAssertEqual(hardware.diskWriteMb, 0.05719282506514655)
        XCTAssertEqual(hardware.tokS, 0)
        XCTAssertEqual(hardware.tokSMean, 0)
        XCTAssertEqual(hardware.prefillTokSMean, 0)
    }

    func testHardwareStaticFixture() throws {
        let hardware = try XCTUnwrap(metrics.hardwareStatic)
        XCTAssertEqual(hardware.gpuName, "NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti")
        XCTAssertEqual(hardware.gpuCount, 2)
        XCTAssertEqual(hardware.cpuName, "AMD Ryzen 7 5800X3D 8-Core Processor")
        XCTAssertEqual(hardware.cores, 8)
        XCTAssertEqual(hardware.threads, 16)
        XCTAssertEqual(hardware.psutil, true)
    }

    func testHistoryFixture() throws {
        let history = try XCTUnwrap(metrics.history)
        for series in [history.tokS, history.prefillTokSMean, history.gpuUtil, history.gpuMemUsed,
                       history.gpuTemp, history.gpuPower, history.gpuPcieRxMb, history.cpu,
                       history.ramUsed, history.diskReadMb] {
            XCTAssertEqual(series?.count, 60)
        }
        XCTAssertEqual(history.gpuPower?[3], 27.91)
        XCTAssertEqual(history.gpuPcieRxMb?[3], 10.41)
        XCTAssertEqual(history.cpu?[31], 1.5)
        XCTAssertEqual(history.diskReadMb?[55], 0.01)
        XCTAssertEqual(history.tokS?.allSatisfy { $0 == 0 }, true)
    }

    func testTimeFixture() throws {
        XCTAssertEqual(metrics.time, 1_792_199_432.5641336)
    }
}

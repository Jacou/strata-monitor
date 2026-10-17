import XCTest
@testable import StrataCore

/// The trends card's derivations: which value each series draws from a request, how the series is
/// ordered and trimmed, and what the card says when there is nothing to chart.
final class TrendsTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    /// A request with only what the three series read, newest-first payloads aside.
    private func request(
        time: Double,
        decodeTokS: Double? = nil,
        hitRate: Double? = nil,
        promptTokens: Double? = nil,
        reused: Double? = nil,
        promptMs: Double? = nil
    ) -> Request {
        var r = Request()
        r.time = time
        r.decodeTokS = decodeTokS
        r.hitRate = hitRate
        r.promptTokens = promptTokens
        r.reused = reused
        r.promptMs = promptMs
        return r
    }

    private lazy var three: [Request] = {
        [
            request(time: 300, decodeTokS: 100, hitRate: 0.9, promptTokens: 1_000, reused: 400, promptMs: 1_000),
            request(time: 200, decodeTokS: 120, hitRate: 0.8, promptTokens: 2_000, reused: 500, promptMs: 2_500),
            request(time: 100, decodeTokS: 90, hitRate: 0.75, promptTokens: 664, reused: 0, promptMs: 2_000),
        ]
    }()

    private func trends(_ series: Trends.Series, _ requests: [Request]? = nil) -> Trends {
        Trends(requests: requests ?? three, series: series, locale: locale)
    }

    // MARK: - the three series

    func testDecodeSeriesIsTheRequestsOwnSpeed() {
        let t = trends(.decode)
        XCTAssertEqual(t.points.map(\.value), [90, 120, 100])   // oldest on the left
        XCTAssertEqual(t.points.map(\.valueText), ["90.0", "120.0", "100.0"])
        XCTAssertEqual(Trends.value(for: three[0], series: .decode), 100)
    }

    func testHitRateSeriesTurnsTheFractionIntoAPercent() {
        let t = trends(.hitRate)
        XCTAssertEqual(t.points.map(\.value), [75, 80, 90])
        XCTAssertEqual(t.points.map(\.valueText), ["75.0%", "80.0%", "90.0%"])
    }

    /// A payload that already reports a percent is not multiplied again.
    func testHitRateSeriesAcceptsAPayloadThatAlreadySendsAPercent() {
        XCTAssertEqual(Trends.value(for: request(time: 1, hitRate: 96), series: .hitRate), 96)
        XCTAssertEqual(Trends.value(for: request(time: 1, hitRate: 0.96), series: .hitRate), 96)
    }

    /// (prompt_tokens − reused) / (prompt_ms / 1000), the web page's prefill rate.
    func testPrefillSeriesCountsOnlyWhatWasActuallyRead() {
        XCTAssertEqual(Trends.value(for: three[0], series: .prefill), 600)      // 600 tokens / 1 s
        XCTAssertEqual(Trends.value(for: three[1], series: .prefill), 600)      // 1 500 / 2.5 s
        XCTAssertEqual(Trends.value(for: three[2], series: .prefill), 332)      // 664 / 2 s
        XCTAssertEqual(trends(.prefill).points.map(\.value), [332, 600, 600])   // oldest on the left
    }

    /// Reused can exceed prompt tokens on a cached follow-up; the rate never goes negative.
    func testPrefillSeriesNeverGoesNegative() {
        XCTAssertEqual(Trends.value(for: request(time: 1, promptTokens: 100, reused: 400, promptMs: 1_000), series: .prefill), 0)
    }

    func testPrefillSeriesNeedsAPromptTime() {
        XCTAssertNil(Trends.value(for: request(time: 1, promptTokens: 100, reused: 0), series: .prefill))
        XCTAssertNil(Trends.value(for: request(time: 1, promptTokens: 100, reused: 0, promptMs: 0), series: .prefill))
    }

    // MARK: - ordering, trimming, hiding

    func testPointsAreOrderedOldestFirstWhateverThePayloadOrderIs() {
        let newestFirst = three                       // the payload is newest first
        let oldestFirst = Array(three.reversed())
        XCTAssertEqual(trends(.decode, newestFirst).points.map(\.time), [100, 200, 300])
        XCTAssertEqual(trends(.decode, oldestFirst).points.map(\.time), [100, 200, 300])
    }

    func testCardIsHiddenBelowThreeRequests() {
        XCTAssertTrue(trends(.decode, Array(three.prefix(2))).isHidden)
        XCTAssertTrue(trends(.decode, []).isHidden)
        XCTAssertFalse(trends(.decode).isHidden)
        XCTAssertEqual(Trends.minimumPoints, 3)
    }

    /// A series with too few *usable* points is hidden even when the requests are there.
    func testCardIsHiddenWhenTheSeriesHasNoValues() {
        let noSpeed = [request(time: 1, hitRate: 0.5), request(time: 2, hitRate: 0.6), request(time: 3, hitRate: 0.7)]
        XCTAssertTrue(trends(.decode, noSpeed).isHidden)
        XCTAssertFalse(trends(.hitRate, noSpeed).isHidden)
    }

    func testSeriesIsTrimmedToTheNewestPoints() {
        let many = (1...120).map { request(time: Double($0), decodeTokS: Double($0)) }
        let t = trends(.decode, many)
        XCTAssertEqual(t.points.count, Trends.maximumPoints)
        XCTAssertEqual(t.points.first?.value, 81)     // the oldest of the last 40
        XCTAssertEqual(t.points.last?.value, 120)
    }

    func testRequestsWithoutATimeAreDropped() {
        var untimed = Request()
        untimed.decodeTokS = 50
        let t = trends(.decode, three + [untimed])
        XCTAssertEqual(t.points.count, 3)
    }

    func testUnusableValuesAreDropped() {
        let t = trends(.decode, three + [request(time: 400, decodeTokS: Double.nan)])
        XCTAssertEqual(t.points.map(\.value), [90, 120, 100])
    }

    func testNegativeValuesAreClampedToZero() {
        XCTAssertEqual(Trends.value(for: request(time: 1, decodeTokS: -3), series: .decode), 0)
    }

    // MARK: - axis and captions

    func testHitRateAxisStopsAtOneHundred() {
        XCTAssertEqual(trends(.hitRate).ceiling, 100)
    }

    func testSpeedAxisLeavesHeadroomAboveTheHighestPoint() {
        XCTAssertEqual(trends(.decode).ceiling, 138)   // 120 × 1.15
        XCTAssertEqual(trends(.decode, []).ceiling, 1.15)   // an empty chart still needs a domain
    }

    func testRangeText() {
        let t = trends(.decode)
        XCTAssertTrue(t.rangeText.hasPrefix("3 requests · "))
        XCTAssertTrue(t.rangeText.contains("–"))      // a start and an end time
        XCTAssertEqual(trends(.decode, []).rangeText, "no requests yet")
    }

    func testSeriesLabelsAndUnits() {
        XCTAssertEqual(Trends.Series.allCases.map(\.label), ["Decode tok/s", "Expert hit rate %", "Prefill tok/s"])
        XCTAssertEqual(Trends.Series.decode.unit, "t/s")
        XCTAssertEqual(Trends.Series.hitRate.unit, "%")
        XCTAssertTrue(Trends.Series.decode.showsPoints)
        XCTAssertTrue(Trends.Series.prefill.showsPoints)
        XCTAssertFalse(Trends.Series.hitRate.showsPoints)
    }

    func testAxisStrideKeepsTheTimeLabelsReadable() {
        /// Three points spread over `span` seconds.
        func strideFor(_ span: Double) -> Int {
            trends(.decode, [
                request(time: 1_000, decodeTokS: 1),
                request(time: 1_000 + span / 2, decodeTokS: 2),
                request(time: 1_000 + span, decodeTokS: 3),
            ]).axisStrideMinutes
        }
        XCTAssertEqual(strideFor(3 * 60), 1)          // 3 minutes → every minute
        XCTAssertEqual(strideFor(9 * 60), 2)          // 9 minutes → every 2
        XCTAssertEqual(strideFor(2 * 3_600), 30)      // 2 hours → every half hour
        XCTAssertEqual(strideFor(24 * 3_600), 360)    // a day → every 6 hours
        XCTAssertEqual(trends(.decode, []).axisStrideMinutes, 1)
    }

    // MARK: - tapping the chart

    func testNearestPointMatchesTheTappedTime() {
        let t = trends(.decode)
        XCTAssertEqual(t.nearest(to: Date(timeIntervalSince1970: 101))?.value, 90)
        XCTAssertEqual(t.nearest(to: Date(timeIntervalSince1970: 289))?.value, 100)
        XCTAssertEqual(t.nearest(to: Date(timeIntervalSince1970: 199))?.value, 120)
        XCTAssertNil(trends(.decode, []).nearest(to: .now))
    }

    /// A tapped point carries the request's own id, which is what highlights its row in the list.
    func testPointIDIsTheRequestsID() {
        let t = trends(.decode)
        XCTAssertEqual(t.points.map(\.id), Array(three.reversed()).map(\.id), "oldest left, same ids")
    }

    // MARK: - against the real payload

    func testFixturePayloadCharts() throws {
        let metrics = try Fixtures.metrics(testClass: type(of: self))
        let requests = metrics.requests ?? []
        XCTAssertEqual(requests.count, 12)

        let decode = Trends(requests: requests, series: .decode, locale: locale)
        XCTAssertFalse(decode.isHidden)
        XCTAssertEqual(decode.points.count, 12)
        XCTAssertEqual(decode.points.map(\.value).max(), 117.5)
        XCTAssertTrue(decode.points.map(\.time).sorted() == decode.points.map(\.time), "oldest left")

        let hit = Trends(requests: requests, series: .hitRate, locale: locale)
        XCTAssertEqual(hit.points.map(\.value).max(), 97.2)   // 0.972 in the payload
        XCTAssertEqual(hit.ceiling, 100)

        // The 51 490-token request read all of it (nothing reused) in 23 186.8 ms.
        let prefill = Trends(requests: requests, series: .prefill, locale: locale)
        XCTAssertEqual(prefill.points.map(\.value).max() ?? 0, 2_220.7, accuracy: 0.1)
    }
}

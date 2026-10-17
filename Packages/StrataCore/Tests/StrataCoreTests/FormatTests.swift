import XCTest
@testable import StrataCore

/// The strings must match the web page's `fmt`, `gb`, `kfmt`, `ctxfmt`, `since`.
final class FormatTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    // MARK: - fmt

    func testFmt() {
        XCTAssertEqual(fmt(53_262, locale: locale), "53,262")
        XCTAssertEqual(fmt(1_000, locale: locale), "1,000")
        XCTAssertEqual(fmt(999, locale: locale), "999")
        XCTAssertEqual(fmt(0, locale: locale), "0")
        XCTAssertEqual(fmt(-1, locale: locale), "-1")
        XCTAssertEqual(fmt(111.0, 1, locale: locale), "111.0")
        XCTAssertEqual(fmt(110.55, 1, locale: locale), "110.6")
        XCTAssertEqual(fmt(0.9, locale: locale), "1")
        XCTAssertEqual(fmt(1.15625, 1, locale: locale), "1.2")
        XCTAssertEqual(fmt(28.217, 2, locale: locale), "28.22")
    }

    func testFmtMissing() {
        XCTAssertEqual(fmt(nil, locale: locale), notAvailable)
        XCTAssertEqual(fmt(Double.nan, 1, locale: locale), notAvailable)
        XCTAssertEqual(fmt(Double.infinity, locale: locale), notAvailable)
    }

    // MARK: - gb

    func testGb() {
        // binary GB, as Windows shows it
        XCTAssertEqual(gb(16_803_364_864, locale: locale), "15.6")
        XCTAssertEqual(gb(34_189_869_056, 0, locale: locale), "32")
        XCTAssertEqual(gb(1_073_741_824, locale: locale), "1.0")
        XCTAssertEqual(gb(0, locale: locale), "0.0")
        XCTAssertEqual(gb(2_543_222_320, locale: locale), "2.4")
        XCTAssertEqual(gb(nil, locale: locale), notAvailable)
    }

    // MARK: - kfmt / ctxfmt

    func testKfmt() {
        XCTAssertEqual(kfmt(999, locale: locale), "999")
        XCTAssertEqual(kfmt(1_000, locale: locale), "1.0k")
        XCTAssertEqual(kfmt(1_234, locale: locale), "1.2k")
        XCTAssertEqual(kfmt(9_999, locale: locale), "10.0k")
        XCTAssertEqual(kfmt(12_345, locale: locale), "12k")
        XCTAssertEqual(kfmt(53_262, locale: locale), "53k")
        XCTAssertEqual(kfmt(0, locale: locale), "0")
        XCTAssertEqual(kfmt(nil, locale: locale), notAvailable)
    }

    func testCtxfmt() {
        XCTAssertEqual(ctxfmt(32_768, locale: locale), "32K")
        XCTAssertEqual(ctxfmt(262_144, locale: locale), "256K")
        XCTAssertEqual(ctxfmt(4_096, locale: locale), "4K")
        XCTAssertEqual(ctxfmt(1_536, locale: locale), "1.5k")
        XCTAssertEqual(ctxfmt(1_500, locale: locale), "1.5k")
        XCTAssertEqual(ctxfmt(0, locale: locale), "0")
        XCTAssertEqual(ctxfmt(nil, locale: locale), notAvailable)
    }

    // MARK: - since

    func testSince() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(since(now.timeIntervalSince1970 - 5, now: now, locale: locale), "just now")
        XCTAssertEqual(since(now.timeIntervalSince1970 - 59, now: now, locale: locale), "just now")
        XCTAssertEqual(since(now.timeIntervalSince1970 - 60, now: now, locale: locale), "1 min ago")
        XCTAssertEqual(since(now.timeIntervalSince1970 - 600, now: now, locale: locale), "10 min ago")
        XCTAssertEqual(since(now.timeIntervalSince1970 - 3_599, now: now, locale: locale), "60 min ago")
        XCTAssertEqual(since(now.timeIntervalSince1970 - 3_600, now: now, locale: locale), "1.0 h ago")
        XCTAssertEqual(since(now.timeIntervalSince1970 - 7_200, now: now, locale: locale), "2.0 h ago")
        XCTAssertEqual(since(now.timeIntervalSince1970 + 10, now: now, locale: locale), "just now")  // clock skew
        XCTAssertEqual(since(nil, now: now, locale: locale), "")
        XCTAssertEqual(since(0, now: now, locale: locale), "")
    }

    // MARK: - percent

    func testFractionPercent() {
        XCTAssertEqual(fractionPercent(664, 53_262, locale: locale), "1%")
        XCTAssertEqual(fractionPercent(52_598, 53_262, locale: locale), "99%")
        XCTAssertEqual(fractionPercent(2, 4, locale: locale), "50%")
        XCTAssertEqual(fractionPercent(5, 0, locale: locale), "0%")
        XCTAssertEqual(fractionPercent(nil, 4, locale: locale), "0%")
        XCTAssertEqual(fractionPercent(4, nil, locale: locale), "0%")
    }

    // MARK: - uptime

    func testUptimeText() {
        XCTAssertEqual(uptimeText(0, locale: locale), "0 s")
        XCTAssertEqual(uptimeText(42.7, locale: locale), "42 s")
        XCTAssertEqual(uptimeText(59.9, locale: locale), "59 s")
        XCTAssertEqual(uptimeText(60, locale: locale), "1 min")
        XCTAssertEqual(uptimeText(750, locale: locale), "12 min")
        XCTAssertEqual(uptimeText(3_599, locale: locale), "59 min")
        XCTAssertEqual(uptimeText(3_600, locale: locale), "1 h 0 m")
        XCTAssertEqual(uptimeText(38_209, locale: locale), "10 h 36 m")
        XCTAssertEqual(uptimeText(86_400, locale: locale), "1 d 0 h")
        XCTAssertEqual(uptimeText(190_000, locale: locale), "2 d 4 h")
        XCTAssertEqual(uptimeText(nil, locale: locale), notAvailable)
        XCTAssertEqual(uptimeText(-1, locale: locale), notAvailable)
        XCTAssertEqual(uptimeText(.nan, locale: locale), notAvailable)
    }

    /// A non-en_US locale groups differently — the helpers follow the user, like the web page does.
    func testLocaleIsHonoured() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(fmt(53_262, locale: german), "53.262")
    }
}

import XCTest
import StrataCore
@testable import StrataCore

/// The caption beside the pill. It lives in `MonitorView`, so it stays with the app; the rest of
/// the Monitor chrome is tested in `StrataCoreTests`.
final class UpdatedCaptionTests: XCTestCase {
    func testUpdatedCaption() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 1_000_000 - 5)
        let old = Date(timeIntervalSince1970: 1_000_000 - 600)

        XCTAssertEqual(updatedCaption(status: .idle, lastUpdated: nil, now: now), "no data yet")
        XCTAssertEqual(updatedCaption(status: .idle, lastUpdated: recent, now: now), "updated just now")
        XCTAssertEqual(updatedCaption(status: .generating(tokS: 90), lastUpdated: old, now: now), "updated 10 min ago")
        XCTAssertEqual(updatedCaption(status: .unauthorized, lastUpdated: recent, now: now), "last data just now")
        XCTAssertEqual(updatedCaption(status: .unreachable, lastUpdated: old, now: now), "last data 10 min ago")
        XCTAssertEqual(updatedCaption(status: .unreachable, lastUpdated: nil, now: now), "no data yet")
    }
}

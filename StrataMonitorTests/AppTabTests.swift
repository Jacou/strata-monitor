import XCTest
@testable import StrataMonitor

/// The tab bar lives in the app, so its tests do too.
final class AppTabTests: XCTestCase {
    func testFirstLaunchOpensSettingsWhenNoKeyIsStored() {
        XCTAssertEqual(AppTab.initialTab(hasAPIKey: false), .settings)
        XCTAssertEqual(AppTab.initialTab(hasAPIKey: true), .monitor)
    }

    func testTabsHaveIcons() {
        XCTAssertEqual(AppTab.monitor.systemImage, "waveform.path.ecg")
        XCTAssertEqual(AppTab.chat.systemImage, "bubble.left.and.text.bubble.right")
        XCTAssertEqual(AppTab.config.systemImage, "slider.horizontal.3")
        XCTAssertEqual(AppTab.about.systemImage, "info.circle")
        XCTAssertEqual(AppTab.settings.systemImage, "gearshape")
        XCTAssertEqual(AppTab.allCases.map(\.label), ["Monitor", "Chat", "Config", "About", "Settings"])
    }

    /// `--tab=<name>` names a tab by its raw value, which is how screenshots land on Config.
    func testTabRawValuesMatchLaunchArguments() {
        XCTAssertEqual(AppTab(rawValue: "config"), .config)
        XCTAssertEqual(AppTab(rawValue: "chat"), .chat)
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["monitor", "chat", "config", "about", "settings"])
    }
}

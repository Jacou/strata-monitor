import SwiftUI

#if DEBUG
/// Debug-only launch arguments, so a screenshot can be taken without a hand on the display:
/// `--tab=about` (see `AppTab.initialTab`) and
/// `--scroll-to=resources | cache | trends | api | bottom`.
/// There is no `--rotate`: an iPad refuses programmatic orientation changes (UISceneErrorDomain
/// 101) and simctl cannot turn the device, so landscape has to be rotated by hand.
@MainActor
enum DebugLaunch {
    static var scrollTarget: String? {
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--scroll-to") {
            let parts = argument.split(separator: "=")
            return parts.count > 1 ? String(parts[1]) : "bottom"
        }
        return nil
    }

    /// Scrolls to `id` on launch when `--scroll-to` names it.
    static func scroll(_ proxy: ScrollViewProxy, to id: String, anchor: UnitPoint, after delay: TimeInterval = 0.6) {
        guard scrollTarget == id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    /// `--open-request` opens the first request's detail sheet: simctl cannot tap a row.
    static let opensRequestSheet = ProcessInfo.processInfo.arguments.contains("--open-request")

    /// `--open-config` opens the first run-config key's editor sheet, for the same reason;
    /// `--open-config=vram_reserve_mib` opens that key instead.
    static let opensConfigSheet = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--open-config") }
    static var configKeyToOpen: String? {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--open-config") }) else { return nil }
        let parts = argument.split(separator: "=")
        return parts.count > 1 ? String(parts[1]) : nil
    }

    /// `--select-trend` picks the newest charted request, which is what a tap on the chart does.
    static let selectsTrendPoint = ProcessInfo.processInfo.arguments.contains("--select-trend")

    /// `--ask="…"` asks that question on the Chat tab, since simctl cannot type in the composer.
    static var chatPrompt: String? {
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--ask=") {
            let value = String(argument.dropFirst(6))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// `--open-chat-settings` opens the chat's settings sheet on launch.
    static let opensChatSettings = ProcessInfo.processInfo.arguments.contains("--open-chat-settings")

    /// Runs `work` once a second until it reports success, so a debug action can wait for the
    /// first poll to bring a payload in.
    static func retryUntilOpened(attempts: Int = 8, _ work: @escaping @MainActor () -> Bool) {
        func step(_ remaining: Int) {
            guard remaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if work() { return }
                step(remaining - 1)
            }
        }
        step(attempts)
    }
}
#endif

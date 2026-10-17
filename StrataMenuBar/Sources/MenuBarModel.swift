import AppKit
import Foundation
import Observation
import StrataCore

/// The menu bar app's state: its own settings (its own Keychain entry), its poller, and whether
/// something is showing on screen — which decides how hard the poller pushes.
@Observable @MainActor
final class MenuBarModel {
    /// A separate Keychain service: the Mac app keeps its own server / key, the code is shared.
    static let keychainService = "com.jacou.StrataMenuBar"
    static let openInterval: TimeInterval = 1
    /// The cadence while nothing is on screen — the user's "Refresh when closed" choice.
    var closedInterval: TimeInterval { settings.closedPollInterval }

    let settings: AppSettings
    private(set) var poller: MetricsPoller?
    private(set) var isFastPolling = false

    private var observers: [any NSObjectProtocol] = []

    init() {
        settings = AppSettings(keychain: Keychain(service: Self.keychainService))
        #if DEBUG
        settings.adoptServerFromEnvironment()
        settings.adoptAPIKeyFromEnvironment()
        #endif
        reconnect()
        watchSleepAndLock()
    }

    /// True once the backoff gave up on the server; a click on the icon starts it again.
    var isPaused: Bool { poller?.isPaused ?? false }

    /// The click on the icon: forget the failures and poll now. Nothing happens unless paused.
    func resumeIfPaused() {
        guard isPaused else { return }
        poller?.resume()
    }

    /// No polling while the Mac sleeps or the screen is locked; one fresh try on wake / unlock.
    private func watchSleepAndLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let pause: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
        ]
        let resume: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
            (distributed, Notification.Name("com.apple.screenIsUnlocked")),
        ]
        for (center, name) in pause {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.poller?.setActive(false) }
            })
        }
        for (center, name) in resume {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.poller?.setActive(true) }
            })
        }
    }

    var isConfigured: Bool { poller != nil }
    var status: MonitorStatus { poller?.status ?? .unreachable }
    var metrics: Metrics? { poller?.metrics }
    var health: Health? { poller?.health }
    var lastUpdated: Date? { poller?.lastUpdated }
    var baseURL: URL? { settings.baseURL }
    var modelName: String? { metrics?.engine?.model ?? health?.model }

    /// The Monitor's derivations, reused whole by the popover.
    var monitor: MonitorViewModel? {
        metrics.map { MonitorViewModel(metrics: $0, modelLoaded: health?.loaded) }
    }

    /// The hover card's own, smaller derivation.
    var hoverCard: HoverCard {
        HoverCard(metrics: metrics, status: status, model: modelName, lastUpdated: lastUpdated, paused: isPaused)
    }

    /// 1 s while the hover card or the full popover is open, the chosen cadence otherwise. No scene
    /// phase on the Mac: the poller keeps running either way.
    func setFastPolling(_ fast: Bool) {
        guard fast != isFastPolling else { return }
        isFastPolling = fast
        poller?.setInterval(fast ? Self.openInterval : closedInterval)
    }

    /// The cadence setting changed: push it to the running poller without waiting for a card to open.
    func refreshCadence() {
        poller?.setInterval(isFastPolling ? Self.openInterval : closedInterval)
    }

    /// Settings changed: point at the new server / key and poll again at once.
    func reconnect() {
        poller?.stop()
        guard let client = settings.makeClient() else {
            poller = nil
            return
        }
        let next = MetricsPoller(
            client: client,
            interval: isFastPolling ? Self.openInterval : closedInterval,
            backoff: .menuBar
        )
        next.start()
        poller = next
    }
}


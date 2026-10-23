import AppKit
import Foundation
import Observation
import StrataCore

/// The menu bar app's state: its own settings (its own Keychain entry), one `ServerMonitorModel`
/// per configured server, and the sleep / lock watch that pauses all of them.
@Observable @MainActor
final class MenuBarModel {
    /// A separate Keychain service: the Mac app keeps its own servers / keys, the code is shared.
    static let keychainService = "com.jacou.StrataMenuBar"

    let settings: AppSettings
    /// One per configured server, in slot order. Each gets its own menu bar item.
    private(set) var servers: [ServerMonitorModel] = []
    /// Called after `servers` changed, so the app delegate can add or drop status items.
    @ObservationIgnored var onServersChanged: (() -> Void)?

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init() {
        settings = AppSettings(keychain: Keychain(service: Self.keychainService))
        #if DEBUG
        settings.adoptServerFromEnvironment()
        settings.adoptAPIKeyFromEnvironment()
        settings.adoptSecondaryFromEnvironment()
        #endif
        reconnect()
        watchSleepAndLock()
    }

    /// Settings changed: match the servers to the configured slots and point each at its current
    /// address / key, polling again at once.
    func reconnect() {
        let slots = settings.configuredSlots
        let kept = servers.filter { slots.contains($0.slot) }
        for dropped in servers where !slots.contains(dropped.slot) { dropped.stop() }
        servers = slots.map { slot in kept.first { $0.slot == slot } ?? ServerMonitorModel(slot: slot, settings: settings) }
        for server in servers { server.reconnect() }
        onServersChanged?()
    }

    /// The cadence setting changed: push it to every running poller.
    func refreshCadence() {
        for server in servers { server.refreshCadence() }
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
                MainActor.assumeIsolated { self?.setActive(false) }
            })
        }
        for (center, name) in resume {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setActive(true) }
            })
        }
    }

    private func setActive(_ active: Bool) {
        for server in servers { server.setActive(active) }
    }
}

/// One server's poller and what its menu bar item, hover card and popover read from it.
@Observable @MainActor
final class ServerMonitorModel {
    static let openInterval: TimeInterval = 1

    let slot: ServerSlot
    let settings: AppSettings
    private(set) var poller: MetricsPoller?
    private(set) var isFastPolling = false
    /// False while the Mac sleeps or is locked; a poller made meanwhile starts inactive too.
    private var isActive = true

    init(slot: ServerSlot, settings: AppSettings) {
        self.slot = slot
        self.settings = settings
    }

    /// The cadence while nothing is on screen — the user's "Refresh when closed" choice.
    var closedInterval: TimeInterval { settings.closedPollInterval }

    var displayName: String { settings.displayName(for: slot) }

    /// The few characters in front of the label that say which server this item is — only
    /// once there are two to tell apart. An unnamed server is "1" / "2": "Server 1" and "Server 2"
    /// would both cut down to "Server".
    var tag: String? {
        guard settings.hasMultipleServers else { return nil }
        let name = settings.name(for: slot)
        return name.isEmpty ? (slot == .primary ? "1" : "2") : MenuBarLabel.tag(for: name)
    }

    /// The name to put on the cards, or nil with a single server (nothing to tell apart).
    var cardName: String? { settings.hasMultipleServers ? displayName : nil }

    /// True once the backoff gave up on the server; a click on the icon starts it again.
    var isPaused: Bool { poller?.isPaused ?? false }

    /// The click on the icon: forget the failures and poll now. Nothing happens unless paused.
    func resumeIfPaused() {
        guard isPaused else { return }
        poller?.resume()
    }

    var isConfigured: Bool { poller != nil }
    var status: MonitorStatus { poller?.status ?? .unreachable }
    var metrics: Metrics? { poller?.metrics }
    var health: Health? { poller?.health }
    var lastUpdated: Date? { poller?.lastUpdated }
    var baseURL: URL? { settings.baseURL(for: slot) }
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

    func setActive(_ active: Bool) {
        isActive = active
        poller?.setActive(active)
    }

    /// Settings changed: point at the new server / key and poll again at once.
    func reconnect() {
        poller?.stop()
        guard let client = settings.makeClient(for: slot) else {
            poller = nil
            return
        }
        let next = MetricsPoller(
            client: client,
            interval: isFastPolling ? Self.openInterval : closedInterval,
            backoff: .menuBar
        )
        if isActive {
            next.start()
        } else {
            next.setActive(false)
        }
        poller = next
    }

    func stop() {
        poller?.stop()
        poller = nil
    }
}

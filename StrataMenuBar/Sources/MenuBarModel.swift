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

    init() {
        settings = AppSettings(keychain: Keychain(service: Self.keychainService))
        #if DEBUG
        settings.adoptServerFromEnvironment()
        settings.adoptAPIKeyFromEnvironment()
        #endif
        reconnect()
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
        HoverCard(metrics: metrics, status: status, model: modelName, lastUpdated: lastUpdated)
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
            interval: isFastPolling ? Self.openInterval : closedInterval
        )
        next.start()
        poller = next
    }
}


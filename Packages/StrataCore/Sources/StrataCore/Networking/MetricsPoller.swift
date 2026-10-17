import Foundation
import Observation

/// The Monitor's header pill. Mirrors `render()` in docs/reference-app.js.
public enum MonitorStatus: Equatable, Sendable {
    /// No payload yet.
    case unknown
    case idle
    /// "Reading prompt · 42%" (nil percent when the server has not reported a total).
    case reading(percent: Int?)
    case generating(tokS: Double?)
    case queued(Int)
    /// /health says the model is not resident yet; the first request will load it.
    case modelUnloaded
    /// 401 from /metrics.
    case unauthorized
    /// Three consecutive failures.
    case unreachable

    public var text: String {
        switch self {
        case .unknown: "Connecting…"
        case .idle: "Idle"
        case .reading(let percent): percent.map { "Reading prompt · \($0)%" } ?? "Reading prompt"
        case .generating(let tokS): "Generating · \(fmt(tokS, 1)) tok/s"
        case .queued(let count): "\(count) queued"
        case .modelUnloaded: "Model unloaded"
        case .unauthorized: "API key needed"
        case .unreachable: "Server not reachable"
        }
    }
}

/// Polls /metrics once a second while the app is in the foreground, like the web page does.
@Observable @MainActor
public final class MetricsPoller {
    public private(set) var metrics: Metrics?
    /// /health, refreshed every 10 polls: the model load state changes rarely, like the web page's mcpTick.
    public private(set) var health: Health?
    public private(set) var status: MonitorStatus = .unknown
    public private(set) var lastUpdated: Date?
    public private(set) var consecutiveFailures = 0
    public private(set) var lastError: StrataError?

    /// "Show all" on the recent-requests list: `metrics?requests=all`.
    public private(set) var allRequests = false

    /// The `metrics?requests=all` payload fetched for the trends card. It is deliberately kept
    /// apart from the 1 s poll: the card only needs a fresh series every 30 s.
    public private(set) var trendRequests: [Request] = []
    public private(set) var trendsUpdated: Date?

    /// False while `scenePhase != .active`: the loop idles instead of hitting the server.
    public private(set) var isActive = true

    private var client: StrataClient
    public private(set) var interval: TimeInterval
    private let failureLimit = 3
    private let healthEveryPolls = 10
    private var polls = 0
    private var task: Task<Void, Never>?

    public init(client: StrataClient, interval: TimeInterval = 1) {
        self.client = client
        self.interval = interval
    }

    // MARK: - lifecycle

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Called from the scene: polling pauses in the background, resumes in the foreground.
    public func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { start() }
    }

    /// Change the polling cadence. A menu bar app polls every second while its popover is open and
    /// backs off to five when it closes; the loop picks the new value up on its next sleep.
    public func setInterval(_ interval: TimeInterval) {
        guard interval > 0, interval != self.interval else { return }
        self.interval = interval
    }

    /// One `metrics?requests=all` fetch for the trends card. A failure keeps the series already on
    /// screen rather than blanking the chart.
    public func refreshTrends() async {
        do {
            let all = try await client.metrics(allRequests: true)
            trendRequests = all.requests ?? []
            trendsUpdated = .now
        } catch {
            // The 1 s loop reports what the server is doing; this one only has to keep the chart.
        }
    }

    /// Settings changed: point at the new server / key and poll again at once.
    public func update(client: StrataClient) {
        self.client = client
        consecutiveFailures = 0
        lastError = nil
        status = .unknown
        health = nil
        polls = 0
        if isActive { Task { await pollOnce() } }
    }

    public func setAllRequests(_ all: Bool) {
        guard all != allRequests else { return }
        allRequests = all
        if isActive { Task { await pollOnce() } }
    }

    // MARK: - one poll

    /// One poll. Public so the pull-to-refresh / "Test connection" path can reuse it.
    public func pollOnce() async {
        guard isActive else { return }
        do {
            let fetched = try await client.metrics(allRequests: allRequests)
            metrics = fetched
            consecutiveFailures = 0
            lastError = nil
            lastUpdated = .now
            polls += 1
            // Server state changes rarely: /health every 10th poll, like the web page's mcpTick.
            if polls % healthEveryPolls == 1 || health == nil {
                await pollHealth()
            }
            status = Self.status(from: fetched, loaded: health?.loaded)
        } catch let error as StrataError {
            record(error)
        } catch {
            record(StrataError.unreachable)
        }
    }

    /// A failed /health must not spoil the Monitor: keep the last answer and carry on.
    private func pollHealth() async {
        guard let health = try? await client.health() else { return }
        self.health = health
    }

    private func record(_ error: StrataError) {
        lastError = error
        switch error {
        case .unauthorized:
            // The web page shows "API key needed" on the first 401, without counting it.
            status = .unauthorized
        case .unreachable, .http, .decoding:
            consecutiveFailures += 1
            if consecutiveFailures >= failureLimit { status = .unreachable }
        }
    }

    /// The pill text the web page would show for this payload. `loaded` comes from /health:
    /// an idle engine with no model resident says so instead of claiming it is just idle.
    nonisolated static func status(from metrics: Metrics, loaded: Bool? = nil) -> MonitorStatus {
        let derived = liveStatus(from: metrics)
        if derived == .idle && loaded == false { return .modelUnloaded }
        return derived
    }

    private nonisolated static func liveStatus(from metrics: Metrics) -> MonitorStatus {
        let live = metrics.live
        if let queued = live?.queuedCount, queued > 0 { return .queued(queued) }
        switch live?.state {
        case .reading:
            let total = live?.promptTotal ?? 0
            guard total > 0 else { return .reading(percent: nil) }
            let percent = Int(((100 * (live?.promptRead ?? 0)) / total).rounded())
            return .reading(percent: percent)
        case .generating:
            return .generating(tokS: live?.tokS)
        case .idle, .other, .none:
            return .idle
        }
    }
}

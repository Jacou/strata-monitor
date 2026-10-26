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

/// How a poller slows down while the server does not answer: the delay doubles from the normal
/// interval up to `maxInterval`; after `pauseAfterAttemptsAtMax` failed tries at that ceiling it
/// stops altogether until `resume()` (a click on the menu bar icon, a wake from sleep, new settings).
/// nil `pauseAfterAttemptsAtMax` backs off but never stops.
public struct BackoffPolicy: Sendable, Equatable {
    public var maxInterval: TimeInterval
    public var pauseAfterAttemptsAtMax: Int?

    public init(maxInterval: TimeInterval, pauseAfterAttemptsAtMax: Int? = nil) {
        self.maxInterval = maxInterval
        self.pauseAfterAttemptsAtMax = pauseAfterAttemptsAtMax
    }

    /// The menu bar app's: 5 → 10 → 20 → 40 → 60 s, then three misses at 60 s and it stops.
    public static let menuBar = BackoffPolicy(maxInterval: 60, pauseAfterAttemptsAtMax: 3)
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
    /// Basalt with more than one slot: `GET /slots` from the same tick, empty otherwise.
    public private(set) var slots: [Slot] = []
    public private(set) var trendsUpdated: Date?

    /// False while `scenePhase != .active` (iOS) or the Mac is asleep / locked: the loop is stopped.
    public private(set) var isActive = true

    /// Set to slow down while the server is unreachable; nil polls at `interval` no matter what.
    public var backoff: BackoffPolicy?
    /// True once the backoff gave up: nothing is fetched until `resume()`.
    public private(set) var isPaused = false
    /// Failed tries made at the backoff ceiling since the last success.
    public private(set) var attemptsAtMax = 0

    private var client: StrataClient
    public private(set) var interval: TimeInterval
    private let failureLimit = 3
    private let healthEveryPolls = 10
    private var polls = 0
    private var task: Task<Void, Never>?
    /// The series the server does not keep itself (Basalt keeps only the two speeds), sampled here.
    private var sampled = SampledHistory()

    public init(client: StrataClient, interval: TimeInterval = 1, backoff: BackoffPolicy? = nil) {
        self.client = client
        self.interval = interval
        self.backoff = backoff
    }

    /// The wait before the next poll: `interval` normally, longer while the server keeps failing.
    public var currentDelay: TimeInterval {
        guard let backoff, consecutiveFailures > 0 else { return interval }
        let doubled = interval * pow(2, Double(consecutiveFailures - 1))
        return min(backoff.maxInterval, max(interval, doubled))
    }

    // MARK: - lifecycle

    public func start() {
        guard task == nil, !isPaused else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.pollOnce()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: UInt64(self.currentDelay * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Called from the scene (iOS) or on sleep / wake and lock / unlock (Mac): the loop stops
    /// while inactive and starts again — a paused poller gets one fresh try on wake.
    public func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            if isPaused { resume() } else { start() }
        } else {
            stop()
        }
    }

    /// Change the polling cadence. A menu bar app polls every second while its popover is open and
    /// backs off to five when it closes; the loop picks the new value up on its next sleep.
    public func setInterval(_ interval: TimeInterval) {
        guard interval > 0, interval != self.interval else { return }
        self.interval = interval
    }

    /// Forget the failures and poll again now. A no-op while not active (the Mac is asleep).
    public func resume() {
        isPaused = false
        consecutiveFailures = 0
        attemptsAtMax = 0
        lastError = nil
        guard isActive else { return }
        if task == nil { start() } else { Task { await pollOnce() } }
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

    /// Which engine answers, from the last `/health`. Until one comes in, the engine this address
    /// named last time, so a Basalt server opens in its own colours instead of flashing Strata's.
    public var engine: ServerEngine {
        health?.engine ?? Self.rememberedEngine(for: client.baseURL)
    }

    static func rememberedEngine(for baseURL: URL) -> ServerEngine {
        UserDefaults.standard.string(forKey: engineKey(baseURL)).flatMap(ServerEngine.init(rawValue:)) ?? .strata
    }

    private static func engineKey(_ baseURL: URL) -> String {
        "poller.engine.\(baseURL.absoluteString)"
    }

    /// Settings changed: point at the new server / key and poll again at once.
    public func update(client: StrataClient) {
        self.client = client
        status = .unknown
        health = nil
        slots = []
        sampled = SampledHistory()
        polls = 0
        resume()
    }

    /// Another server picked: like `update(client:)`, but nothing from the old server may stay on
    /// screen under the new one's name, so its payload and trend series go too.
    public func switchServer(to client: StrataClient) {
        metrics = nil
        lastUpdated = nil
        trendRequests = []
        trendsUpdated = nil
        update(client: client)
        if isActive { Task { await refreshTrends() } }
    }

    /// "Show all" reads the full list from the same one-off `metrics?requests=all` fetch the trends
    /// card uses (`trendRequests`), never from the 1 s loop: that payload is ten times the size.
    public func setAllRequests(_ all: Bool) {
        guard all != allRequests else { return }
        allRequests = all
        if all, isActive { Task { await refreshTrends() } }
    }

    // MARK: - one poll

    /// One poll. Public so the pull-to-refresh / "Test connection" path can reuse it.
    public func pollOnce() async {
        guard isActive, !isPaused else { return }
        do {
            var fetched = try await client.metrics(allRequests: false)
            sampled.record(fetched.hardware)
            fetched.history = sampled.filling(fetched.history)
            // The per-slot rows come from their own endpoint; one failing must not fail the tick.
            if fetched.live?.isMultiSlot == true {
                slots = (try? await client.slots()) ?? slots
            } else {
                slots = []
            }
            metrics = fetched
            consecutiveFailures = 0
            attemptsAtMax = 0
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
        UserDefaults.standard.set(health.engine.rawValue, forKey: Self.engineKey(client.baseURL))
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
            if let backoff, currentDelay >= backoff.maxInterval {
                attemptsAtMax += 1
                if let limit = backoff.pauseAfterAttemptsAtMax, attemptsAtMax >= limit {
                    pause()
                }
            }
        }
    }

    /// Tests drive the failure ladder without a clock.
    func recordFailureForTesting() {
        record(.unreachable)
    }

    /// The backoff gave up: stop the loop, keep the last data and the "not reachable" status.
    private func pause() {
        isPaused = true
        stop()
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

/// A rolling sample of the hardware series, one point per poll, for the sparklines a server does
/// not keep a history of. A series the server does send always wins.
struct SampledHistory: Sendable, Equatable {
    static let capacity = 60

    private(set) var gpuUtil: [Double] = []
    private(set) var gpuMemUsed: [Double] = []
    private(set) var gpuTemp: [Double] = []
    private(set) var gpuPower: [Double] = []
    private(set) var gpuPcieRxMb: [Double] = []
    private(set) var cpu: [Double] = []
    private(set) var ramUsed: [Double] = []
    private(set) var diskReadMb: [Double] = []

    mutating func record(_ hw: Hardware?) {
        func push(_ series: inout [Double], _ value: Double?) {
            series.append(value ?? 0)   // a gap draws as 0, like the server's own nulls
            if series.count > Self.capacity { series.removeFirst(series.count - Self.capacity) }
        }
        push(&gpuUtil, hw?.gpuUtil)
        push(&gpuMemUsed, hw?.gpuMemUsed)
        push(&gpuTemp, hw?.gpuTemp)
        push(&gpuPower, hw?.gpuPower)
        push(&gpuPcieRxMb, hw?.gpuPcieRxMb)
        push(&cpu, hw?.cpu)
        push(&ramUsed, hw?.ramUsed)
        push(&diskReadMb, hw?.diskReadMb)
    }

    func filling(_ history: History?) -> History {
        var out = history ?? History()
        func fill(_ keyPath: WritableKeyPath<History, [Double]?>, _ series: [Double]) {
            if out[keyPath: keyPath]?.isEmpty ?? true { out[keyPath: keyPath] = series }
        }
        fill(\.gpuUtil, gpuUtil)
        fill(\.gpuMemUsed, gpuMemUsed)
        fill(\.gpuTemp, gpuTemp)
        fill(\.gpuPower, gpuPower)
        fill(\.gpuPcieRxMb, gpuPcieRxMb)
        fill(\.cpu, cpu)
        fill(\.ramUsed, ramUsed)
        fill(\.diskReadMb, diskReadMb)
        return out
    }
}

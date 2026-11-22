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
    /// oMLX is swapping a model in (`is_loading`): the server is up, but nothing decodes yet.
    case modelLoading
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
        case .modelLoading: "Loading model"
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
    // MARK: oMLX state
    //
    // oMLX is read straight from its admin API with the main key. The live payload comes every
    // tick; everything else is slower to change and some of it costs the server more, so each has
    // its own cadence, counted in polls.

    /// `/admin/api/activity`, every poll.
    public private(set) var omlxActivity: OmLXActivity?
    /// Session counters for all models: cache tiers, engine versions, the Session card.
    public private(set) var omlxStats: OmLXStats?
    /// The counters the Serving card shows: the picked scope and model filter. The same as
    /// `omlxStats` when that is session-wide.
    public private(set) var omlxScopedStats: OmLXStats?
    public private(set) var omlxScope: OmLXStatsScope = .session
    /// nil or empty: every model.
    public private(set) var omlxModelFilter: String?
    public private(set) var omlxUsage: OmLXUsage?
    public private(set) var omlxUsageRange: OmLXUsageRange = .today
    public private(set) var omlxModelList: OmLXModelList?
    /// Finished requests read from the server log, newest first.
    public private(set) var omlxJournal: [OmLXFinishedRequest] = []
    /// `scheduler.max_concurrent_requests`: how many requests the engine runs side by side.
    public private(set) var omlxSlots: Int?
    /// The requests in flight last tick: one that is gone has finished, so its log line is due.
    private var omlxInFlight: Set<String> = []
    /// Log reads still owed after a request finished (this tick and the next, in case the line
    /// lands a moment after the activity entry goes).
    private var omlxLogsDue = 0
    private var omlxLogsSeeded = false
    private var omlxPrimed = false

    private let statsEveryPolls = 3
    private let slowEveryPolls = 60
    private let logsEveryPolls = 60
    nonisolated static let journalLimit = 50
    nonisolated static let logSeedLines = 1500
    nonisolated static let logTailLines = 400

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
        // oMLX has no per-request history endpoint; the sparklines come from the sampled polls.
        guard engine != .omlx else { return }
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
        resetOmLX()
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

    // MARK: - oMLX controls

    /// The Serving card's Session / All time switch: fetched at once, then on the usual cadence.
    public func setOmLXScope(_ scope: OmLXStatsScope) {
        guard scope != omlxScope else { return }
        omlxScope = scope
        omlxScopedStats = nil
        if isActive { Task { await refreshOmLXScopedStats() } }
    }

    /// The model filter on the Serving and Usage cards; nil for every model.
    public func setOmLXModelFilter(_ model: String?) {
        let picked = model?.isEmpty == true ? nil : model
        guard picked != omlxModelFilter else { return }
        omlxModelFilter = picked
        omlxScopedStats = nil
        if isActive {
            Task {
                await refreshOmLXScopedStats()
                await refreshOmLXUsage()
            }
        }
    }

    public func setOmLXUsageRange(_ range: OmLXUsageRange) {
        guard range != omlxUsageRange else { return }
        omlxUsageRange = range
        omlxUsage = nil
        if isActive { Task { await refreshOmLXUsage() } }
    }

    /// What the oMLX screen draws from: live state, session totals and the finished journal.
    public var omlxSnapshot: OmLXSnapshot? {
        guard let omlxActivity else { return nil }
        return OmLXSnapshot(activity: omlxActivity, stats: omlxStats, recent: omlxRecent)
    }

    /// The journal in the shape the Metrics adapter reads, each request given its model's window.
    private var omlxRecent: OmLXRecent {
        let windows = omlxModelList?.windows ?? [:]
        let requests = omlxJournal.map { item -> OmLXFinishedRequest in
            var item = item
            if item.contextWindow == nil, let model = item.model { item.contextWindow = windows[model] }
            return item
        }
        return OmLXRecent(requests: requests, windows: windows, slots: omlxSlots)
    }

    /// The model a chat request names. oMLX loads whatever is asked for, so the one already in
    /// memory is the better pick than the server's default.
    public var chatModel: String? {
        if engine == .omlx, let loaded = omlxActivity?.activeModels?.models?.first(where: { $0.isLoading != true })?.id {
            return loaded
        }
        return health?.model
    }

    private func resetOmLX() {
        omlxActivity = nil
        omlxStats = nil
        omlxScopedStats = nil
        omlxUsage = nil
        omlxModelList = nil
        omlxJournal = []
        omlxSlots = nil
        omlxInFlight = []
        omlxLogsDue = 0
        omlxLogsSeeded = false
        omlxPrimed = false
        // Another server need not have the model that was picked.
        omlxModelFilter = nil
    }

    // MARK: - one poll

    /// One poll. Public so the pull-to-refresh / "Test connection" path can reuse it.
    public func pollOnce() async {
        guard isActive, !isPaused else { return }
        // The engine comes from /health. A fresh address would otherwise be treated as Strata and
        // asked for /metrics, which oMLX does not serve, so the first tick asks /health first.
        if health == nil { await pollHealth() }
        if engine == .omlx {
            await pollOmLX()
            return
        }
        do {
            var fetched = try await client.metrics(allRequests: false)
            sampled.record(fetched.hardware, fetched.live)
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

    /// One oMLX tick: the live payload every time, the rest when it is due. Only the live payload
    /// failing fails the tick; a slower call that fails keeps what it had.
    private func pollOmLX() async {
        do {
            let activity = try await client.omlxActivity()
            omlxActivity = activity
            noteFinishedRequests(in: activity)

            // The first tick fetches everything once; after that a call that keeps failing (usage
            // history switched off, say) waits for its own cadence instead of retrying every second.
            let firstTick = !omlxPrimed
            omlxPrimed = true
            if firstTick || polls % statsEveryPolls == 0 {
                let before = omlxStats?.totalRequests
                omlxStats = (try? await client.omlxStats()) ?? omlxStats
                // A request too quick to show up in the live payload still bumps the counter.
                if let before, let after = omlxStats?.totalRequests, after > before { omlxLogsDue = max(omlxLogsDue, 1) }
                await refreshOmLXScopedStats()
            }
            if firstTick || polls % slowEveryPolls == 0 {
                omlxModelList = (try? await client.omlxModels()) ?? omlxModelList
                omlxSlots = (try? await client.omlxGlobalSettings())?.maxConcurrentRequests ?? omlxSlots
            }
            if firstTick || polls % slowEveryPolls == 0 {
                await refreshOmLXUsage()
            }
            if firstTick || omlxLogsDue > 0 || polls % logsEveryPolls == 0 {
                await refreshOmLXJournal()
            }

            let snapshot = OmLXSnapshot(activity: activity, stats: omlxStats, recent: omlxRecent)
            // The Trends card draws the finished journal: oMLX has no per-request history call.
            let finished = snapshot.finishedRows()
            if finished != trendRequests {
                trendRequests = finished
                trendsUpdated = .now
            }
            var fetched = snapshot.metrics()
            sampled.record(fetched.hardware, fetched.live)
            fetched.history = sampled.filling(fetched.history)
            slots = snapshot.slots()
            metrics = fetched
            consecutiveFailures = 0
            attemptsAtMax = 0
            lastError = nil
            lastUpdated = .now
            polls += 1
            if polls % healthEveryPolls == 1 || health == nil { await pollHealth() }
            status = Self.status(from: fetched, loaded: health?.loaded)
        } catch let error as StrataError {
            record(error)
        } catch {
            record(StrataError.unreachable)
        }
    }

    /// A request that was in flight last tick and is gone now has finished: its `Chat completion:`
    /// line is in the log, so the journal is read this tick and the next.
    private func noteFinishedRequests(in activity: OmLXActivity) {
        let models = activity.activeModels?.models ?? []
        var current = Set<String>()
        for model in models {
            for item in model.generating ?? [] { if let id = item.requestID { current.insert(id) } }
            for item in model.prefilling ?? [] { if let id = item.requestID { current.insert(id) } }
        }
        if !omlxInFlight.subtracting(current).isEmpty { omlxLogsDue = 2 }
        omlxInFlight = current
    }

    private func refreshOmLXScopedStats() async {
        let model = omlxModelFilter
        if omlxScope == .session, model == nil {
            omlxScopedStats = omlxStats
            return
        }
        omlxScopedStats = (try? await client.omlxStats(scope: omlxScope, model: model)) ?? omlxScopedStats
    }

    private func refreshOmLXUsage() async {
        omlxUsage = (try? await client.omlxUsage(range: omlxUsageRange, model: omlxModelFilter)) ?? omlxUsage
    }

    /// Reads the tail of `server.log` and keeps the finished requests it has not seen. The first
    /// read goes further back so the list is not empty on launch.
    private func refreshOmLXJournal() async {
        if omlxLogsDue > 0 { omlxLogsDue -= 1 }
        let lines = omlxLogsSeeded ? Self.logTailLines : Self.logSeedLines
        guard let tail = try? await client.omlxLogs(lines: lines) else { return }
        omlxLogsSeeded = true
        let found = OmLXLogParser.finishedRequests(in: tail.numberedLines.map { $0.text })
        omlxJournal = Self.merge(journal: omlxJournal, with: found)
    }

    /// New finished requests joined onto the ones already held: no duplicates, newest first, capped.
    nonisolated static func merge(journal: [OmLXFinishedRequest], with found: [OmLXFinishedRequest]) -> [OmLXFinishedRequest] {
        func key(_ item: OmLXFinishedRequest) -> String {
            "\(item.finishedAt ?? 0)|\(item.model ?? "")|\(item.outputTokens ?? 0)|\(item.promptTokens ?? 0)"
        }
        var seen = Set(journal.map(key))
        var out = journal
        for item in found where !seen.contains(key(item)) {
            seen.insert(key(item))
            out.append(item)
        }
        out.sort { ($0.finishedAt ?? 0) > ($1.finishedAt ?? 0) }
        if out.count > journalLimit { out.removeLast(out.count - journalLimit) }
        return out
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
        case .other(let raw):
            // The adapter marks a model swap as `other("loading")`: the server is up, no work runs.
            return raw == "loading" ? .modelLoading : .idle
        case .idle, .none:
            return .idle
        }
    }
}

/// A rolling sample of the series, one point per poll, for the sparklines a server does not keep a
/// history of. A series the server does send always wins. oMLX sends none at all, so the speeds
/// come from here too, not just the hardware.
struct SampledHistory: Sendable, Equatable {
    static let capacity = 60

    private(set) var tokS: [Double] = []
    private(set) var prefillTokSMean: [Double] = []
    private(set) var gpuUtil: [Double] = []
    private(set) var gpuMemUsed: [Double] = []
    private(set) var gpuTemp: [Double] = []
    private(set) var gpuPower: [Double] = []
    private(set) var gpuPcieRxMb: [Double] = []
    private(set) var cpu: [Double] = []
    private(set) var ramUsed: [Double] = []
    private(set) var diskReadMb: [Double] = []

    mutating func record(_ hw: Hardware?, _ live: Live? = nil) {
        func push(_ series: inout [Double], _ value: Double?) {
            series.append(value ?? 0)   // a gap draws as 0, like the server's own nulls
            if series.count > Self.capacity { series.removeFirst(series.count - Self.capacity) }
        }
        push(&tokS, live?.tokS)
        push(&prefillTokSMean, live?.prefillTokSMean)
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
        fill(\.tokS, tokS)
        fill(\.prefillTokSMean, prefillTokSMean)
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

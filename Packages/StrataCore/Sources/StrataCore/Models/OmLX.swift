import Foundation

// MARK: - /admin/api/activity

/// oMLX's live state: one entry per loaded model, with the requests it is reading or decoding.
/// Read from the stats proxy on `:8001` (`/admin/api/activity`), which needs no key.
public struct OmLXActivity: Decodable, Encodable, Sendable, Equatable {
    public var activeModels: OmLXActiveModels?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeModels = try? c.decode(OmLXActiveModels.self, forKey: .activeModels)
    }

    private enum CodingKeys: String, CodingKey {
        case activeModels = "active_models"
    }
}

public struct OmLXActiveModels: Decodable, Encodable, Sendable, Equatable {
    public var models: [OmLXModel]?
    /// Bytes the loaded model holds.
    public var modelMemoryUsed: Double?
    /// Bytes the server will admit before it refuses another model.
    public var modelMemoryMax: Double?
    public var memoryPressure: OmLXMemoryPressure?
    public var totalActiveRequests: Int?
    public var totalWaitingRequests: Int?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        models = c.decodeArray(OmLXModel.self, forKey: .models)
        modelMemoryUsed = c.decodeDouble(forKey: .modelMemoryUsed)
        modelMemoryMax = c.decodeDouble(forKey: .modelMemoryMax)
        memoryPressure = try? c.decode(OmLXMemoryPressure.self, forKey: .memoryPressure)
        totalActiveRequests = c.decodeInt(forKey: .totalActiveRequests)
        totalWaitingRequests = c.decodeInt(forKey: .totalWaitingRequests)
    }

    private enum CodingKeys: String, CodingKey {
        case models
        case modelMemoryUsed = "model_memory_used"
        case modelMemoryMax = "model_memory_max"
        case memoryPressure = "memory_pressure"
        case totalActiveRequests = "total_active_requests"
        case totalWaitingRequests = "total_waiting_requests"
    }
}

public struct OmLXMemoryPressure: Decodable, Encodable, Sendable, Equatable {
    public var enabled: Bool?
    public var currentBytes: Double?
    public var softBytes: Double?
    public var hardBytes: Double?
    public var pressureLevel: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.decodeBool(forKey: .enabled)
        currentBytes = c.decodeDouble(forKey: .currentBytes)
        softBytes = c.decodeDouble(forKey: .softBytes)
        hardBytes = c.decodeDouble(forKey: .hardBytes)
        pressureLevel = c.decodeString(forKey: .pressureLevel)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case currentBytes = "current_bytes"
        case softBytes = "soft_bytes"
        case hardBytes = "hard_bytes"
        case pressureLevel = "pressure_level"
    }
}

public struct OmLXModel: Decodable, Encodable, Sendable, Equatable {
    public var id: String?
    /// Bytes on disk, including parts offloaded to SSD: not the memory figure.
    public var estimatedSize: Double?
    /// Bytes actually resident in memory. Use this one.
    public var actualSize: Double?
    public var pinned: Bool?
    public var isLoading: Bool?
    public var loadingRemainingSeconds: Double?
    public var activeRequests: Int?
    public var waitingRequests: Int?
    public var idleSeconds: Double?
    public var waiting: [OmLXWaiting]?
    public var prefilling: [OmLXPrefill]?
    public var generating: [OmLXGenerate]?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeString(forKey: .id)
        estimatedSize = c.decodeDouble(forKey: .estimatedSize)
        actualSize = c.decodeDouble(forKey: .actualSize)
        pinned = c.decodeBool(forKey: .pinned)
        isLoading = c.decodeBool(forKey: .isLoading)
        loadingRemainingSeconds = c.decodeDouble(forKey: .loadingRemainingSeconds)
        activeRequests = c.decodeInt(forKey: .activeRequests)
        waitingRequests = c.decodeInt(forKey: .waitingRequests)
        idleSeconds = c.decodeDouble(forKey: .idleSeconds)
        waiting = c.decodeArray(OmLXWaiting.self, forKey: .waiting)
        prefilling = c.decodeArray(OmLXPrefill.self, forKey: .prefilling)
        generating = c.decodeArray(OmLXGenerate.self, forKey: .generating)
    }

    private enum CodingKeys: String, CodingKey {
        case id, pinned, waiting, prefilling, generating
        case estimatedSize = "estimated_size"
        case actualSize = "actual_size"
        case isLoading = "is_loading"
        case loadingRemainingSeconds = "loading_remaining_seconds_estimate"
        case activeRequests = "active_requests"
        case waitingRequests = "waiting_requests"
        case idleSeconds = "idle_seconds"
    }
}

/// The prompt being read. `elapsed` here; the other two entries call it `elapsed_seconds`.
public struct OmLXPrefill: Decodable, Encodable, Sendable, Equatable {
    public var requestID: String?
    public var processed: Double?
    /// Tokens to read, excluding the cached prefix.
    public var total: Double?
    public var speed: Double?
    public var eta: Double?
    public var elapsed: Double?
    public var phase: String?
    public var detail: String?
    public var promptTokens: Double?
    public var cachedTokens: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestID = c.decodeString(forKey: .requestID)
        processed = c.decodeDouble(forKey: .processed)
        total = c.decodeDouble(forKey: .total)
        speed = c.decodeDouble(forKey: .speed)
        eta = c.decodeDouble(forKey: .eta)
        elapsed = c.decodeDouble(forKey: .elapsed)
        phase = c.decodeString(forKey: .phase)
        detail = c.decodeString(forKey: .detail)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        cachedTokens = c.decodeDouble(forKey: .cachedTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case processed, total, speed, eta, elapsed, phase, detail
        case requestID = "request_id"
        case promptTokens = "prompt_tokens"
        case cachedTokens = "cached_tokens"
    }
}

/// Tokens being produced. `tokens_per_second` is live over ~3 s, not a lifetime average.
public struct OmLXGenerate: Decodable, Encodable, Sendable, Equatable {
    public var requestID: String?
    public var elapsedSeconds: Double?
    public var generatedTokens: Double?
    public var tokensPerSecond: Double?
    /// Above ~5 s means the request stalled.
    public var lastActivityAgeSeconds: Double?
    public var promptTokens: Double?
    public var maxTokens: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestID = c.decodeString(forKey: .requestID)
        elapsedSeconds = c.decodeDouble(forKey: .elapsedSeconds)
        generatedTokens = c.decodeDouble(forKey: .generatedTokens)
        tokensPerSecond = c.decodeDouble(forKey: .tokensPerSecond)
        lastActivityAgeSeconds = c.decodeDouble(forKey: .lastActivityAgeSeconds)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        maxTokens = c.decodeDouble(forKey: .maxTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case elapsedSeconds = "elapsed_seconds"
        case generatedTokens = "generated_tokens"
        case tokensPerSecond = "tokens_per_second"
        case lastActivityAgeSeconds = "last_activity_age_seconds"
        case promptTokens = "prompt_tokens"
        case maxTokens = "max_tokens"
    }

    /// The request has produced nothing for over five seconds.
    public var isStalled: Bool { (lastActivityAgeSeconds ?? 0) > 5 }
}

public struct OmLXWaiting: Decodable, Encodable, Sendable, Equatable {
    public var requestID: String?
    /// 1 is next.
    public var queuePosition: Int?
    public var elapsedSeconds: Double?
    public var promptTokens: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestID = c.decodeString(forKey: .requestID)
        queuePosition = c.decodeInt(forKey: .queuePosition)
        elapsedSeconds = c.decodeDouble(forKey: .elapsedSeconds)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case queuePosition = "queue_position"
        case elapsedSeconds = "elapsed_seconds"
        case promptTokens = "prompt_tokens"
    }
}

// MARK: - /admin/api/stats

/// Lifetime counters since the oMLX process started; they reset on restart.
public struct OmLXStats: Decodable, Encodable, Sendable, Equatable {
    public var totalTokensServed: Double?
    /// Prompt tokens served from the prefix cache.
    public var totalCachedTokens: Double?
    /// Percent of prompt tokens served from cache.
    public var cacheEfficiency: Double?
    public var totalPromptTokens: Double?
    public var totalCompletionTokens: Double?
    public var totalRequests: Double?
    /// Lifetime averages, not live speeds.
    public var avgPrefillTps: Double?
    public var avgGenerationTps: Double?
    public var uptimeSeconds: Double?
    public var engines: [String: OmLXEngineVersion]?
    public var activeModels: OmLXActiveModels?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalTokensServed = c.decodeDouble(forKey: .totalTokensServed)
        totalCachedTokens = c.decodeDouble(forKey: .totalCachedTokens)
        cacheEfficiency = c.decodeDouble(forKey: .cacheEfficiency)
        totalPromptTokens = c.decodeDouble(forKey: .totalPromptTokens)
        totalCompletionTokens = c.decodeDouble(forKey: .totalCompletionTokens)
        totalRequests = c.decodeDouble(forKey: .totalRequests)
        avgPrefillTps = c.decodeDouble(forKey: .avgPrefillTps)
        avgGenerationTps = c.decodeDouble(forKey: .avgGenerationTps)
        uptimeSeconds = c.decodeDouble(forKey: .uptimeSeconds)
        engines = try? c.decode([String: OmLXEngineVersion].self, forKey: .engines)
        activeModels = try? c.decode(OmLXActiveModels.self, forKey: .activeModels)
    }

    private enum CodingKeys: String, CodingKey {
        case engines
        case totalTokensServed = "total_tokens_served"
        case totalCachedTokens = "total_cached_tokens"
        case cacheEfficiency = "cache_efficiency"
        case totalPromptTokens = "total_prompt_tokens"
        case totalCompletionTokens = "total_completion_tokens"
        case totalRequests = "total_requests"
        case avgPrefillTps = "avg_prefill_tps"
        case avgGenerationTps = "avg_generation_tps"
        case uptimeSeconds = "uptime_seconds"
        case activeModels = "active_models"
    }
}

/// One MLX library oMLX is built on (`mlx`, `mlx-lm`, `mlx-vlm`…).
public struct OmLXEngineVersion: Decodable, Encodable, Sendable, Equatable {
    public var name: String?
    public var version: String?
    public var commit: String?
    public var url: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.decodeString(forKey: .name)
        version = c.decodeString(forKey: .version)
        commit = c.decodeString(forKey: .commit)
        url = c.decodeString(forKey: .url)
    }

    private enum CodingKeys: String, CodingKey { case name, version, commit, url }
}

// MARK: - /admin/api/recent

/// One finished request, recorded by the stats proxy from oMLX's own log line. `finish` is the
/// server's OpenAI-style reason ("tool_calls", "stop", …); `contextUsed` is prompt plus output.
public struct OmLXFinishedRequest: Decodable, Encodable, Sendable, Equatable {
    public var finishedAt: Double?
    public var model: String?
    public var promptTokens: Double?
    public var outputTokens: Double?
    public var durationS: Double?
    public var tokS: Double?
    public var finish: String?
    public var maxTokens: Double?
    public var ttftS: Double?
    public var contextUsed: Double?
    public var contextWindow: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finishedAt = c.decodeDouble(forKey: .finishedAt)
        model = c.decodeString(forKey: .model)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        outputTokens = c.decodeDouble(forKey: .outputTokens)
        durationS = c.decodeDouble(forKey: .durationS)
        tokS = c.decodeDouble(forKey: .tokS)
        finish = c.decodeString(forKey: .finish)
        maxTokens = c.decodeDouble(forKey: .maxTokens)
        ttftS = c.decodeDouble(forKey: .ttftS)
        contextUsed = c.decodeDouble(forKey: .contextUsed)
        contextWindow = c.decodeDouble(forKey: .contextWindow)
    }

    private enum CodingKeys: String, CodingKey {
        case model, finish
        case finishedAt = "finished_at"
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case durationS = "duration_s"
        case tokS = "tok_s"
        case maxTokens = "max_tokens"
        case ttftS = "ttft_s"
        case contextUsed = "context_used"
        case contextWindow = "context_window"
    }
}

/// The proxy's journal of finished requests, newest first, plus each model's context window.
public struct OmLXRecent: Decodable, Encodable, Sendable, Equatable {
    public var requests: [OmLXFinishedRequest]?
    public var windows: [String: Double]?
    /// How many requests the engine runs side by side (`scheduler.max_concurrent_requests`).
    public var slots: Int?
    public var generatedAt: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = c.decodeArray(OmLXFinishedRequest.self, forKey: .requests)
        // The proxy sends windows as JSON numbers; they may arrive as integers.
        if let doubles = try? c.decode([String: Double].self, forKey: .windows) {
            windows = doubles
        } else if let ints = try? c.decode([String: Int].self, forKey: .windows) {
            windows = ints.mapValues(Double.init)
        }
        slots = c.decodeInt(forKey: .slots)
        generatedAt = c.decodeDouble(forKey: .generatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case requests, windows, slots
        case generatedAt = "generated_at"
    }
}

// MARK: - adapting to the app's Metrics

/// One tick's worth of oMLX state: the live payload, the lifetime totals when they are due, and
/// the proxy's finished-request journal.
/// `metrics()` turns them into the `Metrics` the Monitor's derivation already understands, so no
/// screen has to know which engine answered.
public struct OmLXSnapshot: Sendable, Equatable {
    public var activity: OmLXActivity
    public var stats: OmLXStats?
    public var recent: OmLXRecent?

    public init(activity: OmLXActivity, stats: OmLXStats? = nil, recent: OmLXRecent? = nil) {
        self.activity = activity
        self.stats = stats
        self.recent = recent
    }

    public var models: [OmLXModel] { activity.activeModels?.models ?? [] }
    public var generating: [OmLXGenerate] { models.flatMap { $0.generating ?? [] } }
    public var prefilling: [OmLXPrefill] { models.flatMap { $0.prefilling ?? [] } }
    public var waiting: [OmLXWaiting] { models.flatMap { $0.waiting ?? [] } }

    /// A model is being swapped in: the server stays up, but nothing can decode meanwhile.
    public var isLoading: Bool { models.contains { $0.isLoading == true } }

    public var activeCount: Int {
        activity.activeModels?.totalActiveRequests ?? (generating.count + prefilling.count)
    }

    public var waitingCount: Int {
        activity.activeModels?.totalWaitingRequests ?? waiting.count
    }

    /// Total live decode speed: the sum of each request's own rate.
    public var decodeTokS: Double { generating.reduce(0) { $0 + ($1.tokensPerSecond ?? 0) } }

    /// Total live prefill speed.
    public var prefillTokS: Double { prefilling.reduce(0) { $0 + ($1.speed ?? 0) } }

    /// 0...1 of the hard memory ceiling, the figure the dashboard draws its bar from.
    public var memoryFraction: Double {
        guard let pressure = activity.activeModels?.memoryPressure,
              let used = pressure.currentBytes, let hard = pressure.hardBytes, hard > 0
        else { return 0 }
        return min(1, used / hard)
    }

    /// A stalled request has produced nothing for over five seconds.
    public var hasStalled: Bool { generating.contains { $0.isStalled } }

    // MARK: Metrics

    public func metrics(now: Date = .now) -> Metrics {
        var out = Metrics()
        out.engine = engine()
        out.live = live()
        out.requests = requests()
        out.requestsKept = out.requests?.count
        out.totals = totals(now: now)
        out.hardware = hardware()
        // No conversation cache or history: the app samples the series it can from each poll.
        return out
    }

    private func engine() -> Engine? {
        guard let first = models.first else { return nil }
        var engine = Engine()
        engine.model = first.id
        engine.version = stats?.engines?["mlx"]?.version
        engine.engine = stats?.engines?["mlx"]?.name
        engine.maxContext = contextWindow(for: first.id)
        return engine
    }

    /// The loaded model's context window: from the proxy's model table, or the last request's own
    /// figure when the table has not arrived yet.
    private func contextWindow(for model: String?) -> Double? {
        guard let model else { return nil }
        if let window = recent?.windows?[model], window > 0 { return window }
        return recent?.requests?.first { $0.model == model }?.contextWindow
    }

    private func live() -> Live {
        var live = Live()
        // The proxy reports the engine's lane count; without it, the in-flight requests stand in.
        let capacity = recent?.slots ?? activeCount
        live.slots = LiveSlots(total: capacity, active: activeCount, queueDepth: waitingCount)
        // A queue is only the pill's headline while nothing is running: with work in flight the
        // speed matters more, and the Queue card still lists what waits.
        live.queued = activeCount == 0 ? waitingCount : nil
        live.queue = waiting.map { request in
            var queued = QueuedRequest()
            queued.waitedS = request.elapsedSeconds
            queued.model = models.first?.id
            queued.promptTokens = request.promptTokens
            return queued
        }
        if !prefilling.isEmpty { live.prefillTokSMean = prefillTokS }
        if isLoading {
            live.state = .other("loading")
        } else if !generating.isEmpty {
            live.state = .generating
            live.tokS = decodeTokS
            if let first = generating.first {
                live.generated = first.generatedTokens
                live.maxTokens = first.maxTokens
                live.elapsedS = first.elapsedSeconds
                live.promptTokens = first.promptTokens
                live.tokSWindowS = 3   // the server's own sliding window
            }
        } else if !prefilling.isEmpty {
            live.state = .reading
            if let first = prefilling.first {
                live.promptRead = first.processed
                live.promptTotal = first.total
                live.promptTokens = first.promptTokens ?? first.total
            }
        } else {
            live.state = .idle
        }
        return live
    }

    /// Requests as rows: the proxy's finished journal newest first, then whatever is running now.
    /// oMLX keeps no history of its own; the journal comes from the server's own log line.
    private func requests() -> [Request] {
        var rows: [Request] = []
        for item in recent?.requests ?? [] {
            var row = Request(id: "recent-\(Int(item.finishedAt ?? 0))-\(item.model ?? "")")
            row.time = item.finishedAt
            row.durationS = item.durationS
            row.finish = RequestFinish(rawValue: item.finish ?? "")
            row.promptTokens = item.promptTokens
            row.outputTokens = item.outputTokens
            row.decodeTokS = item.tokS
            row.decodeMs = item.durationS.map { $0 * 1000 }
            row.promptMs = item.ttftS.map { $0 * 1000 }
            row.contextUsed = item.contextUsed
            row.maxContext = item.contextWindow
            rows.append(row)
        }
        for item in generating {
            var row = Request(id: item.requestID ?? UUID().uuidString)
            row.promptTokens = item.promptTokens
            row.outputTokens = item.generatedTokens
            row.decodeTokS = item.tokensPerSecond
            row.durationS = item.elapsedSeconds
            rows.append(row)
        }
        for item in prefilling {
            var row = Request(id: item.requestID ?? UUID().uuidString)
            row.promptTokens = item.promptTokens ?? item.total
            row.promptRead = item.processed
            row.durationS = item.elapsed
            rows.append(row)
        }
        for item in waiting {
            var row = Request(id: item.requestID ?? UUID().uuidString)
            row.promptTokens = item.promptTokens
            row.durationS = item.elapsedSeconds
            rows.append(row)
        }
        return rows
    }

    private func totals(now: Date) -> Totals? {
        guard let stats else { return nil }
        var totals = Totals()
        totals.requests = stats.totalRequests
        totals.promptTokens = stats.totalPromptTokens
        totals.reused = stats.totalCachedTokens
        totals.outputTokens = stats.totalCompletionTokens
        totals.since = stats.uptimeSeconds.map { now.timeIntervalSince1970 - $0 }
        // The session card reads speeds from durations; oMLX reports lifetime averages instead,
        // so the durations are worked back out of those. It is the same arithmetic either way.
        let read = max(0, (totals.promptTokens ?? 0) - (totals.reused ?? 0))
        if let avg = stats.avgPrefillTps, avg > 0, read > 0 {
            totals.promptMs = read / avg * 1000
        }
        if let avg = stats.avgGenerationTps, avg > 0, let written = totals.outputTokens, written > 0 {
            totals.decodeMs = written / avg * 1000
        }
        return totals
    }

    /// RAM, not VRAM: the memory-pressure figures are the machine's, and the RAM bar is the one
    /// that means something on an Apple Silicon server.
    private func hardware() -> Hardware? {
        guard let pressure = activity.activeModels?.memoryPressure else { return nil }
        var hardware = Hardware()
        hardware.ramUsed = pressure.currentBytes ?? activity.activeModels?.modelMemoryUsed
        hardware.ramTotal = pressure.hardBytes ?? activity.activeModels?.modelMemoryMax
        return hardware
    }

    /// One row per concurrent lane, in the shape Basalt's `/slots` gives. oMLX runs up to
    /// `scheduler.max_concurrent_requests` requests side by side (the proxy reports it): busy rows
    /// are the decoding/prefilling requests, and the rest stay on the card as idle slots. Waiting
    /// requests are not lanes — the Queue card owns those.
    public func slots() -> [Slot] {
        let capacity = recent?.slots ?? 0
        let window = contextWindow(for: models.first?.id)
        var rows: [Slot] = []
        for item in generating {
            var slot = Slot(id: rows.count, state: .decoding)
            slot.isProcessing = true
            slot.tokS = item.tokensPerSecond
            slot.generated = item.generatedTokens
            slot.promptTokens = item.promptTokens
            slot.ctxUsed = (item.promptTokens ?? 0) + (item.generatedTokens ?? 0)
            slot.model = models.first?.id
            slot.nCtx = window
            rows.append(slot)
        }
        for item in prefilling {
            var slot = Slot(id: rows.count, state: .prefill)
            slot.isProcessing = true
            slot.promptTokens = item.promptTokens ?? item.total
            slot.prefillDone = item.processed
            slot.ctxUsed = item.promptTokens ?? item.processed
            slot.model = models.first?.id
            slot.nCtx = window
            rows.append(slot)
        }
        while rows.count < capacity {
            var slot = Slot(id: rows.count, state: .idle)
            slot.isProcessing = false
            slot.model = models.first?.id
            slot.nCtx = window
            rows.append(slot)
        }
        return rows
    }
}

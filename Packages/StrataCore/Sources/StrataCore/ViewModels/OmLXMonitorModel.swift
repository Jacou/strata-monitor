import Foundation

/// Everything the oMLX Monitor shows, as strings and fractions, from what the poller read. It
/// follows the blocks of oMLX's own Status page: live activity, active models, serving stats,
/// usage history, the cache tiers and the engine versions.
public struct OmLXMonitorModel: Sendable, Equatable {
    public typealias Fact = MonitorViewModel.Fact
    public typealias Tone = MonitorViewModel.Tone

    // MARK: live

    public struct Live: Sendable, Equatable {
        /// Summed decode speed across every running request, "–" when nothing decodes.
        public var decodeText: String
        public var prefillText: String
        /// "2 running · 1 waiting · 4 lanes".
        public var detail: String
        public var isDecoding: Bool
        public var isPrefilling: Bool
    }

    public struct Memory: Sendable, Equatable {
        /// 0...100 of the hard ceiling.
        public var percent: Double
        /// "41.2 / 96.0 GB".
        public var text: String
        /// "Normal", "Soft limit", "Hard limit".
        public var level: String
        public var tone: Tone
        public var facts: [Fact]
    }

    // MARK: active models

    public enum RequestKind: Sendable, Equatable {
        case prefill, generate, waiting
    }

    public struct RequestRow: Identifiable, Sendable, Equatable {
        public var id: String
        public var kind: RequestKind
        /// The first 8 characters of the request id, as the web page shows them.
        public var shortID: String
        public var stateText: String
        /// Right-hand figure: tok/s, or the queue position.
        public var speedText: String
        /// 0...100 for a prefill; nil draws no bar.
        public var percent: Double?
        public var detail: String
        public var isStalled: Bool
    }

    public struct ModelRow: Identifiable, Sendable, Equatable {
        public var id: String
        /// "Pinned", "Loading"…
        public var badges: [String]
        /// "2 req" / "Idle · 4 min · ~26 min left" / "Loading · 12 s, ~30 s left".
        public var statusText: String
        public var sizeText: String
        public var contextText: String?
        public var isBusy: Bool
        public var isLoading: Bool
        public var requests: [RequestRow]
    }

    // MARK: serving stats

    public struct Tile: Identifiable, Sendable, Equatable {
        public var id: String
        public var label: String
        public var value: String
        public var unit: String?
    }

    public struct Serving: Sendable, Equatable {
        public var tiles: [Tile]
        public var prefillSpeed: String
        public var generationSpeed: String
        /// "Up 3 h 12 m" for the session; nil for all time.
        public var footnote: String?
        /// The numbers are being fetched for a newly picked scope or model.
        public var isLoading: Bool
    }

    // MARK: usage

    public struct Usage: Sendable, Equatable {
        public var bars: [OmLXUsageBar]
        /// "Hour" / "Day".
        public var axisLabel: String
        public var totalText: String
        public var facts: [Fact]
        /// Shown instead of the chart when the server keeps no history.
        public var unavailableText: String?
    }

    // MARK: cache

    public struct TierBar: Sendable, Equatable {
        public var label: String
        public var text: String
        public var percent: Double
    }

    public struct Cache: Sendable, Equatable {
        public var tiers: [TierBar]
        public var facts: [Fact]
        public var note: String?
    }

    public var live: Live
    public var memory: Memory?
    public var models: [ModelRow]
    public var modelsSummary: String
    public var serving: Serving?
    public var usage: Usage?
    public var cache: Cache?
    public var engines: [Fact]
    /// Every model id the filter menu can offer: loaded ones first, then any with usage history.
    public var filterChoices: [String]

    public init(
        activity: OmLXActivity?,
        stats: OmLXStats?,
        scopedStats: OmLXStats?,
        scope: OmLXStatsScope,
        modelFilter: String?,
        usage: OmLXUsage?,
        usageRange: OmLXUsageRange,
        modelList: OmLXModelList?,
        slots: Int?,
        locale: Locale = .autoupdatingCurrent
    ) {
        let active = activity?.activeModels
        let models = active?.models ?? []
        let windows = modelList?.windows ?? [:]

        self.live = Self.makeLive(models: models, active: active, slots: slots, locale: locale)
        self.memory = Self.makeMemory(active, locale: locale)
        self.models = models.compactMap { model in
            Self.makeModelRow(model, window: model.id.flatMap { windows[$0] }, locale: locale)
        }
        self.modelsSummary = Self.makeModelsSummary(active)
        self.serving = Self.makeServing(scopedStats, scope: scope, filtered: modelFilter != nil, locale: locale)
        self.usage = usage.map { Self.makeUsage($0, range: usageRange, locale: locale) }
        self.cache = stats?.runtimeCache.map { Self.makeCache($0, model: modelFilter, locale: locale) }
        self.engines = Self.makeEngines(stats?.engines)

        var choices = models.compactMap(\.id)
        for row in usage?.models ?? [] {
            if let id = row.modelID, !choices.contains(id) { choices.append(id) }
        }
        if let modelFilter, !choices.contains(modelFilter) { choices.append(modelFilter) }
        self.filterChoices = choices
    }

    // MARK: - live

    static func makeLive(models: [OmLXModel], active: OmLXActiveModels?, slots: Int?, locale: Locale) -> Live {
        let generating = models.flatMap { $0.generating ?? [] }
        let prefilling = models.flatMap { $0.prefilling ?? [] }
        let decode = generating.reduce(0) { $0 + ($1.tokensPerSecond ?? 0) }
        let prefill = prefilling.reduce(0) { $0 + ($1.speed ?? 0) }
        let running = active?.totalActiveRequests ?? (generating.count + prefilling.count)
        let waiting = active?.totalWaitingRequests ?? models.reduce(0) { $0 + ($1.waiting?.count ?? 0) }

        var parts: [String] = []
        if models.contains(where: { $0.isLoading == true }) {
            parts.append("Loading a model")
        } else if running == 0 && waiting == 0 {
            parts.append(models.isEmpty ? "No model loaded" : "Idle")
        } else {
            parts.append("\(running) running")
        }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if let slots, slots > 0 { parts.append("\(slots) lane\(slots == 1 ? "" : "s")") }

        return Live(
            decodeText: generating.isEmpty ? notAvailable : fmt(decode, 1, locale: locale),
            prefillText: prefilling.isEmpty ? notAvailable : fmt(prefill, 0, locale: locale),
            detail: parts.joined(separator: " · "),
            isDecoding: !generating.isEmpty,
            isPrefilling: !prefilling.isEmpty
        )
    }

    static func makeMemory(_ active: OmLXActiveModels?, locale: Locale) -> Memory? {
        guard let active else { return nil }
        let pressure = active.memoryPressure
        // With the enforcer on, its figures are the ones eviction acts on; otherwise the pool's.
        let enforced = pressure?.enabled == true
        let used = enforced ? pressure?.currentBytes : active.modelMemoryUsed
        let ceiling = enforced ? pressure?.hardBytes : active.modelMemoryMax
        guard let used, let ceiling, ceiling > 0 else { return nil }

        let level: String
        let tone: Tone
        switch pressure?.pressureLevel {
        case "hard":
            level = "Hard limit"; tone = .danger
        case "soft":
            level = "Soft limit"; tone = .warn
        default:
            level = enforced ? "Normal" : "Model memory"; tone = .normal
        }

        var facts: [Fact] = []
        if enforced, let soft = pressure?.softBytes, soft > 0 {
            facts.append(Fact(key: "Soft limit", value: "\(gb(soft, 1, locale: locale)) GB"))
        }
        if enforced, let hard = pressure?.hardBytes, hard > 0 {
            facts.append(Fact(key: "Hard limit", value: "\(gb(hard, 1, locale: locale)) GB"))
        }
        if enforced, let models = active.modelMemoryUsed, models > 0 {
            // With the enforcer on, model_memory_used is the whole process footprint.
            facts.append(Fact(key: "Process", value: "\(gb(models, 1, locale: locale)) GB"))
        }

        return Memory(
            percent: min(100, 100 * used / ceiling),
            text: "\(gb(used, 1, locale: locale)) / \(gb(ceiling, 1, locale: locale)) GB",
            level: level,
            tone: tone,
            facts: facts
        )
    }

    static func makeModelsSummary(_ active: OmLXActiveModels?) -> String {
        let count = active?.models?.count ?? 0
        return count == 1 ? "1 loaded" : "\(count) loaded"
    }

    static func makeModelRow(_ model: OmLXModel, window: Double?, locale: Locale) -> ModelRow? {
        guard let id = model.id else { return nil }
        var badges: [String] = []
        if model.pinned == true { badges.append("Pinned") }

        let active = model.activeRequests ?? ((model.generating?.count ?? 0) + (model.prefilling?.count ?? 0))
        let status: String
        if model.isLoading == true {
            var text = "Loading"
            if let elapsed = model.loadingElapsedSeconds { text += " · \(shortDuration(elapsed))" }
            if let left = model.loadingRemainingSeconds, left > 0 { text += ", ~\(shortDuration(left)) left" }
            status = text
        } else if active > 0 {
            status = "\(active) req"
        } else {
            var text = "Idle"
            if let idle = model.idleSeconds { text += " · \(shortDuration(idle))" }
            if let ttl = model.ttlRemainingSeconds { text += " · ~\(shortDuration(ttl)) left" }
            status = text
        }

        // `actual_size` is what is resident; `estimated_size` counts what is offloaded to SSD too.
        let size = (model.actualSize ?? 0) > 0 ? model.actualSize : model.estimatedSize
        let sizeText = size.map { "\(model.isLoading == true ? "est. " : "")\(gb($0, 1, locale: locale)) GB" } ?? notAvailable

        var requests: [RequestRow] = []
        for item in model.prefilling ?? [] {
            let total = item.total ?? 0
            let done = item.processed ?? 0
            var detail = "\(kfmt(done, locale: locale)) / \(kfmt(total, locale: locale)) tok"
            if let cached = item.cachedTokens, cached > 0 { detail += " · \(kfmt(cached, locale: locale)) cached" }
            if let elapsed = item.elapsed { detail += " · \(shortDuration(elapsed))" }
            if let eta = item.eta, eta > 0 { detail += " · ~\(shortDuration(eta)) left" }
            requests.append(RequestRow(
                id: item.requestID ?? "prefill-\(requests.count)",
                kind: .prefill,
                shortID: shortID(item.requestID),
                stateText: item.detail ?? "Reading prompt",
                speedText: item.speed.map { "\(fmt($0, 0, locale: locale)) tok/s" } ?? "",
                percent: total > 0 ? min(100, 100 * done / total) : nil,
                detail: detail,
                isStalled: false
            ))
        }
        for item in model.generating ?? [] {
            var detail = "\(kfmt(item.generatedTokens ?? 0, locale: locale)) tok"
            if let max = item.maxTokens, max > 0 { detail += " of \(kfmt(max, locale: locale))" }
            if let prompt = item.promptTokens, prompt > 0 { detail += " · prompt \(kfmt(prompt, locale: locale))" }
            if let elapsed = item.elapsedSeconds { detail += " · \(shortDuration(elapsed))" }
            let context = (item.promptTokens ?? 0) + (item.generatedTokens ?? 0)
            requests.append(RequestRow(
                id: item.requestID ?? "gen-\(requests.count)",
                kind: .generate,
                shortID: shortID(item.requestID),
                stateText: item.isStalled ? "Stalled" : "Generating",
                speedText: item.tokensPerSecond.map { "\(fmt($0, 1, locale: locale)) tok/s" } ?? "",
                percent: window.map { $0 > 0 ? min(100, 100 * context / $0) : 0 },
                detail: detail,
                isStalled: item.isStalled
            ))
        }
        for item in (model.waiting ?? []).sorted(by: { ($0.queuePosition ?? 0) < ($1.queuePosition ?? 0) }) {
            var detail = item.elapsedSeconds.map { "waiting \(shortDuration($0))" } ?? "waiting"
            if let prompt = item.promptTokens, prompt > 0 { detail += " · \(kfmt(prompt, locale: locale)) prompt tokens" }
            requests.append(RequestRow(
                id: item.requestID ?? "wait-\(requests.count)",
                kind: .waiting,
                shortID: shortID(item.requestID),
                stateText: "Waiting",
                speedText: item.queuePosition.map { "#\($0)" } ?? "",
                percent: nil,
                detail: detail,
                isStalled: false
            ))
        }

        return ModelRow(
            id: id,
            badges: badges,
            statusText: status,
            sizeText: sizeText,
            contextText: window.map { "\(ctxfmt($0, locale: locale)) context" },
            isBusy: active > 0,
            isLoading: model.isLoading == true,
            requests: requests
        )
    }

    // MARK: - serving

    static func makeServing(_ stats: OmLXStats?, scope: OmLXStatsScope, filtered: Bool, locale: Locale) -> Serving? {
        guard let stats else {
            return Serving(tiles: [], prefillSpeed: notAvailable, generationSpeed: notAvailable,
                           footnote: nil, isLoading: true)
        }
        let efficiency = stats.cacheEfficiency.map { fmt($0, 1, locale: locale) } ?? notAvailable
        let tiles = [
            Tile(id: "requests", label: "Requests", value: bigCount(stats.totalRequests, locale: locale)),
            Tile(id: "prompt", label: "Prompt tokens", value: bigCount(stats.totalPromptTokens, locale: locale)),
            Tile(id: "cached", label: "Cached tokens", value: bigCount(stats.totalCachedTokens, locale: locale)),
            Tile(id: "efficiency", label: "Cache efficiency", value: efficiency, unit: "%"),
            Tile(id: "generated", label: "Generated", value: bigCount(stats.totalCompletionTokens, locale: locale)),
            Tile(id: "served", label: "Tokens served", value: bigCount(stats.totalTokensServed, locale: locale)),
        ]
        var footnote: String?
        if scope == .session, let uptime = stats.uptimeSeconds {
            footnote = "Up \(uptimeText(uptime, locale: locale))" + (filtered ? " · one model" : "")
        } else if filtered {
            footnote = "One model"
        }
        return Serving(
            tiles: tiles,
            prefillSpeed: stats.avgPrefillTps.map { "\(fmt($0, 1, locale: locale)) tok/s" } ?? notAvailable,
            generationSpeed: stats.avgGenerationTps.map { "\(fmt($0, 1, locale: locale)) tok/s" } ?? notAvailable,
            footnote: footnote,
            isLoading: false
        )
    }

    // MARK: - usage

    static func makeUsage(_ usage: OmLXUsage, range: OmLXUsageRange, locale: Locale) -> Usage {
        var unavailable: String?
        if usage.enabled == false {
            unavailable = "Usage history is turned off in oMLX's settings."
        } else if usage.available == false {
            unavailable = "Usage history is not available on this server."
        }
        let totals = usage.totals
        var facts: [Fact] = []
        if let totals {
            facts.append(Fact(key: "Requests", value: bigCount(totals.requests, locale: locale)))
            facts.append(Fact(key: "Prompt / generated",
                              value: "\(bigCount(totals.promptTokens, locale: locale)) / \(bigCount(totals.completionTokens, locale: locale))"))
            if let efficiency = totals.cacheEfficiency {
                facts.append(Fact(key: "Cache efficiency", value: "\(fmt(efficiency * 100, 1, locale: locale))%"))
            }
            if let decode = totals.generationTps {
                facts.append(Fact(key: "Generation", value: "\(fmt(decode, 1, locale: locale)) tok/s"))
            }
            if let prefill = totals.prefillTps {
                facts.append(Fact(key: "Prefill", value: "\(fmt(prefill, 0, locale: locale)) tok/s"))
            }
        }
        // The busiest models, when more than one served in this range.
        let rows = usage.models ?? []
        if rows.count > 1 {
            for row in rows.prefix(3) {
                guard let id = row.modelID else { continue }
                facts.append(Fact(key: id, value: "\(bigCount(row.totalTokens, locale: locale)) tok"))
            }
        }
        return Usage(
            bars: usage.bars,
            axisLabel: range == .today ? "Hour" : "Day",
            totalText: "\(bigCount(totals?.totalTokens ?? 0, locale: locale)) tokens",
            facts: facts,
            unavailableText: unavailable
        )
    }

    // MARK: - cache

    static func makeCache(_ cache: OmLXRuntimeCache, model: String?, locale: Locale) -> Cache {
        var tiers: [TierBar] = []
        if cache.hasMemoryTier {
            let used = cache.hotCacheSizeBytes ?? 0
            let max = cache.hotCacheMaxBytes ?? 0
            tiers.append(TierBar(
                label: "Memory",
                text: "\(gb(used, 1, locale: locale)) / \(gb(max, 1, locale: locale)) GB · \(bigCount(cache.hotCacheEntries ?? 0, locale: locale)) blocks",
                percent: max > 0 ? min(100, 100 * used / max) : 0
            ))
        }
        if cache.ssdCacheUnavailable != true {
            let used = cache.totalSizeBytes ?? 0
            let max = cache.diskMaxBytes ?? 0
            let ceiling = max > 0 ? " / \(gb(max, 1, locale: locale))" : ""
            tiers.append(TierBar(
                label: "SSD",
                text: "\(gb(used, 1, locale: locale))\(ceiling) GB · \(bigCount(cache.totalNumFiles ?? 0, locale: locale)) files",
                percent: max > 0 ? min(100, 100 * used / max) : 0
            ))
        }

        let rates = cache.rates(model: model)
        var facts: [Fact] = []
        if let rate = rates.prefixHitRate {
            facts.append(Fact(key: "Prefix hit rate", value: "\(fmt(rate * 100, 1, locale: locale))%"))
        }
        if let rate = rates.memoryHitRate {
            facts.append(Fact(key: "Memory hit rate", value: "\(fmt(rate * 100, 1, locale: locale))%"))
        }
        if let evictions = rates.evictions {
            facts.append(Fact(key: "Prefix evictions", value: bigCount(evictions, locale: locale)))
        }
        if let evictions = rates.hotCacheEvictions, cache.hasMemoryTier {
            facts.append(Fact(key: "Memory evictions", value: bigCount(evictions, locale: locale)))
        }

        let note = cache.ssdCacheUnavailable == true
            ? "The SSD cache folder is not available\(cache.ssdCacheDir.map { ": \($0)" } ?? ".")"
            : nil
        return Cache(tiers: tiers, facts: facts, note: note)
    }

    // MARK: - engines

    static func makeEngines(_ engines: [String: OmLXEngineVersion]?) -> [Fact] {
        let order = ["mlx", "mlx-lm", "mlx-vlm", "mlx-embeddings", "mlx-audio"]
        let entries = engines ?? [:]
        let keys = order.filter { entries[$0] != nil } + entries.keys.filter { !order.contains($0) }.sorted()
        return keys.compactMap { key in
            guard let entry = entries[key], let version = entry.version else { return nil }
            let commit = entry.commit.map { " · \($0.prefix(7))" } ?? ""
            return Fact(key: entry.name ?? key, value: version + commit)
        }
    }

    // MARK: - formatting

    /// 950 → "950", 12_400 → "12k", 3_200_000 → "3.2M", 1_100_000_000 → "1.1B".
    static func bigCount(_ value: Double?, locale: Locale) -> String {
        guard let value, value.isFinite else { return notAvailable }
        if value >= 1_000_000_000 { return fmt(value / 1_000_000_000, 1, locale: locale) + "B" }
        if value >= 1_000_000 { return fmt(value / 1_000_000, 1, locale: locale) + "M" }
        return kfmt(value, locale: locale)
    }

    /// The web page's `formatDurationShort`: "42 s", "12 min", "3 h 5 m".
    static func shortDuration(_ seconds: Double) -> String {
        uptimeText(seconds)
    }

    static func shortID(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "—" }
        return String(id.prefix(8))
    }
}

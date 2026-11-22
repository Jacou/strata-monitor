import Foundation

// The parts of oMLX's admin API the app reads directly from the server (`:8000`, with the main
// API key as a Bearer token): no stats proxy in between.

// MARK: - stats scope

/// `/admin/api/stats?scope=`: since this server process started, or the totals oMLX persists.
public enum OmLXStatsScope: String, Sendable, Equatable, CaseIterable, Identifiable {
    case session
    case alltime

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .session: "Session"
        case .alltime: "All time"
        }
    }
}

// MARK: - /admin/api/stats → runtime_cache

/// The two cache tiers the dashboard's "Cache" block shows: hot blocks in memory, cold ones on SSD.
public struct OmLXRuntimeCache: Decodable, Encodable, Sendable, Equatable {
    public var basePath: String?
    public var ssdCacheDir: String?
    public var ssdCacheUnavailable: Bool?
    public var totalNumFiles: Double?
    public var totalSizeBytes: Double?
    /// The SSD tier's ceiling; 0 or missing when unbounded.
    public var diskMaxBytes: Double?
    /// 0 means the memory tier is off.
    public var hotCacheMaxBytes: Double?
    public var hotCacheSizeBytes: Double?
    public var hotCacheEntries: Double?
    public var models: [OmLXCacheModel]?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        basePath = c.decodeString(forKey: .basePath)
        ssdCacheDir = c.decodeString(forKey: .ssdCacheDir)
        ssdCacheUnavailable = c.decodeBool(forKey: .ssdCacheUnavailable)
        totalNumFiles = c.decodeDouble(forKey: .totalNumFiles)
        totalSizeBytes = c.decodeDouble(forKey: .totalSizeBytes)
        diskMaxBytes = c.decodeDouble(forKey: .diskMaxBytes)
        hotCacheMaxBytes = c.decodeDouble(forKey: .hotCacheMaxBytes)
        hotCacheSizeBytes = c.decodeDouble(forKey: .hotCacheSizeBytes)
        hotCacheEntries = c.decodeDouble(forKey: .hotCacheEntries)
        models = c.decodeArray(OmLXCacheModel.self, forKey: .models)
    }

    private enum CodingKeys: String, CodingKey {
        case models
        case basePath = "base_path"
        case ssdCacheDir = "ssd_cache_dir"
        case ssdCacheUnavailable = "ssd_cache_unavailable"
        case totalNumFiles = "total_num_files"
        case totalSizeBytes = "total_size_bytes"
        case diskMaxBytes = "disk_max_bytes"
        case hotCacheMaxBytes = "hot_cache_max_bytes"
        case hotCacheSizeBytes = "hot_cache_size_bytes"
        case hotCacheEntries = "hot_cache_entries"
    }

    /// The memory tier is configured.
    public var hasMemoryTier: Bool { (hotCacheMaxBytes ?? 0) > 0 }

    /// Hit rates summed over every loaded model, the way the dashboard's `cacheObsCumulative`
    /// does when no model filter is set; one model's own counters when `model` is given.
    public func rates(model: String? = nil) -> OmLXCacheRates {
        let entries = models ?? []
        if let model, !model.isEmpty {
            return entries.first { $0.id == model }?.cumulative ?? OmLXCacheRates()
        }
        return entries.reduce(into: OmLXCacheRates()) { sum, entry in
            guard let c = entry.cumulative else { return }
            sum.prefixHits = (sum.prefixHits ?? 0) + (c.prefixHits ?? 0)
            sum.prefixMisses = (sum.prefixMisses ?? 0) + (c.prefixMisses ?? 0)
            sum.evictions = (sum.evictions ?? 0) + (c.evictions ?? 0)
            sum.ssdHotHits = (sum.ssdHotHits ?? 0) + (c.ssdHotHits ?? 0)
            sum.ssdDiskLoads = (sum.ssdDiskLoads ?? 0) + (c.ssdDiskLoads ?? 0)
            sum.ssdSaves = (sum.ssdSaves ?? 0) + (c.ssdSaves ?? 0)
            sum.hotCacheEvictions = (sum.hotCacheEvictions ?? 0) + (c.hotCacheEvictions ?? 0)
            sum.hotCachePromotions = (sum.hotCachePromotions ?? 0) + (c.hotCachePromotions ?? 0)
        }
    }
}

/// One loaded model's slice of the cache.
public struct OmLXCacheModel: Decodable, Encodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var blockSize: Double?
    public var indexedBlocks: Double?
    public var numFiles: Double?
    public var totalSizeBytes: Double?
    public var hotCacheEntries: Double?
    public var hotCacheSizeBytes: Double?
    /// `cache_rates.cumulative`.
    public var cumulative: OmLXCacheRates?

    public init(id: String) { self.id = id }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeString(forKey: .id) ?? ""
        blockSize = c.decodeDouble(forKey: .blockSize)
        indexedBlocks = c.decodeDouble(forKey: .indexedBlocks)
        numFiles = c.decodeDouble(forKey: .numFiles)
        totalSizeBytes = c.decodeDouble(forKey: .totalSizeBytes)
        hotCacheEntries = c.decodeDouble(forKey: .hotCacheEntries)
        hotCacheSizeBytes = c.decodeDouble(forKey: .hotCacheSizeBytes)
        if let rates = try? c.nestedContainer(keyedBy: RatesKeys.self, forKey: .cacheRates) {
            cumulative = try? rates.decode(OmLXCacheRates.self, forKey: .cumulative)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(blockSize, forKey: .blockSize)
        try c.encodeIfPresent(indexedBlocks, forKey: .indexedBlocks)
        try c.encodeIfPresent(numFiles, forKey: .numFiles)
        try c.encodeIfPresent(totalSizeBytes, forKey: .totalSizeBytes)
        try c.encodeIfPresent(hotCacheEntries, forKey: .hotCacheEntries)
        try c.encodeIfPresent(hotCacheSizeBytes, forKey: .hotCacheSizeBytes)
        if let cumulative {
            var rates = c.nestedContainer(keyedBy: RatesKeys.self, forKey: .cacheRates)
            try rates.encode(cumulative, forKey: .cumulative)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case blockSize = "block_size"
        case indexedBlocks = "indexed_blocks"
        case numFiles = "num_files"
        case totalSizeBytes = "total_size_bytes"
        case hotCacheEntries = "hot_cache_entries"
        case hotCacheSizeBytes = "hot_cache_size_bytes"
        case cacheRates = "cache_rates"
    }

    private enum RatesKeys: String, CodingKey { case cumulative }
}

/// Prefix-cache and memory-tier counters since the model loaded.
public struct OmLXCacheRates: Decodable, Encodable, Sendable, Equatable {
    public var prefixHits: Double?
    public var prefixMisses: Double?
    public var evictions: Double?
    public var ssdHotHits: Double?
    public var ssdDiskLoads: Double?
    public var ssdSaves: Double?
    public var hotCacheEvictions: Double?
    public var hotCachePromotions: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prefixHits = c.decodeDouble(forKey: .prefixHits)
        prefixMisses = c.decodeDouble(forKey: .prefixMisses)
        evictions = c.decodeDouble(forKey: .evictions)
        ssdHotHits = c.decodeDouble(forKey: .ssdHotHits)
        ssdDiskLoads = c.decodeDouble(forKey: .ssdDiskLoads)
        ssdSaves = c.decodeDouble(forKey: .ssdSaves)
        hotCacheEvictions = c.decodeDouble(forKey: .hotCacheEvictions)
        hotCachePromotions = c.decodeDouble(forKey: .hotCachePromotions)
    }

    private enum CodingKeys: String, CodingKey {
        case evictions
        case prefixHits = "prefix_hits"
        case prefixMisses = "prefix_misses"
        case ssdHotHits = "ssd_hot_hits"
        case ssdDiskLoads = "ssd_disk_loads"
        case ssdSaves = "ssd_saves"
        case hotCacheEvictions = "hot_cache_evictions"
        case hotCachePromotions = "hot_cache_promotions"
    }

    /// 0...1: prefix lookups that found blocks already cached.
    public var prefixHitRate: Double? {
        let hits = prefixHits ?? 0, misses = prefixMisses ?? 0
        return hits + misses > 0 ? hits / (hits + misses) : nil
    }

    /// 0...1: cached blocks served from memory rather than read back from SSD.
    public var memoryHitRate: Double? {
        let hot = ssdHotHits ?? 0, disk = ssdDiskLoads ?? 0
        return hot + disk > 0 ? hot / (hot + disk) : nil
    }
}

// MARK: - /admin/api/models

/// The model list. Read for each model's context window and type; it is a heavy call on the server,
/// so the app asks once a minute.
public struct OmLXModelList: Decodable, Sendable, Equatable {
    public var models: [OmLXModelInfo]

    public init(models: [OmLXModelInfo] = []) { self.models = models }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        models = c.decodeArray(OmLXModelInfo.self, forKey: .models) ?? []
    }

    private enum CodingKeys: String, CodingKey { case models }

    /// Context window by model id, for the models that report one.
    public var windows: [String: Double] {
        var out: [String: Double] = [:]
        for model in models {
            if let length = model.modelContextLength, length > 0 { out[model.id] = length }
        }
        return out
    }
}

public struct OmLXModelInfo: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String?
    public var loaded: Bool?
    public var isLoading: Bool?
    public var pinned: Bool?
    public var isDefault: Bool?
    public var isHidden: Bool?
    public var modelType: String?
    public var engineType: String?
    public var modelContextLength: Double?
    public var estimatedSize: Double?

    public init(id: String) { self.id = id }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeString(forKey: .id) ?? ""
        displayName = c.decodeString(forKey: .displayName)
        loaded = c.decodeBool(forKey: .loaded)
        isLoading = c.decodeBool(forKey: .isLoading)
        pinned = c.decodeBool(forKey: .pinned)
        isDefault = c.decodeBool(forKey: .isDefault)
        isHidden = c.decodeBool(forKey: .isHidden)
        modelType = c.decodeString(forKey: .modelType)
        engineType = c.decodeString(forKey: .engineType)
        modelContextLength = c.decodeDouble(forKey: .modelContextLength)
        estimatedSize = c.decodeDouble(forKey: .estimatedSize)
    }

    private enum CodingKeys: String, CodingKey {
        case id, loaded, pinned
        case displayName = "display_name"
        case isLoading = "is_loading"
        case isDefault = "is_default"
        case isHidden = "is_hidden"
        case modelType = "model_type"
        case engineType = "engine_type"
        case modelContextLength = "model_context_length"
        case estimatedSize = "estimated_size"
    }
}

// MARK: - /admin/api/global-settings

/// The one setting the Monitor needs: how many requests the engine runs side by side.
public struct OmLXGlobalSettings: Decodable, Sendable, Equatable {
    public var maxConcurrentRequests: Int?

    public init(maxConcurrentRequests: Int? = nil) { self.maxConcurrentRequests = maxConcurrentRequests }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let scheduler = try? c.nestedContainer(keyedBy: SchedulerKeys.self, forKey: .scheduler) {
            maxConcurrentRequests = scheduler.decodeInt(forKey: .maxConcurrentRequests)
        }
    }

    private enum CodingKeys: String, CodingKey { case scheduler }
    private enum SchedulerKeys: String, CodingKey {
        case maxConcurrentRequests = "max_concurrent_requests"
    }
}

// MARK: - /admin/api/usage

/// `/admin/api/usage?range=`: oMLX's own hourly serving history, kept in SQLite on the server.
public enum OmLXUsageRange: String, Sendable, Equatable, CaseIterable, Identifiable {
    case today
    case week = "7d"
    case month = "30d"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
}

public struct OmLXUsage: Decodable, Sendable, Equatable {
    public var range: String?
    public var enabled: Bool?
    public var available: Bool?
    public var totals: OmLXUsageSummary?
    public var models: [OmLXUsageSummary]?
    /// One entry per calendar day, 24 hourly token counts each, in the server's local time.
    public var heatmap: [OmLXUsageDay]?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        range = c.decodeString(forKey: .range)
        enabled = c.decodeBool(forKey: .enabled)
        available = c.decodeBool(forKey: .available)
        totals = try? c.decode(OmLXUsageSummary.self, forKey: .totals)
        models = c.decodeArray(OmLXUsageSummary.self, forKey: .models)
        heatmap = c.decodeArray(OmLXUsageDay.self, forKey: .heatmap)
    }

    private enum CodingKeys: String, CodingKey { case range, enabled, available, totals, models, heatmap }

    /// The bars the chart draws: one per hour for a single day, one per day for a longer range.
    public var bars: [OmLXUsageBar] {
        let days = heatmap ?? []
        if days.count == 1, let day = days.first {
            return day.tokens.enumerated().map { hour, tokens in
                OmLXUsageBar(id: "\(day.date)-\(hour)", label: String(format: "%02d", hour), tokens: tokens)
            }
        }
        return days.map { day in
            OmLXUsageBar(id: day.date, label: Self.shortDay(day.date), tokens: day.tokens.reduce(0, +))
        }
    }

    /// "2026-11-21" → "21". The chart's axis only needs the day of the month.
    static func shortDay(_ iso: String) -> String {
        guard let last = iso.split(separator: "-").last else { return iso }
        return String(Int(last) ?? 0)
    }
}

public struct OmLXUsageBar: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var tokens: Double
}

public struct OmLXUsageDay: Decodable, Sendable, Equatable {
    public var date: String
    public var tokens: [Double]

    public init(date: String, tokens: [Double]) {
        self.date = date
        self.tokens = tokens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.decodeString(forKey: .date) ?? ""
        tokens = c.decodeDoubleArray(forKey: .tokens) ?? []
    }

    private enum CodingKeys: String, CodingKey { case date, tokens }
}

public struct OmLXUsageSummary: Decodable, Sendable, Equatable {
    /// Set on the per-model rows only.
    public var modelID: String?
    public var requests: Double?
    public var promptTokens: Double?
    public var completionTokens: Double?
    public var cachedTokens: Double?
    public var totalTokens: Double?
    /// 0...1 here, unlike the stats endpoint's percent.
    public var cacheEfficiency: Double?
    public var generationTps: Double?
    public var prefillTps: Double?
    public var averageRequestSeconds: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelID = c.decodeString(forKey: .modelID)
        requests = c.decodeDouble(forKey: .requests)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        completionTokens = c.decodeDouble(forKey: .completionTokens)
        cachedTokens = c.decodeDouble(forKey: .cachedTokens)
        totalTokens = c.decodeDouble(forKey: .totalTokens)
        cacheEfficiency = c.decodeDouble(forKey: .cacheEfficiency)
        generationTps = c.decodeDouble(forKey: .generationTps)
        prefillTps = c.decodeDouble(forKey: .prefillTps)
        averageRequestSeconds = c.decodeDouble(forKey: .averageRequestSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case requests
        case modelID = "model_id"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case cachedTokens = "cached_tokens"
        case totalTokens = "total_tokens"
        case cacheEfficiency = "cache_efficiency"
        case generationTps = "generation_tps"
        case prefillTps = "prefill_tps"
        case averageRequestSeconds = "average_request_seconds"
    }
}

// MARK: - /admin/api/logs

/// `/admin/api/logs?lines=N`: the last N lines of `server.log` as one string, and how many lines
/// the file holds. A smaller `total_lines` than last time means the log rotated.
public struct OmLXLogTail: Decodable, Sendable, Equatable {
    public var logs: String
    public var totalLines: Int
    public var logFile: String?

    public init(logs: String, totalLines: Int, logFile: String? = nil) {
        self.logs = logs
        self.totalLines = totalLines
        self.logFile = logFile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logs = c.decodeString(forKey: .logs) ?? ""
        totalLines = c.decodeInt(forKey: .totalLines) ?? 0
        logFile = c.decodeString(forKey: .logFile)
    }

    private enum CodingKeys: String, CodingKey {
        case logs
        case totalLines = "total_lines"
        case logFile = "log_file"
    }

    /// The tail as numbered lines, so the Logs screen can keep only what is new. Line numbers are
    /// the file's own: the last line is `totalLines`.
    public var numberedLines: [(number: Int, text: String)] {
        var lines = logs.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        let first = totalLines - lines.count + 1
        return lines.enumerated().map { (number: first + $0.offset, text: $0.element) }
    }
}

/// Reads oMLX's `server.log` lines. Python's default format:
/// `2026-11-21 21:30:01,123 - omlx.server - INFO - message`.
public enum OmLXLogParser {
    /// `Chat completion: model=X, N tokens in Ds (T tok/s), prompt: P, finish_reason=R,
    /// max_tokens=M, request_max_tokens=RM[, stream_model_ttft=Ss, …]` — the line oMLX writes when
    /// a chat request finishes. TTFT is only on streamed requests.
    nonisolated(unsafe) private static let completion = /^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) .*?Chat completion: model=(?<model>[^,]+), (?<out>\d+) tokens in (?<dur>[\d.]+)s \((?<tps>[\d.]+) tok\/s[^)]*\), prompt: (?<prompt>\d+), finish_reason=(?<finish>\w+), max_tokens=(?<max>\w+)(?:, request_max_tokens=\w+)?(?:, stream_model_ttft=(?<ttft>[\d.]+)s)?/

    nonisolated(unsafe) private static let header = /^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) - (?<src>[^ ]+) - (?<lvl>[A-Z]+) - (?<msg>.*)$/

    /// The server stamps its log in its own local time; the phone is assumed to be in the same zone.
    /// `yyyy-MM-dd HH:mm:ss,SSS`, read by position: the Logs screen parses hundreds of lines every
    /// two seconds, and a `DateFormatter` per line would cost more than the rest of the parse.
    static func timestamp(_ text: Substring, timeZone: TimeZone = .current) -> Double? {
        let chars = Array(text.utf8)
        guard chars.count == 23 else { return nil }
        func number(_ from: Int, _ length: Int) -> Int? {
            var value = 0
            for index in from..<(from + length) {
                let digit = Int(chars[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              let millis = number(20, 3)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: components) else { return nil }
        return date.timeIntervalSince1970 + Double(millis) / 1000
    }

    /// Every finished request in the text, newest first.
    public static func finishedRequests(
        in lines: [String],
        windows: [String: Double] = [:],
        timeZone: TimeZone = .current
    ) -> [OmLXFinishedRequest] {
        var out: [OmLXFinishedRequest] = []
        for line in lines where line.contains("Chat completion: ") {
            guard let match = line.firstMatch(of: completion) else { continue }
            var item = OmLXFinishedRequest()
            item.finishedAt = timestamp(match.ts, timeZone: timeZone)
            let model = String(match.model)
            item.model = model
            item.outputTokens = Double(match.out)
            item.durationS = Double(match.dur)
            item.tokS = Double(match.tps)
            item.promptTokens = Double(match.prompt)
            item.finish = String(match.finish)
            item.maxTokens = Double(match.max)
            item.ttftS = match.ttft.flatMap { Double($0) }
            item.contextUsed = (item.promptTokens ?? 0) + (item.outputTokens ?? 0)
            item.contextWindow = windows[model]
            out.append(item)
        }
        return out.reversed()
    }

    /// One log line for the Logs screen. A line without the usual header (a traceback, a
    /// continuation) is kept as it is, at info level.
    public static func logLine(number: Int, text: String, timeZone: TimeZone = .current) -> LogLine {
        guard let match = text.firstMatch(of: header) else {
            return LogLine(id: number, level: .info, message: text)
        }
        let level: LogLevel
        switch match.lvl {
        case "WARNING", "WARN": level = .warn
        case "ERROR", "CRITICAL", "FATAL": level = .err
        default: level = .info
        }
        return LogLine(
            id: number,
            time: timestamp(match.ts, timeZone: timeZone),
            source: String(match.src),
            level: level,
            message: String(match.msg)
        )
    }

    /// The tail as the batch shape the Logs screen already understands: ids are line numbers, and
    /// `last` is the file's line count, so a rotated log (fewer lines) starts the screen over.
    public static func batch(_ tail: OmLXLogTail, timeZone: TimeZone = .current) -> LogBatch {
        LogBatch(
            lines: tail.numberedLines.map { logLine(number: $0.number, text: $0.text, timeZone: timeZone) },
            last: tail.totalLines
        )
    }
}

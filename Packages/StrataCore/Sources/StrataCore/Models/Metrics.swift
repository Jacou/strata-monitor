import Foundation

// MARK: - /metrics

/// Everything `GET /metrics` returns. Every field is optional: servers differ by version,
/// and a partial payload must still render.
public struct Metrics: Decodable, Encodable, Sendable, Equatable {
    public var engine: Engine?
    public var live: Live?
    public var requests: [Request]?
    public var conversationCache: ConversationCache?
    public var requestsKept: Int?
    public var totals: Totals?
    public var hardware: Hardware?
    public var hardwareStatic: HardwareStatic?
    public var history: History?
    public var time: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        engine = try? c.decode(Engine.self, forKey: .engine)
        live = try? c.decode(Live.self, forKey: .live)
        requests = c.decodeArray(Request.self, forKey: .requests)
        conversationCache = try? c.decode(ConversationCache.self, forKey: .conversationCache)
        requestsKept = c.decodeInt(forKey: .requestsKept)
        totals = try? c.decode(Totals.self, forKey: .totals)
        hardware = try? c.decode(Hardware.self, forKey: .hardware)
        hardwareStatic = try? c.decode(HardwareStatic.self, forKey: .hardwareStatic)
        history = try? c.decode(History.self, forKey: .history)
        time = c.decodeDouble(forKey: .time)
        // Basalt reports each GPU but not the totals Strata adds up; work them out the same way.
        hardware = hardware?.fillingTotals()
        hardwareStatic = hardwareStatic?.fillingNames()
    }

    private enum CodingKeys: String, CodingKey {
        case engine, live, requests
        case conversationCache = "conversation_cache"
        case requestsKept = "requests_kept"
        case totals, hardware
        case hardwareStatic = "hardware_static"
        case history, time
    }

    /// The newest request, or nil when there is none.
    public var latestRequest: Request? { requests?.first }
}

// MARK: - engine

public struct Engine: Decodable, Encodable, Sendable, Equatable {
    public var model: String?
    public var maxContext: Double?
    public var images: Bool?
    public var version: String?
    public var context: Double?
    public var kv: String?
    public var kvResident: Double?
    public var expertSlots: Double?
    public var expertCacheMib: Double?
    public var expertSlotsPrimary: Double?
    public var expertCachePrimaryMib: Double?
    public var spec: Double?
    public var mtpMax: Double?
    public var lookup: Double?
    public var vramFreeMib: Double?
    /// "project:4-44[:singleL] | add:A-B | 0" — or a number.
    public var cvec: LenientString?
    public var arenaMib: Double?
    public var poolWorkers: Double?
    public var pcieFrac: LenientString?
    public var specMinP: LenientString?
    public var conversationCacheMib: Double?
    public var conversationCacheSlots: Double?
    public var conversationCacheMinFreeMib: Double?
    public var tailRoleToken: Double?
    public var vramElastic: Double?
    public var engine: String?
    /// Basalt: the weight format ("NVFP4").
    public var quant: String?
    /// Basalt: how many requests the engine runs side by side.
    public var batchSlots: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = c.decodeString(forKey: .model)
        maxContext = c.decodeDouble(forKey: .maxContext)
        images = c.decodeBool(forKey: .images)
        version = c.decodeString(forKey: .version)
        context = c.decodeDouble(forKey: .context)
        kv = c.decodeString(forKey: .kv)
        kvResident = c.decodeDouble(forKey: .kvResident)
        expertSlots = c.decodeDouble(forKey: .expertSlots)
        expertCacheMib = c.decodeDouble(forKey: .expertCacheMib)
        expertSlotsPrimary = c.decodeDouble(forKey: .expertSlotsPrimary)
        expertCachePrimaryMib = c.decodeDouble(forKey: .expertCachePrimaryMib)
        spec = c.decodeDouble(forKey: .spec)
        mtpMax = c.decodeDouble(forKey: .mtpMax)
        lookup = c.decodeDouble(forKey: .lookup)
        vramFreeMib = c.decodeDouble(forKey: .vramFreeMib)
        cvec = try? c.decode(LenientString.self, forKey: .cvec)
        arenaMib = c.decodeDouble(forKey: .arenaMib)
        poolWorkers = c.decodeDouble(forKey: .poolWorkers)
        pcieFrac = try? c.decode(LenientString.self, forKey: .pcieFrac)
        specMinP = try? c.decode(LenientString.self, forKey: .specMinP)
        conversationCacheMib = c.decodeDouble(forKey: .conversationCacheMib)
        conversationCacheSlots = c.decodeDouble(forKey: .conversationCacheSlots)
        conversationCacheMinFreeMib = c.decodeDouble(forKey: .conversationCacheMinFreeMib)
        tailRoleToken = c.decodeDouble(forKey: .tailRoleToken)
        vramElastic = c.decodeDouble(forKey: .vramElastic)
        engine = c.decodeString(forKey: .engine)
        quant = c.decodeString(forKey: .quant)
        batchSlots = c.decodeDouble(forKey: .batchSlots)
    }

    private enum CodingKeys: String, CodingKey {
        case model, images, version, context, kv, spec, lookup, engine, cvec, quant
        case batchSlots = "batch_slots"
        case maxContext = "max_context"
        case kvResident = "kv_resident"
        case expertSlots = "expert_slots"
        case expertCacheMib = "expert_cache_mib"
        case expertSlotsPrimary = "expert_slots_primary"
        case expertCachePrimaryMib = "expert_cache_primary_mib"
        case mtpMax = "mtp_max"
        case vramFreeMib = "vram_free_mib"
        case arenaMib = "arena_mib"
        case poolWorkers = "pool_workers"
        case pcieFrac = "pcie_frac"
        case specMinP = "spec_min_p"
        case conversationCacheMib = "conversation_cache_mib"
        case conversationCacheSlots = "conversation_cache_slots"
        case conversationCacheMinFreeMib = "conversation_cache_min_free_mib"
        case tailRoleToken = "tail_role_token"
        case vramElastic = "vram_elastic"
    }
}

// MARK: - live

/// `idle | reading | generating`; anything a newer server adds is kept as `other`.
public enum LiveState: Codable, Equatable, Sendable {
    case idle
    case reading
    case generating
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        switch raw {
        case "idle": self = .idle
        case "reading": self = .reading
        case "generating": self = .generating
        case "": self = .other("")
        default: self = .other(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "reading": self = .reading
        case "generating": self = .generating
        case "": return nil
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .idle: "idle"
        case .reading: "reading"
        case .generating: "generating"
        case .other(let value): value
        }
    }
}

/// What the engine is doing right now. Every field is null while the server is idle.
public struct Live: Decodable, Encodable, Sendable, Equatable {
    public var state: LiveState?
    public var queued: Int?
    public var phase: String?
    public var promptTokens: Double?
    public var promptRead: Double?
    public var promptTotal: Double?
    public var generated: Double?
    public var maxTokens: Double?
    public var elapsedS: Double?
    public var tokS: Double?
    public var tokSMean: Double?
    public var prefillTokSMean: Double?
    public var tokSWindowS: Double?
    /// Basalt: the parallel request slots, busy and total.
    public var slots: LiveSlots?
    /// Basalt: requests waiting for a free slot, oldest first.
    public var queue: [QueuedRequest]?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedState = try? c.decode(LiveState.self, forKey: .state)
        if case .some(.other(let raw)) = decodedState, raw.isEmpty { state = nil } else { state = decodedState }
        queued = c.decodeInt(forKey: .queued)
        phase = c.decodeString(forKey: .phase)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        promptRead = c.decodeDouble(forKey: .promptRead)
        promptTotal = c.decodeDouble(forKey: .promptTotal)
        generated = c.decodeDouble(forKey: .generated)
        maxTokens = c.decodeDouble(forKey: .maxTokens)
        elapsedS = c.decodeDouble(forKey: .elapsedS)
        tokS = c.decodeDouble(forKey: .tokS)
        tokSMean = c.decodeDouble(forKey: .tokSMean)
        prefillTokSMean = c.decodeDouble(forKey: .prefillTokSMean)
        tokSWindowS = c.decodeDouble(forKey: .tokSWindowS)
        slots = try? c.decode(LiveSlots.self, forKey: .slots)
        queue = c.decodeArray(QueuedRequest.self, forKey: .queue)
    }

    private enum CodingKeys: String, CodingKey {
        case state, queued, phase, generated, slots, queue
        case promptTokens = "prompt_tokens"
        case promptRead = "prompt_read"
        case promptTotal = "prompt_total"
        case maxTokens = "max_tokens"
        case elapsedS = "elapsed_s"
        case tokS = "tok_s"
        case tokSMean = "tok_s_mean"
        case prefillTokSMean = "prefill_tok_s_mean"
        case tokSWindowS = "tok_s_window_s"
    }

    /// Requests waiting behind the running one.
    public var queuedCount: Int { queued ?? 0 }

    /// More than one request can run at once (Basalt with `batch_slots` > 1).
    public var isMultiSlot: Bool { (slots?.total ?? 0) > 1 }
}

/// Basalt's `live.slots`: how many parallel slots exist and how many are busy.
public struct LiveSlots: Decodable, Encodable, Sendable, Equatable {
    public var total: Int?
    public var active: Int?
    public var queueDepth: Int?

    public init(total: Int? = nil, active: Int? = nil, queueDepth: Int? = nil) {
        self.total = total
        self.active = active
        self.queueDepth = queueDepth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.decodeInt(forKey: .total)
        active = c.decodeInt(forKey: .active)
        queueDepth = c.decodeInt(forKey: .queueDepth)
    }

    private enum CodingKeys: String, CodingKey {
        case total, active
        case queueDepth = "queue_depth"
    }
}

/// One request waiting for a slot, as Basalt lists it in `live.queue`.
public struct QueuedRequest: Decodable, Encodable, Sendable, Equatable {
    public var waitedS: Double?
    /// "openai" | "anthropic"
    public var api: String?
    public var model: String?
    public var promptTokens: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waitedS = c.decodeDouble(forKey: .waitedS)
        api = c.decodeString(forKey: .api)
        model = c.decodeString(forKey: .model)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case api, model
        case waitedS = "waited_s"
        case promptTokens = "prompt_tokens"
    }
}

// MARK: - requests

/// `stop | length | cancel | disconnect | error`; anything else is kept as `other`.
public enum RequestFinish: Codable, Equatable, Sendable {
    case stop
    case length
    case cancel
    case disconnect
    case error
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = RequestFinish(rawValue: raw) ?? .other(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "stop": self = .stop
        case "length": self = .length
        case "cancel": self = .cancel
        case "disconnect": self = .disconnect
        case "error": self = .error
        case "": return nil
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .stop: "stop"
        case .length: "length"
        case .cancel: "cancel"
        case .disconnect: "disconnect"
        case .error: "error"
        case .other(let value): value
        }
    }
}

/// One kept request. Newest first in the payload.
public struct Request: Decodable, Encodable, Identifiable, Sendable, Equatable {
    /// Stable identity derived from `time` (a random id when the server omits it).
    public let id: String

    public var time: Double?
    public var durationS: Double?
    public var finish: RequestFinish?
    public var promptTokens: Double?
    public var reused: Double?
    public var outputTokens: Double?
    public var promptTotal: Double?
    public var promptRead: Double?
    public var reasoningRecoveries: Double?
    public var reasoningRepeatCoverage: Double?
    public var engineGenerated: Double?
    public var promptMs: Double?
    public var decodeMs: Double?
    public var decodeTokS: Double?
    public var hitRate: Double?
    public var pcieShare: Double?
    public var ramBlobs: Double?
    public var fileBlobs: Double?
    public var fileMb: Double?
    public var draftsOffered: Double?
    public var draftsAccepted: Double?
    /// Experimental speed projection for this request (nil when the server does not report it).
    public var projection: Bool?
    /// Basalt: the server's own id ("r_1638") and the endpoint that was called.
    public var requestID: String?
    public var path: String?

    public init(id: String = UUID().uuidString) { self.id = id }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = c.decodeDouble(forKey: .time)
        durationS = c.decodeDouble(forKey: .durationS)
        finish = RequestFinish(rawValue: c.decodeString(forKey: .finish) ?? "")
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        reused = c.decodeDouble(forKey: .reused)
        outputTokens = c.decodeDouble(forKey: .outputTokens)
        promptTotal = c.decodeDouble(forKey: .promptTotal)
        promptRead = c.decodeDouble(forKey: .promptRead)
        reasoningRecoveries = c.decodeDouble(forKey: .reasoningRecoveries)
        reasoningRepeatCoverage = c.decodeDouble(forKey: .reasoningRepeatCoverage)
        engineGenerated = c.decodeDouble(forKey: .engineGenerated)
        promptMs = c.decodeDouble(forKey: .promptMs)
        decodeMs = c.decodeDouble(forKey: .decodeMs)
        decodeTokS = c.decodeDouble(forKey: .decodeTokS)
        hitRate = c.decodeDouble(forKey: .hitRate)
        pcieShare = c.decodeDouble(forKey: .pcieShare)
        ramBlobs = c.decodeDouble(forKey: .ramBlobs)
        fileBlobs = c.decodeDouble(forKey: .fileBlobs)
        fileMb = c.decodeDouble(forKey: .fileMb)
        draftsOffered = c.decodeDouble(forKey: .draftsOffered)
        draftsAccepted = c.decodeDouble(forKey: .draftsAccepted)
        projection = c.decodeBool(forKey: .projection)
        requestID = c.decodeString(forKey: .requestID)
        path = c.decodeString(forKey: .path)
        id = time.map { String($0) } ?? UUID().uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case time, finish, reused, projection, path
        case requestID = "id"
        case durationS = "duration_s"
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case promptTotal = "prompt_total"
        case promptRead = "prompt_read"
        case reasoningRecoveries = "reasoning_recoveries"
        case reasoningRepeatCoverage = "reasoning_repeat_coverage"
        case engineGenerated = "engine_generated"
        case promptMs = "prompt_ms"
        case decodeMs = "decode_ms"
        case decodeTokS = "decode_tok_s"
        case hitRate = "hit_rate"
        case pcieShare = "pcie_share"
        case ramBlobs = "ram_blobs"
        case fileBlobs = "file_blobs"
        case fileMb = "file_mb"
        case draftsOffered = "drafts_offered"
        case draftsAccepted = "drafts_accepted"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(time, forKey: .time)
        try c.encodeIfPresent(durationS, forKey: .durationS)
        try c.encodeIfPresent(finish?.rawValue, forKey: .finish)
        try c.encodeIfPresent(promptTokens, forKey: .promptTokens)
        try c.encodeIfPresent(reused, forKey: .reused)
        try c.encodeIfPresent(outputTokens, forKey: .outputTokens)
        try c.encodeIfPresent(promptTotal, forKey: .promptTotal)
        try c.encodeIfPresent(promptRead, forKey: .promptRead)
        try c.encodeIfPresent(reasoningRecoveries, forKey: .reasoningRecoveries)
        try c.encodeIfPresent(reasoningRepeatCoverage, forKey: .reasoningRepeatCoverage)
        try c.encodeIfPresent(engineGenerated, forKey: .engineGenerated)
        try c.encodeIfPresent(promptMs, forKey: .promptMs)
        try c.encodeIfPresent(decodeMs, forKey: .decodeMs)
        try c.encodeIfPresent(decodeTokS, forKey: .decodeTokS)
        try c.encodeIfPresent(hitRate, forKey: .hitRate)
        try c.encodeIfPresent(pcieShare, forKey: .pcieShare)
        try c.encodeIfPresent(ramBlobs, forKey: .ramBlobs)
        try c.encodeIfPresent(fileBlobs, forKey: .fileBlobs)
        try c.encodeIfPresent(fileMb, forKey: .fileMb)
        try c.encodeIfPresent(draftsOffered, forKey: .draftsOffered)
        try c.encodeIfPresent(draftsAccepted, forKey: .draftsAccepted)
        try c.encodeIfPresent(projection, forKey: .projection)
        try c.encodeIfPresent(requestID, forKey: .requestID)
        try c.encodeIfPresent(path, forKey: .path)
    }
}

// MARK: - conversation cache

public struct ConversationCache: Decodable, Encodable, Sendable, Equatable {
    public var enabled: Bool?
    public var budgetMib: Double?
    public var slots: Double?
    public var parked: Double?
    public var bytes: Double?
    public var evictions: Double?
    public var parks: Double?
    public var restores: Double?
    public var lastEvent: String?
    public var lastTokens: Double?
    public var lastAt: Double?
    public var requests: Double?
    public var requestsReused: Double?
    public var reusedTokens: Double?
    public var promptTokens: Double?
    public var lastReused: Double?
    public var lastPrompt: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.decodeBool(forKey: .enabled)
        budgetMib = c.decodeDouble(forKey: .budgetMib)
        slots = c.decodeDouble(forKey: .slots)
        parked = c.decodeDouble(forKey: .parked)
        bytes = c.decodeDouble(forKey: .bytes)
        evictions = c.decodeDouble(forKey: .evictions)
        parks = c.decodeDouble(forKey: .parks)
        restores = c.decodeDouble(forKey: .restores)
        lastEvent = c.decodeString(forKey: .lastEvent)
        lastTokens = c.decodeDouble(forKey: .lastTokens)
        lastAt = c.decodeDouble(forKey: .lastAt)
        requests = c.decodeDouble(forKey: .requests)
        requestsReused = c.decodeDouble(forKey: .requestsReused)
        reusedTokens = c.decodeDouble(forKey: .reusedTokens)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        lastReused = c.decodeDouble(forKey: .lastReused)
        lastPrompt = c.decodeDouble(forKey: .lastPrompt)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, slots, parked, bytes, evictions, parks, restores, requests
        case budgetMib = "budget_mib"
        case lastEvent = "last_event"
        case lastTokens = "last_tokens"
        case lastAt = "last_at"
        case requestsReused = "requests_reused"
        case reusedTokens = "reused_tokens"
        case promptTokens = "prompt_tokens"
        case lastReused = "last_reused"
        case lastPrompt = "last_prompt"
    }
}

// MARK: - totals

public struct Totals: Decodable, Encodable, Sendable, Equatable {
    /// Unix seconds of the first counted request.
    public var since: Double?
    public var requests: Double?
    public var promptTokens: Double?
    public var reused: Double?
    public var outputTokens: Double?
    public var promptMs: Double?
    public var decodeMs: Double?
    public var draftsOffered: Double?
    public var draftsAccepted: Double?
    public var toolCallsFromReasoning: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        since = c.decodeDouble(forKey: .since)
        requests = c.decodeDouble(forKey: .requests)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        reused = c.decodeDouble(forKey: .reused)
        outputTokens = c.decodeDouble(forKey: .outputTokens)
        promptMs = c.decodeDouble(forKey: .promptMs)
        decodeMs = c.decodeDouble(forKey: .decodeMs)
        draftsOffered = c.decodeDouble(forKey: .draftsOffered)
        draftsAccepted = c.decodeDouble(forKey: .draftsAccepted)
        toolCallsFromReasoning = c.decodeDouble(forKey: .toolCallsFromReasoning)
    }

    private enum CodingKeys: String, CodingKey {
        case since, requests, reused
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case promptMs = "prompt_ms"
        case decodeMs = "decode_ms"
        case draftsOffered = "drafts_offered"
        case draftsAccepted = "drafts_accepted"
        case toolCallsFromReasoning = "tool_calls_from_reasoning"
    }
}

// MARK: - hardware

public struct GPU: Decodable, Encodable, Sendable, Equatable {
    public var index: Int?
    public var util: Double?
    public var memUsed: Double?
    public var memTotal: Double?
    public var temp: Double?
    public var power: Double?
    /// Basalt reports these per card; Strata only as `gpu_*` totals.
    public var powerLimit: Double?
    public var pcieGen: Int?
    public var pcieGenMax: Int?
    public var pcieWidth: Int?
    public var pcieRxMb: Double?
    public var pcieTxMb: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = c.decodeInt(forKey: .index)
        powerLimit = c.decodeDouble(forKey: .powerLimit)
        pcieGen = c.decodeInt(forKey: .pcieGen)
        pcieGenMax = c.decodeInt(forKey: .pcieGenMax)
        pcieWidth = c.decodeInt(forKey: .pcieWidth)
        pcieRxMb = c.decodeDouble(forKey: .pcieRxMb)
        pcieTxMb = c.decodeDouble(forKey: .pcieTxMb)
        util = c.decodeDouble(forKey: .util)
        memUsed = c.decodeDouble(forKey: .memUsed)
        memTotal = c.decodeDouble(forKey: .memTotal)
        temp = c.decodeDouble(forKey: .temp)
        power = c.decodeDouble(forKey: .power)
    }

    private enum CodingKeys: String, CodingKey {
        case index, util, temp, power
        case memUsed = "mem_used"
        case memTotal = "mem_total"
        case powerLimit = "power_limit"
        case pcieGen = "pcie_gen"
        case pcieGenMax = "pcie_gen_max"
        case pcieWidth = "pcie_width"
        case pcieRxMb = "pcie_rx_mb"
        case pcieTxMb = "pcie_tx_mb"
    }
}

public struct Hardware: Decodable, Encodable, Sendable, Equatable {
    public var gpus: [GPU]?
    public var gpuUtil: Double?
    public var gpuMemUsed: Double?
    public var gpuMemTotal: Double?
    public var gpuTemp: Double?
    public var gpuPower: Double?
    public var gpuPowerLimit: Double?
    public var gpuPcieGen: Int?
    public var gpuPcieGenMax: Int?
    public var gpuPcieWidth: Int?
    public var gpuPcieRxMb: Double?
    public var gpuPcieTxMb: Double?
    public var cpu: Double?
    public var ramUsed: Double?
    public var ramTotal: Double?
    public var diskReadMb: Double?
    public var diskWriteMb: Double?
    public var tokS: Double?
    public var tokSMean: Double?
    public var prefillTokSMean: Double?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gpus = c.decodeArray(GPU.self, forKey: .gpus)
        gpuUtil = c.decodeDouble(forKey: .gpuUtil)
        gpuMemUsed = c.decodeDouble(forKey: .gpuMemUsed)
        gpuMemTotal = c.decodeDouble(forKey: .gpuMemTotal)
        gpuTemp = c.decodeDouble(forKey: .gpuTemp)
        gpuPower = c.decodeDouble(forKey: .gpuPower)
        gpuPowerLimit = c.decodeDouble(forKey: .gpuPowerLimit)
        gpuPcieGen = c.decodeInt(forKey: .gpuPcieGen)
        gpuPcieGenMax = c.decodeInt(forKey: .gpuPcieGenMax)
        gpuPcieWidth = c.decodeInt(forKey: .gpuPcieWidth)
        gpuPcieRxMb = c.decodeDouble(forKey: .gpuPcieRxMb)
        gpuPcieTxMb = c.decodeDouble(forKey: .gpuPcieTxMb)
        cpu = c.decodeDouble(forKey: .cpu)
        ramUsed = c.decodeDouble(forKey: .ramUsed)
        ramTotal = c.decodeDouble(forKey: .ramTotal)
        diskReadMb = c.decodeDouble(forKey: .diskReadMb)
        diskWriteMb = c.decodeDouble(forKey: .diskWriteMb)
        tokS = c.decodeDouble(forKey: .tokS)
        tokSMean = c.decodeDouble(forKey: .tokSMean)
        prefillTokSMean = c.decodeDouble(forKey: .prefillTokSMean)
    }

    private enum CodingKeys: String, CodingKey {
        case gpus, cpu
        case gpuUtil = "gpu_util"
        case gpuMemUsed = "gpu_mem_used"
        case gpuMemTotal = "gpu_mem_total"
        case gpuTemp = "gpu_temp"
        case gpuPower = "gpu_power"
        case gpuPowerLimit = "gpu_power_limit"
        case gpuPcieGen = "gpu_pcie_gen"
        case gpuPcieGenMax = "gpu_pcie_gen_max"
        case gpuPcieWidth = "gpu_pcie_width"
        case gpuPcieRxMb = "gpu_pcie_rx_mb"
        case gpuPcieTxMb = "gpu_pcie_tx_mb"
        case ramUsed = "ram_used"
        case ramTotal = "ram_total"
        case diskReadMb = "disk_read_mb"
        case diskWriteMb = "disk_write_mb"
        case tokS = "tok_s"
        case tokSMean = "tok_s_mean"
        case prefillTokSMean = "prefill_tok_s_mean"
    }

    /// More than one GPU: the metric subtitles list each card (issue #112).
    public var isMultiGPU: Bool { (gpus?.count ?? 0) > 1 }

    /// The `gpu_*` totals worked out from `gpus` wherever the server left them out, the way
    /// Strata adds them up: mean load, summed memory / power / PCIe traffic, the hottest card,
    /// the slowest link. A total the server did send is kept as it is.
    func fillingTotals() -> Hardware {
        guard let gpus, !gpus.isEmpty else { return self }
        func values<T>(_ key: (GPU) -> T?) -> [T] { gpus.compactMap(key) }
        func sum(_ key: (GPU) -> Double?) -> Double? { values(key).isEmpty ? nil : values(key).reduce(0, +) }
        var out = self
        if out.gpuUtil == nil, !values(\.util).isEmpty {
            out.gpuUtil = values(\.util).reduce(0, +) / Double(values(\.util).count)
        }
        out.gpuMemUsed = out.gpuMemUsed ?? sum(\.memUsed)
        out.gpuMemTotal = out.gpuMemTotal ?? sum(\.memTotal)
        out.gpuTemp = out.gpuTemp ?? values(\.temp).max()
        out.gpuPower = out.gpuPower ?? sum(\.power)
        out.gpuPowerLimit = out.gpuPowerLimit ?? sum(\.powerLimit)
        out.gpuPcieGen = out.gpuPcieGen ?? values(\.pcieGen).min()
        out.gpuPcieGenMax = out.gpuPcieGenMax ?? values(\.pcieGenMax).min()
        out.gpuPcieWidth = out.gpuPcieWidth ?? values(\.pcieWidth).min()
        out.gpuPcieRxMb = out.gpuPcieRxMb ?? sum(\.pcieRxMb)
        out.gpuPcieTxMb = out.gpuPcieTxMb ?? sum(\.pcieTxMb)
        return out
    }
}

/// Basalt's `hardware_static.gpus[]`: which card is which.
public struct GPUInfo: Decodable, Encodable, Sendable, Equatable {
    public var index: Int?
    public var name: String?

    public init(index: Int? = nil, name: String? = nil) {
        self.index = index
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = c.decodeInt(forKey: .index)
        name = c.decodeString(forKey: .name)
    }

    private enum CodingKeys: String, CodingKey { case index, name }
}

public struct HardwareStatic: Decodable, Encodable, Sendable, Equatable {
    public var gpuName: String?
    public var gpuCount: Int?
    public var cpuName: String?
    public var cores: Int?
    public var threads: Int?
    public var psutil: Bool?
    /// Basalt: each card by name, the NVIDIA driver and the CUDA version.
    public var gpus: [GPUInfo]?
    public var driver: String?
    public var cuda: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gpuName = c.decodeString(forKey: .gpuName)
        gpuCount = c.decodeInt(forKey: .gpuCount)
        cpuName = c.decodeString(forKey: .cpuName)
        cores = c.decodeInt(forKey: .cores)
        threads = c.decodeInt(forKey: .threads)
        psutil = c.decodeBool(forKey: .psutil)
        gpus = c.decodeArray(GPUInfo.self, forKey: .gpus)
        driver = c.decodeString(forKey: .driver)
        cuda = c.decodeString(forKey: .cuda)
    }

    /// `gpu_name` / `gpu_count` from `gpus` when the server sent only the list (Basalt):
    /// "NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti", like Strata spells it.
    func fillingNames() -> HardwareStatic {
        guard let gpus, !gpus.isEmpty else { return self }
        var out = self
        let names = gpus.sorted { ($0.index ?? 0) < ($1.index ?? 0) }.compactMap(\.name)
        if out.gpuName == nil, !names.isEmpty { out.gpuName = names.joined(separator: " + ") }
        out.gpuCount = out.gpuCount ?? gpus.count
        return out
    }

    private enum CodingKeys: String, CodingKey {
        case cores, threads, psutil, gpus, driver, cuda
        case gpuName = "gpu_name"
        case gpuCount = "gpu_count"
        case cpuName = "cpu_name"
    }
}

// MARK: - history

/// ~60 samples per series, oldest first. Nulls arrive as 0 so a sparkline can still draw.
public struct History: Decodable, Encodable, Sendable, Equatable {
    public var tokS: [Double]?
    public var prefillTokSMean: [Double]?
    public var gpuUtil: [Double]?
    public var gpuMemUsed: [Double]?
    public var gpuTemp: [Double]?
    public var gpuPower: [Double]?
    public var gpuPcieRxMb: [Double]?
    public var cpu: [Double]?
    public var ramUsed: [Double]?
    public var diskReadMb: [Double]?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokS = c.decodeDoubleArray(forKey: .tokS)
        prefillTokSMean = c.decodeDoubleArray(forKey: .prefillTokSMean)
        gpuUtil = c.decodeDoubleArray(forKey: .gpuUtil)
        gpuMemUsed = c.decodeDoubleArray(forKey: .gpuMemUsed)
        gpuTemp = c.decodeDoubleArray(forKey: .gpuTemp)
        gpuPower = c.decodeDoubleArray(forKey: .gpuPower)
        gpuPcieRxMb = c.decodeDoubleArray(forKey: .gpuPcieRxMb)
        cpu = c.decodeDoubleArray(forKey: .cpu)
        ramUsed = c.decodeDoubleArray(forKey: .ramUsed)
        diskReadMb = c.decodeDoubleArray(forKey: .diskReadMb)
    }

    private enum CodingKeys: String, CodingKey {
        case cpu
        case tokS = "tok_s"
        case prefillTokSMean = "prefill_tok_s_mean"
        case gpuUtil = "gpu_util"
        case gpuMemUsed = "gpu_mem_used"
        case gpuTemp = "gpu_temp"
        case gpuPower = "gpu_power"
        case gpuPcieRxMb = "gpu_pcie_rx_mb"
        case ramUsed = "ram_used"
        case diskReadMb = "disk_read_mb"
    }
}

import Foundation

/// Which engine answers at the address. Both speak `/health`, `/metrics` and `/v1`; Basalt
/// adds parallel slots and a log feed and has no run config.
public enum ServerEngine: String, Sendable, Equatable {
    case strata
    case basalt

    /// From `/health`'s `service`. Anything that is not Basalt is treated as Strata, which is
    /// what every server said before the field mattered.
    public init(service: String?) {
        self = service?.lowercased() == "basalt" ? .basalt : .strata
    }

    public var name: String {
        switch self {
        case .strata: "Strata"
        case .basalt: "Basalt"
        }
    }

    /// `GET /config` exists — the Config tab is only offered when it does.
    public var hasRunConfig: Bool { self == .strata }

    /// `GET /api/logs` exists.
    public var hasLogs: Bool { self == .basalt }
}

extension Health {
    public var engine: ServerEngine { ServerEngine(service: service) }
}

// MARK: - /slots

/// `idle | prefill | decoding`; anything else is kept as `other`.
public enum SlotState: Equatable, Sendable {
    case idle
    case prefill
    case decoding
    case other(String)

    public init(rawValue: String?) {
        switch rawValue {
        case "idle", nil: self = .idle
        case "prefill": self = .prefill
        case "decoding": self = .decoding
        case let value?: self = .other(value)
        }
    }

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .prefill: "Prefill"
        case .decoding: "Decoding"
        case .other(let value): value.prefix(1).uppercased() + value.dropFirst()
        }
    }
}

/// One of Basalt's parallel request slots, from `GET /slots`.
public struct Slot: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var nCtx: Double?
    public var isProcessing: Bool?
    public var state: SlotState
    /// "openai" | "anthropic"
    public var api: String?
    public var model: String?
    public var tokS: Double?
    public var generated: Double?
    public var promptTokens: Double?
    public var prefillDone: Double?
    public var ctxUsed: Double?
    public var draftsOffered: Double?
    public var draftsAccepted: Double?

    public init(id: Int, state: SlotState = .idle) {
        self.id = id
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(forKey: .id) ?? 0
        nCtx = c.decodeDouble(forKey: .nCtx)
        isProcessing = c.decodeBool(forKey: .isProcessing)
        state = SlotState(rawValue: c.decodeString(forKey: .state))
        api = c.decodeString(forKey: .api)
        model = c.decodeString(forKey: .model)
        tokS = c.decodeDouble(forKey: .tokS)
        generated = c.decodeDouble(forKey: .generated)
        promptTokens = c.decodeDouble(forKey: .promptTokens)
        prefillDone = c.decodeDouble(forKey: .prefillDone)
        ctxUsed = c.decodeDouble(forKey: .ctxUsed)
        draftsOffered = c.decodeDouble(forKey: .draftsOffered)
        draftsAccepted = c.decodeDouble(forKey: .draftsAccepted)
    }

    private enum CodingKeys: String, CodingKey {
        case id, state, api, model, generated
        case nCtx = "n_ctx"
        case isProcessing = "is_processing"
        case tokS = "tok_s"
        case promptTokens = "prompt_tokens"
        case prefillDone = "prefill_done"
        case ctxUsed = "ctx_used"
        case draftsOffered = "drafts_offered"
        case draftsAccepted = "drafts_accepted"
    }
}

// MARK: - /api/logs

/// `info | warn | err`; anything else reads as info.
public enum LogLevel: String, Sendable, Equatable, CaseIterable {
    case info
    case warn
    case err
}

/// One server log line.
public struct LogLine: Decodable, Sendable, Equatable, Identifiable {
    public var id: Int
    /// Unix seconds.
    public var time: Double?
    /// Which part of the server wrote it ("srv", "eng").
    public var source: String?
    public var level: LogLevel
    public var message: String

    public init(id: Int, time: Double? = nil, source: String? = nil, level: LogLevel = .info, message: String) {
        self.id = id
        self.time = time
        self.source = source
        self.level = level
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(forKey: .id) ?? 0
        time = c.decodeDouble(forKey: .time)
        source = c.decodeString(forKey: .source)
        level = LogLevel(rawValue: c.decodeString(forKey: .level) ?? "") ?? .info
        message = c.decodeString(forKey: .message) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case time = "t"
        case source = "src"
        case level = "lvl"
        case message = "msg"
    }
}

/// `GET /api/logs?after=N`: the lines after id N, and the newest id. A `last` below the one
/// asked for means the server restarted and its ids began again.
public struct LogBatch: Decodable, Sendable, Equatable {
    public var lines: [LogLine]
    public var last: Int

    public init(lines: [LogLine], last: Int) {
        self.lines = lines
        self.last = last
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = c.decodeArray(LogLine.self, forKey: .lines) ?? []
        last = c.decodeInt(forKey: .last) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case lines, last }
}

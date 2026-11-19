import Foundation

/// `GET /health` — no auth.
public struct Health: Decodable, Encodable, Sendable, Equatable {
    public var status: String?
    public var maxContext: Double?
    public var model: String?
    /// oMLX's name for the resident model; `model` falls back to it.
    public var defaultModel: String?
    public var images: Bool?
    /// True when the server requires an API key.
    public var apiKey: Bool?
    public var loaded: Bool?
    public var service: String?
    /// oMLX: the models discovered and loaded, and the memory ceiling. Its presence is what tells
    /// this server apart from Strata and Basalt, which never send it.
    public var enginePool: EnginePool?

    /// `engine_pool`: oMLX's own summary of the pool.
    public struct EnginePool: Decodable, Encodable, Sendable, Equatable {
        public var modelCount: Int?
        public var loadedCount: Int?
        public var finalCeiling: Double?
        public var currentModelMemory: Double?

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            modelCount = c.decodeInt(forKey: .modelCount)
            loadedCount = c.decodeInt(forKey: .loadedCount)
            finalCeiling = c.decodeDouble(forKey: .finalCeiling)
            currentModelMemory = c.decodeDouble(forKey: .currentModelMemory)
        }

        private enum CodingKeys: String, CodingKey {
            case modelCount = "model_count"
            case loadedCount = "loaded_count"
            case finalCeiling = "final_ceiling"
            case currentModelMemory = "current_model_memory"
        }
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = c.decodeString(forKey: .status)
        maxContext = c.decodeDouble(forKey: .maxContext)
        enginePool = try? c.decode(EnginePool.self, forKey: .enginePool)
        // oMLX calls its resident model `default_model`; the pool's count says whether one is in.
        defaultModel = c.decodeString(forKey: .defaultModel)
        model = c.decodeString(forKey: .model) ?? defaultModel
        images = c.decodeBool(forKey: .images)
        apiKey = c.decodeBool(forKey: .apiKey)
        loaded = c.decodeBool(forKey: .loaded) ?? enginePool?.loadedCount.map { $0 > 0 }
        service = c.decodeString(forKey: .service)
    }

    private enum CodingKeys: String, CodingKey {
        case status, model, images, loaded, service
        case maxContext = "max_context"
        case apiKey = "api_key"
        case enginePool = "engine_pool"
        case defaultModel = "default_model"
    }

    /// Strata says `ok`, oMLX says `healthy`.
    public var isOK: Bool { status == "ok" || status == "healthy" }
}

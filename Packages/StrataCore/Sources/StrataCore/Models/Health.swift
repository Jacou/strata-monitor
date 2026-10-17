import Foundation

/// `GET /health` — no auth.
public struct Health: Decodable, Encodable, Sendable, Equatable {
    public var status: String?
    public var maxContext: Double?
    public var model: String?
    public var images: Bool?
    /// True when the server requires an API key.
    public var apiKey: Bool?
    public var loaded: Bool?
    public var service: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = c.decodeString(forKey: .status)
        maxContext = c.decodeDouble(forKey: .maxContext)
        model = c.decodeString(forKey: .model)
        images = c.decodeBool(forKey: .images)
        apiKey = c.decodeBool(forKey: .apiKey)
        loaded = c.decodeBool(forKey: .loaded)
        service = c.decodeString(forKey: .service)
    }

    private enum CodingKeys: String, CodingKey {
        case status, model, images, loaded, service
        case maxContext = "max_context"
        case apiKey = "api_key"
    }

    public var isOK: Bool { status == "ok" }
}

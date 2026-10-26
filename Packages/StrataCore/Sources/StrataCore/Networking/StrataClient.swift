import Foundation

/// What can go wrong talking to a Strata server.
public enum StrataError: Error, Equatable, Sendable {
    /// 401: the server wants an API key (Settings).
    case unauthorized
    /// Any other non-2xx status.
    case http(Int)
    /// No connection, timeout, bad host, or a non-HTTP response.
    case unreachable
    /// The body arrived but did not decode.
    case decoding(String)
}

/// The one network call the client makes, behind a protocol so tests can stub it.
public protocol HTTPTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = StrataClient.defaultTimeout) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw StrataError.unreachable }
            return (data, http)
        } catch let error as StrataError {
            throw error
        } catch is URLError {
            throw StrataError.unreachable
        } catch {
            throw StrataError.unreachable
        }
    }
}

/// async/await client for `GET /health` and `GET /metrics`.
public struct StrataClient: Sendable {
    public static let defaultTimeout: TimeInterval = 5
    /// `POST /v1/chat/completions`, the path the web page's `send()` posts to.
    public static let chatPath = "v1/chat/completions"

    public var baseURL: URL
    public var apiKey: String?
    public var timeout: TimeInterval

    private let transport: any HTTPTransport
    /// Streaming is a different job from a 1 s poll, so it has its own transport.
    private let streamTransport: any ChatStreamTransport

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        timeout: TimeInterval = StrataClient.defaultTimeout,
        transport: (any HTTPTransport)? = nil,
        streamTransport: (any ChatStreamTransport)? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeout = timeout
        self.transport = transport ?? URLSessionTransport(timeout: timeout)
        self.streamTransport = streamTransport ?? URLSessionChatStreamTransport()
    }

    public func health() async throws -> Health {
        try await get(path: "health", query: [], as: Health.self)
    }

    /// `allRequests` mirrors the web page's "Show all": `metrics?requests=all`.
    public func metrics(allRequests: Bool = false) async throws -> Metrics {
        let query = allRequests ? [URLQueryItem(name: "requests", value: "all")] : []
        return try await get(path: "metrics", query: query, as: Metrics.self)
    }

    /// Basalt: `GET /slots`, one entry per parallel request slot.
    public func slots() async throws -> [Slot] {
        try await get(path: "slots", query: [], as: [Slot].self)
    }

    /// Basalt: `GET /api/logs?after=N`, the server log lines after id N (0 for the newest few hundred).
    public func logs(after: Int) async throws -> LogBatch {
        try await get(path: "api/logs", query: [URLQueryItem(name: "after", value: String(after))], as: LogBatch.self)
    }

    /// `GET /config`: the run-config keys this server will edit. 404 when it has no run config.
    public func config() async throws -> ConfigResponse {
        try await get(path: "config", query: [], as: ConfigResponse.self)
    }

    /// `POST /config` with `{"set": {key: value}}`. A rejected value comes back as
    /// `StrataServerError` carrying the server's own message, so the screen can show it.
    public func updateConfig(_ set: [String: ConfigValue]) async throws -> ConfigReply {
        let body: Data
        do {
            body = try JSONEncoder().encode(ConfigRequest(set: set))
        } catch {
            throw StrataError.decoding(String(describing: error))
        }
        guard let request = request(path: "config", method: "POST", body: body) else { throw StrataError.unreachable }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.fetch(request)
        } catch let error as StrataError {
            throw error
        } catch is URLError {
            throw StrataError.unreachable
        } catch {
            throw StrataError.unreachable
        }

        switch response.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(ConfigReply.self, from: data)
            } catch {
                throw StrataError.decoding(String(describing: error))
            }
        case 401:
            throw StrataError.unauthorized
        default:
            let reply = try? JSONDecoder().decode(ConfigReply.self, from: data)
            if let message = reply?.errorMessage, !message.isEmpty {
                throw StrataServerError(message: message, statusCode: response.statusCode)
            }
            throw StrataError.http(response.statusCode)
        }
    }

    // MARK: - chat

    /// `POST /v1/chat/completions` with `stream: true`: the answer as it arrives.
    ///
    /// Throws before the first token when the request itself failed (401, a rejected body);
    /// an error the engine reports mid-stream arrives as `ChatEvent.error`.
    public func chatStream(_ body: ChatRequestBody) async throws -> AsyncThrowingStream<ChatEvent, any Error> {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw StrataError.decoding(String(describing: error))
        }
        guard let request = chatRequest(body: payload) else { throw StrataError.unreachable }

        let stream = try await streamTransport.stream(request)
        return Self.eventStream(from: stream.lines)
    }

    /// Lines in, events out — the whole SSE half of the chat, testable on its own.
    public static func eventStream(
        from lines: AsyncThrowingStream<String, any Error>
    ) -> AsyncThrowingStream<ChatEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        if Task.isCancelled { break }
                        switch SSEParser.parse(line) {
                        case .data(let payload):
                            guard let chunk = ChatChunk.decode(payload) else { continue }   // a junk line is not fatal
                            for event in chunk.events { continuation.yield(event) }
                        case .done:
                            continuation.finish()
                            return
                        case .ignore:
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func chatRequest(body: Data) -> URLRequest? {
        guard var request = request(path: Self.chatPath, method: "POST", body: body) else { return nil }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = URLSessionChatStreamTransport.defaultTimeout
        return request
    }

    // MARK: - request building

    func request(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let base = components.path
        components.path = (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/" + path
        components.queryItems = query.isEmpty ? nil : query
        // An address pasted from the web page can carry "#stats"; it means nothing to the API.
        components.fragment = nil
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - fetch + decode

    private func get<T: Decodable>(path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {
        guard let request = request(path: path, query: query) else { throw StrataError.unreachable }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.fetch(request)
        } catch let error as StrataError {
            throw error
        } catch is URLError {
            throw StrataError.unreachable
        } catch {
            throw StrataError.unreachable
        }

        switch response.statusCode {
        case 200..<300: break
        case 401: throw StrataError.unauthorized
        default: throw StrataError.http(response.statusCode)
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw StrataError.decoding(String(describing: error))
        }
    }
}

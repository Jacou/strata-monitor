import Foundation

// Streaming transport for `POST /v1/chat/completions`.
//
// The monitor client is request/response (`HTTPTransport`); a chat answer arrives as a stream of
// SSE lines, so it gets its own transport behind its own protocol — the tests feed canned lines
// and never touch the network.

/// A live response: the HTTP headers, then the lines as they arrive.
public struct ChatLineStream: Sendable {
    public var response: HTTPURLResponse
    public var lines: AsyncThrowingStream<String, any Error>

    public init(response: HTTPURLResponse, lines: AsyncThrowingStream<String, any Error>) {
        self.response = response
        self.lines = lines
    }
}

public protocol ChatStreamTransport: Sendable {
    /// Throws `StrataError` / `StrataServerError` before the first line when the request failed.
    func stream(_ request: URLRequest) async throws -> ChatLineStream
}

public struct URLSessionChatStreamTransport: ChatStreamTransport {
    /// A chat request can sit in prefill far longer than a 1 s metrics poll.
    public static let defaultTimeout: TimeInterval = 300

    private let session: URLSession

    public init(timeout: TimeInterval = URLSessionChatStreamTransport.defaultTimeout) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func stream(_ request: URLRequest) async throws -> ChatLineStream {
        // `URLSession.Bytes` is not a nameable type, so the bindings stay inside this scope.
        do {
            let (bytes, urlResponse) = try await session.bytes(for: request)

            guard let http = urlResponse as? HTTPURLResponse else { throw StrataError.unreachable }

            if !(200..<300).contains(http.statusCode) {
                // An error body is short; 64 KB is plenty and keeps a broken server streaming forever.
                var body = Data()
                do {
                    for try await byte in bytes {
                        body.append(byte)
                        if body.count >= 65_536 { break }
                    }
                } catch {}
                throw Self.error(forStatus: http.statusCode, body: String(decoding: body, as: UTF8.self))
            }

            let lines = AsyncThrowingStream<String, any Error> { continuation in
                let task = Task {
                    do {
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish()
                    } catch let error as StrataError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: StrataError.unreachable)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }

            return ChatLineStream(response: http, lines: lines)
        } catch let error as StrataError {
            throw error
        } catch let error as StrataServerError {
            throw error
        } catch is URLError {
            throw StrataError.unreachable
        } catch {
            throw StrataError.unreachable
        }
    }

    /// `HTTP 400` is useless; the server's own `{"error": {"message": …}}` is not.
    static func error(forStatus status: Int, body: String) -> any Error {
        if status == 401 { return StrataError.unauthorized }
        if let message = errorMessage(in: body), !message.isEmpty {
            return StrataServerError(message: message, statusCode: status)
        }
        return StrataError.http(status)
    }

    private static func errorMessage(in body: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return nil }
        switch json["error"] {
        case let message as String: return message
        case let object as [String: Any]: return object["message"] as? String
        default: return nil
        }
    }
}

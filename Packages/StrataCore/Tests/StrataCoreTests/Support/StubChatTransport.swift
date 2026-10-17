import Foundation
@testable import StrataCore

/// Stands in for the streaming half of URLSession: canned SSE lines, no network.
final class StubChatTransport: ChatStreamTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let responder: @Sendable (URLRequest) throws -> ChatLineStream

    init(_ responder: @escaping @Sendable (URLRequest) throws -> ChatLineStream) {
        self.responder = responder
    }

    func stream(_ request: URLRequest) async throws -> ChatLineStream {
        requests.append(request)
        return try responder(request)
    }
}

extension StubChatTransport {
    /// A stream that ends after the last line, as a finished answer does.
    static func sse(_ lines: [String], status: Int = 200) -> StubChatTransport {
        StubChatTransport { request in
            ChatLineStream(
                response: httpResponse(request.url ?? URL(string: "http://192.168.1.10:8081")!, status),
                lines: Self.finished(lines)
            )
        }
    }

    /// The request fails before the first token.
    static func failing(_ error: any Error) -> StubChatTransport {
        StubChatTransport { _ in throw error }
    }

    /// Lines that keep coming until the reader cancels them — what a Stop button meets.
    static func endless(every: TimeInterval = 0.02) -> StubChatTransport {
        StubChatTransport { request in
            let response = httpResponse(request.url ?? URL(string: "http://192.168.1.10:8081")!, 200)
            let lines = AsyncThrowingStream<String, any Error> { continuation in
                let task = Task {
                    while !Task.isCancelled {
                        continuation.yield(#"data: {"choices":[{"delta":{"content":"…"}}]}"#)
                        try await Task.sleep(nanoseconds: UInt64(every * 1_000_000_000))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return ChatLineStream(response: response, lines: lines)
        }
    }

    static func finished(_ lines: [String]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
    }
}

/// Collects a stream to an array, for the assertions.
func collect(_ stream: AsyncThrowingStream<ChatEvent, any Error>) async throws -> [ChatEvent] {
    var out: [ChatEvent] = []
    for try await event in stream { out.append(event) }
    return out
}

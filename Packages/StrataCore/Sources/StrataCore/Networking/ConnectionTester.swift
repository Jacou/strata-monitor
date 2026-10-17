import Foundation
import Observation

/// "Test connection" on the Settings screen: /health first (no auth), then /metrics (with the key).
@Observable @MainActor
public final class ConnectionTester {
    public enum State: Equatable, Sendable {
        case idle
        case testing
        case ok(model: String?)
        case failed(String)

        public var text: String {
            switch self {
            case .idle: ""
            case .testing: "Testing…"
            case .ok(let model): model.map { "✓ \($0)" } ?? "✓ Connected"
            case .failed(let reason): reason
            }
        }

        public var isOK: Bool { if case .ok = self { true } else { false } }
    }

    public private(set) var state: State = .idle

    public init() {}

    public func run(client: StrataClient) async {
        state = .testing
        do {
            let health = try await client.health()
            let metrics = try await client.metrics()
            state = .ok(model: metrics.engine?.model ?? health.model)
        } catch let error as StrataError {
            state = .failed(error.plainWords)
        } catch {
            state = .failed(StrataError.unreachable.plainWords)
        }
    }

    public func reset() { state = .idle }

    /// A local problem (bad address) reported in the same voice as a server error.
    public func fail(_ message: String) { state = .failed(message) }
}

extension StrataError {
    /// What to show a human instead of an error enum.
    public var plainWords: String {
        switch self {
        case .unauthorized: "Wrong or missing API key"
        case .http(let code): "Server replied HTTP \(code)"
        case .unreachable: "Server not reachable — check the address, and that the PC is on"
        case .decoding: "The server replied something the app could not read"
        }
    }
}

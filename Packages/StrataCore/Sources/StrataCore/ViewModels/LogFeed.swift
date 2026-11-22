import Foundation
import Observation

/// The server log, as the web pages tail it, every couple of seconds while the Logs screen is
/// open: Basalt's `GET /api/logs?after=N`, or the tail of oMLX's `server.log`
/// (`GET /admin/api/logs?lines=N`, numbered by line). The newest lines are kept, filtered by level
/// and text.
@Observable @MainActor
public final class LogFeed {
    /// Which lines to show — the web page's All / Warnings / Errors.
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all
        case warnings
        case errors

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .all: "All"
            case .warnings: "Warnings"
            case .errors: "Errors"
            }
        }

        /// "Warnings" means anything above info, errors included, like the web page.
        public func passes(_ level: LogLevel) -> Bool {
            switch self {
            case .all: true
            case .warnings: level != .info
            case .errors: level == .err
            }
        }
    }

    /// More than a screen's worth, few enough to stay cheap.
    public static let maxLines = 500
    public static let pollInterval: TimeInterval = 2

    public private(set) var lines: [LogLine] = []
    /// nil until the first fetch; the reason the last fetch failed otherwise.
    public private(set) var errorText: String?
    public private(set) var hasLoaded = false
    public var filter: Filter = .all
    public var query = ""
    /// Which engine's log endpoint to read.
    public var engine: ServerEngine = .basalt
    /// oMLX sends the tail, not what came after an id: this many lines a fetch is plenty at 2 s.
    static let omlxTailLines = 300

    private var last = 0
    private var task: Task<Void, Never>?

    public init() {}

    /// What the screen lists, oldest first.
    public var shown: [LogLine] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return lines.filter { line in
            filter.passes(line.level) && (needle.isEmpty || line.message.lowercased().contains(needle))
        }
    }

    public func start(client: @escaping @MainActor () -> StrataClient?) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if let client = client() { await self.fetch(client) }
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Another server: begin again from its newest lines.
    public func reset() {
        lines = []
        last = 0
        hasLoaded = false
        errorText = nil
    }

    /// One fetch. Public so tests and pull-to-refresh can drive it.
    public func fetch(_ client: StrataClient) async {
        do {
            if engine == .omlx {
                apply(OmLXLogParser.batch(try await client.omlxLogs(lines: Self.omlxTailLines)))
            } else {
                apply(try await client.logs(after: last))
            }
            errorText = nil
        } catch StrataError.unauthorized {
            errorText = "This server rejected the API key."
        } catch StrataError.http(404) {
            errorText = "This server has no log feed."
        } catch {
            errorText = "Could not read the log."
        }
        hasLoaded = true
    }

    func apply(_ batch: LogBatch) {
        if batch.last < last {
            // The server restarted and its ids began again: what we hold belongs to the old run.
            lines = batch.lines
        } else {
            let known = lines.last?.id ?? -1
            lines += batch.lines.filter { $0.id > known }
        }
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        last = batch.last
    }
}

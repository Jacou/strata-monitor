import Foundation
import Observation

/// Loads the run config, holds the edits, and saves them. Shared so the menu bar app can grow the
/// same screen later.
@Observable @MainActor
public final class ConfigStore {
    public enum State: Equatable, Sendable {
        case idle, loading, saving
    }

    public private(set) var response: ConfigResponse?
    public private(set) var state: State = .idle
    /// What the server said after a save, or "Nothing changed.".
    public private(set) var message: String?
    public private(set) var errorText: String?
    /// A server with no run config, an older server, or one that wants a key first.
    public private(set) var isUnavailable = false

    /// key → proposed value; nil means "use the default". Keys not in here are untouched.
    public private(set) var edits: [String: ConfigValue?] = [:]

    public init() {}

    public var model: ConfigViewModel { ConfigViewModel(response) }

    public var pendingChanges: [String: ConfigValue] {
        ConfigViewModel.changes(keys: model.keys, edits: edits)
    }

    public var hasChanges: Bool { !pendingChanges.isEmpty }

    public var isBusy: Bool { state != .idle }

    /// The value the editor should show: the edit if there is one, otherwise the server's value.
    public func value(for key: ConfigKey) -> ConfigValue? {
        if let edit = edits[key.key] { return edit }
        return key.value
    }

    public func setEdit(_ value: ConfigValue?, for key: String) {
        edits[key] = value
        message = nil
        errorText = nil
    }

    public func discardEdits() {
        edits = [:]
        message = nil
    }

    // MARK: - network

    public func load(client: StrataClient?) async {
        guard let client else {
            isUnavailable = true
            errorText = "Set the server address in Settings first."
            return
        }
        state = .loading
        errorText = nil
        message = nil
        do {
            response = try await client.config()
            edits = [:]
            isUnavailable = false
        } catch let error as StrataError {
            response = nil
            edits = [:]
            isUnavailable = true
            switch error {
            case .unauthorized: errorText = "The server needs its API key before it will show the run config."
            case .http(let code): errorText = "This server does not expose its run config (HTTP \(code))."
            default: errorText = StrataError.unreachable.plainWords
            }
        } catch {
            response = nil
            isUnavailable = true
            errorText = StrataError.unreachable.plainWords
        }
        state = .idle
    }

    public func save(client: StrataClient?) async {
        guard let client else {
            errorText = "Set the server address in Settings first."
            return
        }
        let changes = pendingChanges
        guard !changes.isEmpty else {
            message = "Nothing changed."
            errorText = nil
            return
        }

        state = .saving
        errorText = nil
        do {
            let reply = try await client.updateConfig(changes)
            let changed = reply.changed ?? []
            message = changed.isEmpty
                ? "Nothing changed."
                : "Saved \(changed.joined(separator: ", ")). The earlier file is \((reply.file ?? "the run config")).bak — start the model again to use it."
            edits = [:]
            // Re-read, like the web page does, so the rows show what the file holds now.
            response = try await client.config()
        } catch let error as StrataServerError {
            // The server explains a rejected value in its own words; show them.
            errorText = error.message
        } catch let error as StrataError {
            errorText = error.plainWords
        } catch {
            errorText = StrataError.unreachable.plainWords
        }
        state = .idle
    }
}

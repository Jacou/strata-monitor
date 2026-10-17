import Foundation
import Observation

/// Server address in UserDefaults, API key in the Keychain.
@Observable @MainActor
public final class AppSettings {
    public static let defaultBaseURLString = "http://192.168.1.10:8081"
    public static let defaultBaseURL: URL = URL(string: defaultBaseURLString)!
    public static let apiKeyAccount = "apiKey"

    /// How often a menu bar app polls while nothing is on screen. 1 s is reserved for when it is.
    public static let closedPollIntervalChoices: [TimeInterval] = [5, 15, 30]
    public static let defaultClosedPollInterval: TimeInterval = 5

    private static let baseURLKey = "settings.baseURL"
    private static let closedPollIntervalKey = "settings.closedPollInterval"

    public var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Self.baseURLKey) }
    }

    public var apiKey: String {
        didSet {
            let trimmed = apiKey.trimmed()
            if trimmed != apiKey {
                apiKey = trimmed  // didSet runs again, this time with the value we keep
                return
            }
            saveAPIKey(trimmed)
        }
    }

    /// The idle cadence, snapped to one of `closedPollIntervalChoices`.
    public var closedPollInterval: TimeInterval {
        didSet {
            let snapped = Self.validClosedPollInterval(closedPollInterval)
            if snapped != closedPollInterval {
                closedPollInterval = snapped  // didSet runs again, this time with the value we keep
                return
            }
            defaults.set(closedPollInterval, forKey: Self.closedPollIntervalKey)
        }
    }

    private let defaults: UserDefaults
    private let keychain: Keychain

    public init(
        defaults: UserDefaults = .standard,
        keychain: Keychain = Keychain()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.baseURLString = defaults.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURLString
        self.apiKey = keychain.get(Self.apiKeyAccount) ?? ""
        self.closedPollInterval = Self.validClosedPollInterval(defaults.object(forKey: Self.closedPollIntervalKey) as? Double)
    }

    /// The server to talk to. nil when the typed address is unusable — the Settings screen says so
    /// rather than quietly sending requests somewhere else.
    public var baseURL: URL? {
        get { Self.validURL(baseURLString) }
        set { baseURLString = newValue?.absoluteString ?? "" }
    }

    public var isValidBaseURL: Bool { baseURL != nil }

    public var hasAPIKey: Bool { !apiKey.trimmed().isEmpty }

    public func resetBaseURL() { baseURLString = Self.defaultBaseURLString }

    /// A stored cadence we do not offer (junk, or an old value) falls back to the default.
    public static func validClosedPollInterval(_ value: Double?) -> TimeInterval {
        guard let value else { return defaultClosedPollInterval }
        return closedPollIntervalChoices.first { abs($0 - value) < 0.5 } ?? defaultClosedPollInterval
    }

    /// "5 s", "15 s", "30 s" — the label the Settings picker shows.
    public static func closedPollIntervalLabel(_ interval: TimeInterval) -> String {
        "\(Int(interval.rounded())) s"
    }

    #if DEBUG
    /// Debug builds only: `SIMCTL_CHILD_STRATA_API_KEY=… xcrun simctl launch …` hands the key to
    /// the process; store it so a fresh simulator can show live data without typing it.
    public func adoptAPIKeyFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        guard !hasAPIKey,
              let value = env["STRATA_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return }
        apiKey = value
    }

    /// Debug builds only: `open --env STRATA_SERVER=http://127.0.0.1:8098 …` points the app at a
    /// local stand-in server, but only while nothing has been saved yet.
    public func adoptServerFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        guard defaults.string(forKey: Self.baseURLKey) == nil,
              let value = env["STRATA_SERVER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.validURL(value) != nil
        else { return }
        baseURLString = value
    }
    #endif

    /// A client for the current settings, or nil when the address is invalid.
    public func makeClient(transport: (any HTTPTransport)? = nil) -> StrataClient? {
        guard let baseURL = baseURL else { return nil }
        return StrataClient(baseURL: baseURL, apiKey: apiKey.trimmed(), transport: transport)
    }

    /// "http://192.168.1.10:8081" — a scheme and a host, nothing else.
    public static func validURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmed()),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private func saveAPIKey(_ value: String) {
        let trimmed = value.trimmed()
        if trimmed.isEmpty {
            keychain.delete(Self.apiKeyAccount)
        } else {
            try? keychain.set(trimmed, account: Self.apiKeyAccount)
        }
    }
}

extension String {
    fileprivate func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

import Foundation
import Observation

/// One of the two Strata servers the apps know about. The primary one is always there; the
/// secondary one exists once it has an address.
public enum ServerSlot: String, CaseIterable, Identifiable, Sendable {
    case primary
    case secondary

    public var id: String { rawValue }

    /// "Server 1" / "Server 2" — the name when the user gave none.
    public var defaultName: String {
        switch self {
        case .primary: "Server 1"
        case .secondary: "Server 2"
        }
    }

    /// The primary slot keeps the keys a single-server build wrote, so an upgrade carries them over.
    fileprivate var baseURLKey: String { self == .primary ? "settings.baseURL" : "settings.secondary.baseURL" }
    fileprivate var nameKey: String { self == .primary ? "settings.name" : "settings.secondary.name" }
    fileprivate var apiKeyAccount: String { self == .primary ? "apiKey" : "apiKey.secondary" }
}

/// Server addresses and names in UserDefaults, API keys in the Keychain — one of each per slot.
/// The single-server API (`baseURLString`, `apiKey`, `makeClient()`…) means the selected slot.
@Observable @MainActor
public final class AppSettings {
    public static let defaultBaseURLString = "http://192.168.1.10:8081"
    public static let defaultBaseURL: URL = URL(string: defaultBaseURLString)!
    public static let apiKeyAccount = "apiKey"

    /// How often a menu bar app polls while nothing is on screen. 1 s is reserved for when it is.
    public static let closedPollIntervalChoices: [TimeInterval] = [5, 15, 30]
    public static let defaultClosedPollInterval: TimeInterval = 5

    private static let closedPollIntervalKey = "settings.closedPollInterval"
    private static let selectedServerKey = "settings.selectedServer"

    private var baseURLStrings: [ServerSlot: String]
    private var apiKeys: [ServerSlot: String]
    private var names: [ServerSlot: String]
    private var storedSelection: ServerSlot

    /// The server the app is showing. Never a slot that is not set up: a stored choice of the
    /// secondary server reads as the primary once the secondary has no address.
    public var selectedSlot: ServerSlot {
        get { isConfigured(storedSelection) ? storedSelection : .primary }
        set {
            storedSelection = newValue
            defaults.set(newValue.rawValue, forKey: Self.selectedServerKey)
        }
    }

    public var baseURLString: String {
        get { baseURLString(for: selectedSlot) }
        set { setBaseURLString(newValue, for: selectedSlot) }
    }

    public var apiKey: String {
        get { apiKey(for: selectedSlot) }
        set { setAPIKey(newValue, for: selectedSlot) }
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
        var urls: [ServerSlot: String] = [:]
        var keys: [ServerSlot: String] = [:]
        var names: [ServerSlot: String] = [:]
        for slot in ServerSlot.allCases {
            urls[slot] = defaults.string(forKey: slot.baseURLKey) ?? (slot == .primary ? Self.defaultBaseURLString : "")
            keys[slot] = keychain.get(slot.apiKeyAccount) ?? ""
            names[slot] = defaults.string(forKey: slot.nameKey) ?? ""
        }
        self.baseURLStrings = urls
        self.apiKeys = keys
        self.names = names
        self.storedSelection = defaults.string(forKey: Self.selectedServerKey).flatMap(ServerSlot.init(rawValue:)) ?? .primary
        self.closedPollInterval = Self.validClosedPollInterval(defaults.object(forKey: Self.closedPollIntervalKey) as? Double)
    }

    /// The server to talk to. nil when the typed address is unusable — the Settings screen says so
    /// rather than quietly sending requests somewhere else.
    public var baseURL: URL? {
        get { Self.validURL(baseURLString) }
        set { baseURLString = newValue?.absoluteString ?? "" }
    }

    public var isValidBaseURL: Bool { baseURL != nil }

    public var hasAPIKey: Bool { hasAPIKey(for: selectedSlot) }

    public func resetBaseURL() { baseURLString = Self.defaultBaseURLString }

    // MARK: - per server

    public func baseURLString(for slot: ServerSlot) -> String { baseURLStrings[slot] ?? "" }

    public func setBaseURLString(_ value: String, for slot: ServerSlot) {
        baseURLStrings[slot] = value
        defaults.set(value, forKey: slot.baseURLKey)
    }

    public func apiKey(for slot: ServerSlot) -> String { apiKeys[slot] ?? "" }

    /// Trimmed; an empty key removes the Keychain item.
    public func setAPIKey(_ value: String, for slot: ServerSlot) {
        let trimmed = value.trimmed()
        apiKeys[slot] = trimmed
        saveAPIKey(trimmed, account: slot.apiKeyAccount)
    }

    /// What the user typed, possibly empty — `displayName(for:)` is what to show.
    public func name(for slot: ServerSlot) -> String { names[slot] ?? "" }

    public func setName(_ value: String, for slot: ServerSlot) {
        let trimmed = value.trimmed()
        names[slot] = trimmed
        defaults.set(trimmed, forKey: slot.nameKey)
    }

    public func displayName(for slot: ServerSlot) -> String {
        let name = name(for: slot)
        return name.isEmpty ? slot.defaultName : name
    }

    public func baseURL(for slot: ServerSlot) -> URL? { Self.validURL(baseURLString(for: slot)) }

    public func hasAPIKey(for slot: ServerSlot) -> Bool { !apiKey(for: slot).isEmpty }

    /// The primary server always counts (an unusable address is the Settings screen's to report);
    /// the secondary one only once it has a usable address.
    public func isConfigured(_ slot: ServerSlot) -> Bool {
        slot == .primary || baseURL(for: slot) != nil
    }

    public var configuredSlots: [ServerSlot] { ServerSlot.allCases.filter(isConfigured) }

    public var hasMultipleServers: Bool { configuredSlots.count > 1 }

    /// Forget the second server: address, name and key. The selection falls back to the primary.
    public func removeSecondary() {
        setBaseURLString("", for: .secondary)
        setName("", for: .secondary)
        setAPIKey("", for: .secondary)
        if storedSelection == .secondary { selectedSlot = .primary }
    }

    /// A client for one server, or nil when its address is invalid.
    public func makeClient(for slot: ServerSlot, transport: (any HTTPTransport)? = nil) -> StrataClient? {
        guard let baseURL = baseURL(for: slot) else { return nil }
        return StrataClient(baseURL: baseURL, apiKey: apiKey(for: slot), transport: transport)
    }

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
        setAPIKey(value, for: .primary)
    }

    /// Debug builds only: `open --env STRATA_SERVER=http://127.0.0.1:8098 …` points the app at a
    /// local stand-in server, but only while nothing has been saved yet.
    public func adoptServerFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        guard defaults.string(forKey: ServerSlot.primary.baseURLKey) == nil,
              let value = env["STRATA_SERVER"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.validURL(value) != nil
        else { return }
        setBaseURLString(value, for: .primary)
    }

    /// Debug builds only: `open --env STRATA_SERVER_2=http://… --env STRATA_API_KEY_2=… --env
    /// STRATA_NAME_2=…` sets up the second server, but only while it has none. The values are
    /// stored, so later launches need no environment.
    public func adoptSecondaryFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        func value(_ key: String) -> String? {
            env[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        guard !isConfigured(.secondary),
              let server = value("STRATA_SERVER_2"),
              Self.validURL(server) != nil
        else { return }
        setBaseURLString(server, for: .secondary)
        if let key = value("STRATA_API_KEY_2") { setAPIKey(key, for: .secondary) }
        if let name = value("STRATA_NAME_2") { setName(name, for: .secondary) }
    }
    #endif

    /// A client for the current settings, or nil when the address is invalid.
    public func makeClient(transport: (any HTTPTransport)? = nil) -> StrataClient? {
        makeClient(for: selectedSlot, transport: transport)
    }

    /// "http://192.168.1.10:8081" — a scheme and a host, nothing else.
    public static func validURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmed()),
              let scheme = url.scheme, scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private func saveAPIKey(_ trimmed: String, account: String) {
        if trimmed.isEmpty {
            keychain.delete(account)
        } else {
            try? keychain.set(trimmed, account: account)
        }
    }
}

extension String {
    fileprivate func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

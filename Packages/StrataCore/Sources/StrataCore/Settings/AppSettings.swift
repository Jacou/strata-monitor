import Foundation
import Observation

/// One of the up-to-four Strata servers the apps know about, in order. The primary one is always
/// there; the others exist once the user adds them, and shift down when one is removed.
public enum ServerSlot: String, CaseIterable, Identifiable, Sendable {
    case primary
    case secondary
    case third
    case fourth

    public var id: String { rawValue }

    /// 0…3 — the position in the list.
    public var index: Int {
        switch self {
        case .primary: 0
        case .secondary: 1
        case .third: 2
        case .fourth: 3
        }
    }

    /// 1…4 — the number the user sees.
    public var number: Int { index + 1 }

    /// nil for a position outside the list.
    public init?(index: Int) {
        guard index >= 0, index < ServerSlot.allCases.count else { return nil }
        self = ServerSlot.allCases[index]
    }

    /// "Server 1" … "Server 4" — the name when the user gave none.
    public var defaultName: String { "Server \(number)" }

    /// The first two slots keep the keys older builds wrote, so an upgrade carries them over.
    fileprivate var baseURLKey: String {
        switch self {
        case .primary: "settings.baseURL"
        case .secondary: "settings.secondary.baseURL"
        case .third: "settings.server3.baseURL"
        case .fourth: "settings.server4.baseURL"
        }
    }

    fileprivate var nameKey: String {
        switch self {
        case .primary: "settings.name"
        case .secondary: "settings.secondary.name"
        case .third: "settings.server3.name"
        case .fourth: "settings.server4.name"
        }
    }

    fileprivate var apiKeyAccount: String {
        switch self {
        case .primary: "apiKey"
        case .secondary: "apiKey.secondary"
        case .third: "apiKey.server3"
        case .fourth: "apiKey.server4"
        }
    }
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

    /// How many servers the user keeps. One by default; they add the rest, up to this.
    public static let maxServers = 4

    private static let closedPollIntervalKey = "settings.closedPollInterval"
    private static let selectedServerKey = "settings.selectedServer"
    private static let serverCountKey = "settings.serverCount"

    private var baseURLStrings: [ServerSlot: String]
    private var apiKeys: [ServerSlot: String]
    private var names: [ServerSlot: String]
    private var storedSelection: ServerSlot

    /// How many servers there are, 1…4. The slots past it are empty as far as the apps care, even
    /// if an old build left values behind. Only `addServer` and `removeServer` change it.
    public private(set) var serverCount: Int

    /// The server the app is showing. Never a slot that is not set up: a stored choice of a later
    /// server reads as the primary once that server has no address.
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
        self.serverCount = Self.loadedServerCount(stored: defaults.object(forKey: Self.serverCountKey) as? Int, urls: urls)
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

    /// A slot within the count, and — every slot but the first — with a usable address. The primary
    /// always counts (an unusable address is the Settings screen's to report).
    public func isConfigured(_ slot: ServerSlot) -> Bool {
        slot.index < serverCount && (slot == .primary || baseURL(for: slot) != nil)
    }

    /// The servers the Settings screens list: the first `serverCount` slots, including a just-added
    /// one with no address yet.
    public var slots: [ServerSlot] { Array(ServerSlot.allCases.prefix(serverCount)) }

    public var configuredSlots: [ServerSlot] { slots.filter(isConfigured) }

    public var hasMultipleServers: Bool { configuredSlots.count > 1 }

    public var canAddServer: Bool { serverCount < Self.maxServers }

    /// Make room for one more server and return its empty slot, or nil when there are already
    /// `maxServers`. Any leftovers of a server that used to sit here are cleared first.
    @discardableResult
    public func addServer() -> ServerSlot? {
        guard let slot = ServerSlot(index: serverCount) else { return nil }
        clear(slot)
        serverCount += 1
        defaults.set(serverCount, forKey: Self.serverCountKey)
        return slot
    }

    /// Drop one server and close the gap: every later one moves down a slot, address, name and key
    /// with it, and the last slot is left empty. Removing the first promotes the second into the
    /// keys a single-server build wrote.
    public func removeServer(_ slot: ServerSlot) {
        let list = slots
        guard serverCount > 1, list.contains(slot) else { return }
        let selection = selectedSlot
        let survivors = list.filter { $0 != slot }
        for (index, from) in survivors.enumerated() where list[index] != from {
            setBaseURLString(baseURLString(for: from), for: list[index])
            setName(name(for: from), for: list[index])
            setAPIKey(apiKey(for: from), for: list[index])
        }
        clear(list[list.count - 1])
        serverCount -= 1
        defaults.set(serverCount, forKey: Self.serverCountKey)
        // The server the user was looking at either moves down with its own data or, when it is the
        // one that went away, hands over to the one before it.
        if selection.index > slot.index, let moved = ServerSlot(index: selection.index - 1) {
            selectedSlot = moved
        } else if selection == slot {
            selectedSlot = ServerSlot(index: slot.index - 1) ?? .primary
        }
    }

    /// Address, name and key gone, Keychain item included.
    private func clear(_ slot: ServerSlot) {
        setBaseURLString("", for: slot)
        setName("", for: slot)
        setAPIKey("", for: slot)
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

    /// A count we do not offer (junk, or a newer build) falls back to what the keys show: two while
    /// the legacy secondary address is there, one otherwise. Nothing is written for the migration.
    private static func loadedServerCount(stored: Int?, urls: [ServerSlot: String]) -> Int {
        if let stored { return min(max(stored, 1), maxServers) }
        return validURL(urls[.secondary] ?? "") == nil ? 1 : 2
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
    /// STRATA_NAME_2=…` and the same for 3 and 4 set up the extra servers, but only while they have
    /// none. The values are stored, so later launches need no environment.
    public func adoptExtraServersFromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) {
        func value(_ key: String) -> String? {
            env[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        for number in 2...Self.maxServers {
            guard let slot = ServerSlot(index: number - 1),
                  !isConfigured(slot),
                  let server = value("STRATA_SERVER_\(number)"),
                  Self.validURL(server) != nil
            else { continue }
            if serverCount < number {
                serverCount = number
                defaults.set(number, forKey: Self.serverCountKey)
            }
            setBaseURLString(server, for: slot)
            if let key = value("STRATA_API_KEY_\(number)") { setAPIKey(key, for: slot) }
            if let name = value("STRATA_NAME_\(number)") { setName(name, for: slot) }
        }
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

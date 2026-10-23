import XCTest
@testable import StrataCore

@MainActor
final class AppSettingsTests: XCTestCase {
    private var lastSuite = ""

    private func freshDefaults() -> UserDefaults {
        let suite = "StrataMonitorTests.\(UUID().uuidString)"
        lastSuite = suite
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func freshKeychain() -> Keychain {
        Keychain(service: "com.jacou.StrataMonitor.tests.\(UUID().uuidString)")
    }

    /// Everything the settings wrote to the suite — to prove the key never lands here.
    private func persisted(_ defaults: UserDefaults) -> [String: Any] {
        defaults.persistentDomain(forName: lastSuite) ?? [:]
    }

    func testDefaultBaseURL() throws {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        XCTAssertEqual(settings.baseURLString, "http://192.168.1.10:8081")
        XCTAssertTrue(settings.isValidBaseURL)
        let url = try XCTUnwrap(settings.baseURL)
        XCTAssertEqual(url.host, "192.168.1.10")
        XCTAssertEqual(url.port, 8081)
        XCTAssertFalse(settings.hasAPIKey)
    }

    func testBaseURLPersists() {
        let defaults = freshDefaults()
        let keychain = freshKeychain()

        let first = AppSettings(defaults: defaults, keychain: keychain)
        first.baseURLString = "http://192.168.1.9:8081/"
        XCTAssertEqual(defaults.string(forKey: "settings.baseURL"), "http://192.168.1.9:8081/")

        let second = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(second.baseURLString, "http://192.168.1.9:8081/")
        XCTAssertEqual(second.baseURL?.absoluteString, "http://192.168.1.9:8081/")
    }

    func testBaseURLSetFromURL() throws {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.baseURL = URL(string: "http://strata.local:8081")!
        XCTAssertEqual(settings.baseURLString, "http://strata.local:8081")
        settings.resetBaseURL()
        XCTAssertEqual(settings.baseURLString, AppSettings.defaultBaseURLString)
        XCTAssertEqual(settings.baseURL?.absoluteString, AppSettings.defaultBaseURLString)
    }

    func testGarbageBaseURLIsRejectedNotSilentlyReplaced() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.baseURLString = "not a url"
        XCTAssertNil(settings.baseURL)
        XCTAssertFalse(settings.isValidBaseURL)
        XCTAssertNil(settings.makeClient(), "no client for an address we cannot use")
    }

    func testValidURLRules() {
        XCTAssertNotNil(AppSettings.validURL("http://192.168.1.10:8081"))
        XCTAssertNotNil(AppSettings.validURL("  https://strata.local  "))
        XCTAssertNotNil(AppSettings.validURL("http://192.168.1.10:8081/strata"))
        XCTAssertNil(AppSettings.validURL(""))
        XCTAssertNil(AppSettings.validURL("   "))
        XCTAssertNil(AppSettings.validURL("not a url"))
        XCTAssertNil(AppSettings.validURL("192.168.1.10:8081"), "no scheme")
        XCTAssertNil(AppSettings.validURL("ftp://192.168.1.10"), "only http and https")
        XCTAssertNil(AppSettings.validURL("http://"), "no host")
    }

    func testBaseURLCanBeCleared() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.baseURL = nil
        XCTAssertEqual(settings.baseURLString, "")
        XCTAssertFalse(settings.isValidBaseURL)
    }

    func testAPIKeyGoesToTheKeychainNotUserDefaults() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)

        let settings = AppSettings(defaults: defaults, keychain: keychain)
        settings.apiKey = "  hunter2  "

        XCTAssertEqual(settings.apiKey, "hunter2")  // trimmed
        XCTAssertTrue(settings.hasAPIKey)
        XCTAssertEqual(keychain.get(AppSettings.apiKeyAccount), "hunter2")
        // never in UserDefaults
        let stored = persisted(defaults)
        XCTAssertNil(stored["settings.apiKey"])
        for key in stored.keys { XCTAssertFalse(key.lowercased().contains("key")) }
        XCTAssertNil(defaults.string(forKey: "settings.apiKey"))

        settings.apiKey = ""
        XCTAssertFalse(settings.hasAPIKey)
        XCTAssertNil(keychain.get(AppSettings.apiKeyAccount))
    }

    func testAPIKeyIsReloadedFromTheKeychain() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)

        AppSettings(defaults: defaults, keychain: keychain).apiKey = "persisted"
        let reloaded = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.apiKey, "persisted")
        XCTAssertTrue(reloaded.hasAPIKey)
        keychain.delete(AppSettings.apiKeyAccount)
    }

    private func skipIfKeychainUnavailable(_ keychain: Keychain) throws {
        let probe = "probe.\(UUID().uuidString)"
        do {
            try keychain.set("probe", account: probe)
        } catch {
            throw XCTSkip("Keychain unavailable in this test host: \(error)")
        }
        keychain.delete(probe)
    }

    // MARK: - poll cadence (the menu bar app's "Refresh when closed")

    func testClosedPollIntervalDefaultsToFiveSeconds() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        XCTAssertEqual(settings.closedPollInterval, 5)
    }

    func testClosedPollIntervalPersistsAndReloads() {
        let defaults = freshDefaults()
        let keychain = freshKeychain()

        let first = AppSettings(defaults: defaults, keychain: keychain)
        first.closedPollInterval = 30
        XCTAssertEqual(defaults.object(forKey: "settings.closedPollInterval") as? Double, 30)

        let second = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(second.closedPollInterval, 30)
    }

    func testClosedPollIntervalOnlyEverHoldsOneOfTheChoices() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())

        settings.closedPollInterval = 15
        XCTAssertEqual(settings.closedPollInterval, 15)
        settings.closedPollInterval = 7  // not offered
        XCTAssertEqual(settings.closedPollInterval, 5, "junk falls back to the default")
        XCTAssertEqual(defaults.object(forKey: "settings.closedPollInterval") as? Double, 5)
        settings.closedPollInterval = 0
        XCTAssertEqual(settings.closedPollInterval, 5)
        settings.closedPollInterval = 14.9  // close enough to a choice
        XCTAssertEqual(settings.closedPollInterval, 15)
    }

    func testStoredJunkClosedPollIntervalReloadsAsTheDefault() {
        let defaults = freshDefaults()
        defaults.set(999, forKey: "settings.closedPollInterval")
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())
        XCTAssertEqual(settings.closedPollInterval, 5)
    }

    func testClosedPollIntervalChoicesAndLabels() {
        XCTAssertEqual(AppSettings.closedPollIntervalChoices, [5, 15, 30])
        XCTAssertEqual(AppSettings.closedPollIntervalLabel(15), "15 s")
        XCTAssertEqual(AppSettings.validClosedPollInterval(nil), AppSettings.defaultClosedPollInterval)
        XCTAssertEqual(AppSettings.validClosedPollInterval(2), 5)
    }

    func testClientCarriesTheSettings() throws {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.baseURLString = "http://192.168.1.9:8081"
        settings.apiKey = "key"
        let client = try XCTUnwrap(settings.makeClient())
        XCTAssertEqual(client.baseURL.absoluteString, "http://192.168.1.9:8081")
        XCTAssertEqual(client.apiKey, "key")
        XCTAssertEqual(client.request(path: "metrics")?.value(forHTTPHeaderField: "Authorization"), "Bearer key")
    }

    // MARK: - debug-only convenience for screenshots

    #if DEBUG
    func testEnvironmentAPIKeyIsAdoptedWhenNothingIsStored() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        settings.adoptAPIKeyFromEnvironment(["STRATA_API_KEY": "  from-env  "])
        XCTAssertEqual(settings.apiKey, "from-env")
        XCTAssertEqual(keychain.get(AppSettings.apiKeyAccount), "from-env")
        keychain.delete(AppSettings.apiKeyAccount)
    }

    func testEnvironmentAPIKeyNeverOverwritesASavedKey() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        settings.apiKey = "saved"
        settings.adoptAPIKeyFromEnvironment(["STRATA_API_KEY": "from-env"])
        XCTAssertEqual(settings.apiKey, "saved")
        keychain.delete(AppSettings.apiKeyAccount)
    }

    func testEmptyEnvironmentAPIKeyIsIgnored() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.adoptAPIKeyFromEnvironment(["STRATA_API_KEY": "   "])
        XCTAssertFalse(settings.hasAPIKey)
        settings.adoptAPIKeyFromEnvironment([:])
        XCTAssertFalse(settings.hasAPIKey)
    }

    func testEnvironmentServerIsAdoptedWhenNothingIsSaved() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())
        settings.adoptServerFromEnvironment(["STRATA_SERVER": "http://127.0.0.1:8098"])
        XCTAssertEqual(settings.baseURLString, "http://127.0.0.1:8098")
        XCTAssertEqual(settings.baseURL?.host, "127.0.0.1")
    }

    func testEnvironmentServerNeverOverwritesASavedAddress() {
        let defaults = freshDefaults()
        let saved = AppSettings(defaults: defaults, keychain: freshKeychain())
        saved.baseURLString = "http://10.0.0.5:8081"
        let reloaded = AppSettings(defaults: defaults, keychain: freshKeychain())
        reloaded.adoptServerFromEnvironment(["STRATA_SERVER": "http://127.0.0.1:8098"])
        XCTAssertEqual(reloaded.baseURLString, "http://10.0.0.5:8081")
    }

    func testJunkEnvironmentServerIsIgnored() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.adoptServerFromEnvironment(["STRATA_SERVER": "not a url"])
        XCTAssertEqual(settings.baseURLString, AppSettings.defaultBaseURLString)
        settings.adoptServerFromEnvironment([:])
        XCTAssertEqual(settings.baseURLString, AppSettings.defaultBaseURLString)
    }
    #endif

    // MARK: - two servers

    func testSingleServerValuesLoadAsThePrimarySlot() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        defaults.set("http://192.168.1.82:8081", forKey: "settings.baseURL")
        try keychain.set("old-key", account: "apiKey")

        let settings = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(settings.selectedSlot, .primary)
        XCTAssertEqual(settings.baseURLString(for: .primary), "http://192.168.1.82:8081")
        XCTAssertEqual(settings.apiKey(for: .primary), "old-key")
        XCTAssertEqual(settings.baseURLString(for: .secondary), "")
        XCTAssertEqual(settings.configuredSlots, [.primary])
        XCTAssertFalse(settings.hasMultipleServers)
    }

    func testSecondaryServerPersistsUnderItsOwnKeys() {
        let defaults = freshDefaults()
        let keychain = freshKeychain()

        let first = AppSettings(defaults: defaults, keychain: keychain)
        first.setBaseURLString("http://192.168.1.83:8081", for: .secondary)
        first.setName("  Studio  ", for: .secondary)
        first.setAPIKey("  second  ", for: .secondary)

        XCTAssertEqual(defaults.string(forKey: "settings.secondary.baseURL"), "http://192.168.1.83:8081")
        XCTAssertEqual(defaults.string(forKey: "settings.secondary.name"), "Studio")
        XCTAssertEqual(keychain.get("apiKey.secondary"), "second")
        XCTAssertNil(persisted(defaults).values.first { ($0 as? String) == "second" }, "the key stays out of UserDefaults")

        let second = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(second.baseURLString(for: .secondary), "http://192.168.1.83:8081")
        XCTAssertEqual(second.name(for: .secondary), "Studio")
        XCTAssertEqual(second.apiKey(for: .secondary), "second")
        XCTAssertEqual(second.configuredSlots, [.primary, .secondary])
        XCTAssertTrue(second.hasMultipleServers)
    }

    func testTheTwoKeysDoNotCollide() {
        let keychain = freshKeychain()
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        settings.setAPIKey("one", for: .primary)
        settings.setAPIKey("two", for: .secondary)
        XCTAssertEqual(keychain.get("apiKey"), "one")
        XCTAssertEqual(keychain.get("apiKey.secondary"), "two")

        settings.setAPIKey("", for: .secondary)
        XCTAssertNil(keychain.get("apiKey.secondary"))
        XCTAssertEqual(settings.apiKey(for: .primary), "one")
    }

    func testSelectionPersistsAndDrivesTheSingleServerAPI() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()

        let first = AppSettings(defaults: defaults, keychain: keychain)
        first.setAPIKey("one", for: .primary)
        first.setBaseURLString("http://192.168.1.83:8081", for: .secondary)
        first.setAPIKey("two", for: .secondary)
        first.selectedSlot = .secondary
        XCTAssertEqual(first.baseURLString, "http://192.168.1.83:8081")
        XCTAssertEqual(first.apiKey, "two")
        XCTAssertEqual(first.makeClient()?.apiKey, "two")

        first.apiKey = "two-b"
        XCTAssertEqual(first.apiKey(for: .secondary), "two-b")
        XCTAssertEqual(first.apiKey(for: .primary), "one")

        let second = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(second.selectedSlot, .secondary)
        XCTAssertEqual(try XCTUnwrap(second.baseURL).port, 8081)
        XCTAssertEqual(second.baseURL?.host, "192.168.1.83")
    }

    func testSelectionFallsBackWhenTheSecondaryIsNotSetUp() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        settings.selectedSlot = .secondary
        XCTAssertEqual(settings.selectedSlot, .primary, "no address yet")

        settings.setBaseURLString("http://192.168.1.83:8081", for: .secondary)
        XCTAssertEqual(settings.selectedSlot, .secondary)

        settings.removeSecondary()
        XCTAssertEqual(settings.selectedSlot, .primary)
        XCTAssertEqual(settings.configuredSlots, [.primary])
        XCTAssertNil(settings.makeClient(for: .secondary))
    }

    func testDisplayNameFallsBackToTheSlotName() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        XCTAssertEqual(settings.displayName(for: .primary), "Server 1")
        XCTAssertEqual(settings.displayName(for: .secondary), "Server 2")
        settings.setName("Mac Studio", for: .primary)
        XCTAssertEqual(settings.displayName(for: .primary), "Mac Studio")
        settings.setName("   ", for: .primary)
        XCTAssertEqual(settings.displayName(for: .primary), "Server 1")
    }

    func testMakeClientForEachSlot() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        XCTAssertNil(settings.makeClient(for: .secondary))
        settings.setBaseURLString("http://192.168.1.83:8081", for: .secondary)
        settings.setAPIKey("two", for: .secondary)
        let client = settings.makeClient(for: .secondary)
        XCTAssertEqual(client?.baseURL.absoluteString, "http://192.168.1.83:8081")
        XCTAssertEqual(client?.apiKey, "two")
        XCTAssertNotNil(settings.makeClient(for: .primary))
    }

    #if DEBUG
    func testAdoptSecondaryFromEnvironment() {
        let keychain = freshKeychain()
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        settings.adoptSecondaryFromEnvironment(["STRATA_SERVER_2": "not a url"])
        XCTAssertFalse(settings.isConfigured(.secondary))

        settings.adoptSecondaryFromEnvironment([
            "STRATA_SERVER_2": " http://192.168.1.172:8080 ",
            "STRATA_API_KEY_2": "k2",
            "STRATA_NAME_2": "Coder",
        ])
        XCTAssertEqual(settings.baseURLString(for: .secondary), "http://192.168.1.172:8080")
        XCTAssertEqual(keychain.get("apiKey.secondary"), "k2")
        XCTAssertEqual(settings.displayName(for: .secondary), "Coder")

        settings.adoptSecondaryFromEnvironment(["STRATA_SERVER_2": "http://10.0.0.1:8080"])
        XCTAssertEqual(settings.baseURLString(for: .secondary), "http://192.168.1.172:8080", "a saved server wins")
    }
    #endif
}

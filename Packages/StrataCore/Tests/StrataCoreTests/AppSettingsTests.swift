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

    // MARK: - one to four servers

    /// Four servers with an address, a name and a key each, so a move is easy to follow.
    private func fill(_ settings: AppSettings) {
        let servers = [
            ("http://10.0.0.1:8081", "One", "k1"),
            ("http://10.0.0.2:8081", "Two", "k2"),
            ("http://10.0.0.3:8081", "Three", "k3"),
            ("http://10.0.0.4:8081", "Four", "k4"),
        ]
        for slot in ServerSlot.allCases {
            let server = servers[slot.index]
            settings.setBaseURLString(server.0, for: slot)
            settings.setName(server.1, for: slot)
            settings.setAPIKey(server.2, for: slot)
        }
    }

    private func addAllServers(to settings: AppSettings) {
        while settings.addServer() != nil {}
    }

    func testServerSlotNumbering() {
        XCTAssertEqual(ServerSlot.allCases.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(ServerSlot.allCases.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(ServerSlot.allCases.map(\.defaultName), ["Server 1", "Server 2", "Server 3", "Server 4"])
        XCTAssertEqual(ServerSlot(index: 0), .primary)
        XCTAssertEqual(ServerSlot(index: 3), .fourth)
        XCTAssertNil(ServerSlot(index: -1))
        XCTAssertNil(ServerSlot(index: 4))
        XCTAssertEqual(ServerSlot(rawValue: "secondary"), .secondary, "a stored selection still reads back")
    }

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
        XCTAssertEqual(first.addServer(), .secondary)
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

    func testTheFourKeysDoNotCollide() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        addAllServers(to: settings)
        for (slot, value) in zip(ServerSlot.allCases, ["one", "two", "three", "four"]) {
            settings.setAPIKey(value, for: slot)
        }
        XCTAssertEqual(keychain.get("apiKey"), "one")
        XCTAssertEqual(keychain.get("apiKey.secondary"), "two")
        XCTAssertEqual(keychain.get("apiKey.server3"), "three")
        XCTAssertEqual(keychain.get("apiKey.server4"), "four")

        settings.setAPIKey("", for: .secondary)
        XCTAssertNil(keychain.get("apiKey.secondary"))
        XCTAssertEqual(settings.apiKey(for: .primary), "one")
        XCTAssertEqual(settings.apiKey(for: .third), "three")
    }

    func testSelectionPersistsAndDrivesTheSingleServerAPI() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()

        let first = AppSettings(defaults: defaults, keychain: keychain)
        first.setAPIKey("one", for: .primary)
        XCTAssertEqual(first.addServer(), .secondary)
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
        XCTAssertEqual(settings.addServer(), .secondary)
        settings.selectedSlot = .secondary
        XCTAssertEqual(settings.selectedSlot, .primary, "no address yet")

        settings.setBaseURLString("http://192.168.1.83:8081", for: .secondary)
        XCTAssertEqual(settings.selectedSlot, .secondary)

        settings.removeServer(.secondary)
        XCTAssertEqual(settings.selectedSlot, .primary)
        XCTAssertEqual(settings.configuredSlots, [.primary])
        XCTAssertNil(settings.makeClient(for: .secondary))
    }

    func testDisplayNameFallsBackToTheSlotName() {
        let settings = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        addAllServers(to: settings)
        XCTAssertEqual(settings.displayName(for: .primary), "Server 1")
        XCTAssertEqual(settings.displayName(for: .secondary), "Server 2")
        XCTAssertEqual(settings.displayName(for: .third), "Server 3")
        XCTAssertEqual(settings.displayName(for: .fourth), "Server 4")
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

    func testDefaultServerCountIsOne() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())
        XCTAssertEqual(settings.serverCount, 1)
        XCTAssertEqual(settings.slots, [.primary])
        XCTAssertEqual(settings.configuredSlots, [.primary])
        XCTAssertFalse(settings.hasMultipleServers)
        XCTAssertTrue(settings.canAddServer)
        XCTAssertNil(defaults.object(forKey: "settings.serverCount"), "the default is not written")
    }

    func testALegacySecondaryAddressMigratesToTwoServers() {
        let defaults = freshDefaults()
        defaults.set("http://192.168.1.83:8081", forKey: "settings.secondary.baseURL")
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())
        XCTAssertEqual(settings.serverCount, 2)
        XCTAssertEqual(settings.slots, [.primary, .secondary])
        XCTAssertTrue(settings.isConfigured(.secondary))
        XCTAssertTrue(settings.hasMultipleServers)
        XCTAssertNil(defaults.object(forKey: "settings.serverCount"), "the migration writes nothing")

        let junk = freshDefaults()
        junk.set("not a url", forKey: "settings.secondary.baseURL")
        XCTAssertEqual(AppSettings(defaults: junk, keychain: freshKeychain()).serverCount, 1)
    }

    func testServerCountPersistsAcrossInstances() {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        let first = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertNotNil(first.addServer())
        XCTAssertNotNil(first.addServer())
        XCTAssertEqual(defaults.object(forKey: "settings.serverCount") as? Int, 3)

        let second = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(second.serverCount, 3)
        second.removeServer(.third)
        XCTAssertEqual(second.serverCount, 2)
        XCTAssertEqual(AppSettings(defaults: defaults, keychain: keychain).serverCount, 2)
    }

    func testAStoredCountWeDoNotOfferClamps() {
        let defaults = freshDefaults()
        defaults.set(9, forKey: "settings.serverCount")
        XCTAssertEqual(AppSettings(defaults: defaults, keychain: freshKeychain()).serverCount, AppSettings.maxServers)
        defaults.set(0, forKey: "settings.serverCount")
        XCTAssertEqual(AppSettings(defaults: defaults, keychain: freshKeychain()).serverCount, 1)
    }

    func testAddServerFillsTheSlotsThenRefusesMore() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        var added: [ServerSlot] = []
        while let slot = settings.addServer() { added.append(slot) }
        XCTAssertEqual(added, [.secondary, .third, .fourth])
        XCTAssertEqual(settings.serverCount, AppSettings.maxServers)
        XCTAssertFalse(settings.canAddServer)
        XCTAssertNil(settings.addServer(), "no fifth server")
        XCTAssertEqual(settings.slots, [.primary, .secondary, .third, .fourth])
        XCTAssertEqual(settings.configuredSlots, [.primary], "an added server is listed before it has an address")
    }

    func testAddServerClearsWhatSatInThatSlotBefore() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        settings.setBaseURLString("http://10.9.9.9:8081", for: .secondary)
        settings.setName("Ghost", for: .secondary)
        settings.setAPIKey("ghost", for: .secondary)

        XCTAssertEqual(settings.addServer(), .secondary)
        XCTAssertEqual(settings.baseURLString(for: .secondary), "")
        XCTAssertEqual(settings.name(for: .secondary), "")
        XCTAssertEqual(settings.apiKey(for: .secondary), "")
        XCTAssertNil(keychain.get("apiKey.secondary"))
        XCTAssertFalse(settings.isConfigured(.secondary))
    }

    func testThirdAndFourthServersUseTheirOwnKeys() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)

        let first = AppSettings(defaults: defaults, keychain: keychain)
        addAllServers(to: first)
        fill(first)

        XCTAssertEqual(defaults.string(forKey: "settings.server3.baseURL"), "http://10.0.0.3:8081")
        XCTAssertEqual(defaults.string(forKey: "settings.server3.name"), "Three")
        XCTAssertEqual(keychain.get("apiKey.server3"), "k3")
        XCTAssertEqual(defaults.string(forKey: "settings.server4.baseURL"), "http://10.0.0.4:8081")
        XCTAssertEqual(defaults.string(forKey: "settings.server4.name"), "Four")
        XCTAssertEqual(keychain.get("apiKey.server4"), "k4")
        XCTAssertNil(persisted(defaults).values.first { ($0 as? String) == "k4" }, "the key stays out of UserDefaults")

        let second = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(second.serverCount, 4)
        XCTAssertEqual(second.configuredSlots, [.primary, .secondary, .third, .fourth])
        XCTAssertEqual(second.baseURLString(for: .third), "http://10.0.0.3:8081")
        XCTAssertEqual(second.displayName(for: .third), "Three")
        XCTAssertEqual(second.apiKey(for: .fourth), "k4")
    }

    func testRemoveServerCompactsTheList() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)

        let settings = AppSettings(defaults: defaults, keychain: keychain)
        addAllServers(to: settings)
        fill(settings)

        settings.removeServer(.secondary)
        XCTAssertEqual(settings.serverCount, 3)
        XCTAssertEqual(settings.slots, [.primary, .secondary, .third])
        XCTAssertEqual(settings.baseURLString(for: .secondary), "http://10.0.0.3:8081")
        XCTAssertEqual(settings.name(for: .secondary), "Three")
        XCTAssertEqual(settings.apiKey(for: .secondary), "k3")
        XCTAssertEqual(settings.baseURLString(for: .third), "http://10.0.0.4:8081")
        XCTAssertEqual(settings.name(for: .third), "Four")
        XCTAssertEqual(settings.apiKey(for: .third), "k4")
        XCTAssertEqual(settings.baseURLString(for: .fourth), "")
        XCTAssertEqual(settings.name(for: .fourth), "")
        XCTAssertEqual(settings.apiKey(for: .fourth), "")
        XCTAssertEqual(keychain.get("apiKey.secondary"), "k3")
        XCTAssertEqual(keychain.get("apiKey.server3"), "k4")
        XCTAssertNil(keychain.get("apiKey.server4"), "the emptied slot's Keychain item is gone")

        let reloaded = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.serverCount, 3)
        XCTAssertEqual(reloaded.configuredSlots, [.primary, .secondary, .third])
        XCTAssertEqual(reloaded.displayName(for: .third), "Four")
    }

    func testRemovingThePrimaryPromotesTheNextServer() throws {
        let defaults = freshDefaults()
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)

        let settings = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertNotNil(settings.addServer())
        settings.setBaseURLString("http://10.0.0.1:8081", for: .primary)
        settings.setName("One", for: .primary)
        settings.setAPIKey("k1", for: .primary)
        settings.setBaseURLString("http://10.0.0.2:8081", for: .secondary)
        settings.setName("Two", for: .secondary)
        settings.setAPIKey("k2", for: .secondary)

        settings.removeServer(.primary)
        XCTAssertEqual(settings.serverCount, 1)
        XCTAssertEqual(settings.slots, [.primary])
        XCTAssertEqual(settings.baseURLString(for: .primary), "http://10.0.0.2:8081")
        XCTAssertEqual(settings.name(for: .primary), "Two")
        XCTAssertEqual(settings.apiKey(for: .primary), "k2")
        XCTAssertEqual(defaults.string(forKey: "settings.baseURL"), "http://10.0.0.2:8081", "the legacy keys hold it now")
        XCTAssertEqual(defaults.string(forKey: "settings.name"), "Two")
        XCTAssertEqual(keychain.get("apiKey"), "k2")
        XCTAssertEqual(defaults.string(forKey: "settings.secondary.baseURL"), "")
        XCTAssertNil(keychain.get("apiKey.secondary"))

        let reloaded = AppSettings(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.serverCount, 1)
        XCTAssertEqual(reloaded.slots, [.primary])
        XCTAssertEqual(reloaded.baseURLString, "http://10.0.0.2:8081")
        XCTAssertEqual(reloaded.apiKey, "k2")
        XCTAssertEqual(reloaded.configuredSlots, [.primary])
        XCTAssertFalse(reloaded.hasMultipleServers)
    }

    func testRemovingTheSelectedServerSelectsTheOneBeforeIt() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        addAllServers(to: settings)
        fill(settings)
        settings.selectedSlot = .secondary

        settings.removeServer(.secondary)
        XCTAssertEqual(settings.selectedSlot, .primary)
    }

    func testRemovingAnEarlierServerKeepsTheSameServerSelected() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        addAllServers(to: settings)
        fill(settings)
        settings.selectedSlot = .third

        settings.removeServer(.secondary)
        XCTAssertEqual(settings.selectedSlot, .secondary, "the same server, one slot down")
        XCTAssertEqual(settings.baseURLString, "http://10.0.0.3:8081")

        settings.removeServer(.primary)
        XCTAssertEqual(settings.selectedSlot, .primary)
        XCTAssertEqual(settings.baseURLString, "http://10.0.0.3:8081")
    }

    func testRemovingTheOnlyServerIsANoOp() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())
        settings.removeServer(.primary)
        XCTAssertEqual(settings.serverCount, 1)
        XCTAssertEqual(settings.slots, [.primary])
        XCTAssertEqual(settings.baseURLString, AppSettings.defaultBaseURLString)
        XCTAssertNil(defaults.object(forKey: "settings.serverCount"), "a no-op writes nothing")

        settings.removeServer(.fourth)  // not in the list
        XCTAssertEqual(settings.serverCount, 1)

        let two = AppSettings(defaults: freshDefaults(), keychain: freshKeychain())
        XCTAssertNotNil(two.addServer())
        two.removeServer(.fourth)
        XCTAssertEqual(two.serverCount, 2)
    }

    func testSlotsPastTheCountAreNotConfiguredEvenWithAStaleAddress() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, keychain: freshKeychain())
        XCTAssertEqual(settings.addServer(), .secondary)
        settings.setBaseURLString("http://10.0.0.2:8081", for: .secondary)
        settings.setBaseURLString("http://10.0.0.9:8081", for: .third)  // left behind by an older build

        XCTAssertFalse(settings.isConfigured(.third))
        XCTAssertEqual(settings.slots, [.primary, .secondary])
        XCTAssertEqual(settings.configuredSlots, [.primary, .secondary])
        XCTAssertTrue(settings.hasMultipleServers)

        let reloaded = AppSettings(defaults: defaults, keychain: freshKeychain())
        XCTAssertEqual(reloaded.serverCount, 2, "an address past the count adds no server")
        XCTAssertFalse(reloaded.isConfigured(.third))
        XCTAssertFalse(reloaded.isConfigured(.fourth))
    }

    #if DEBUG
    func testAdoptExtraServersFromEnvironment() throws {
        let keychain = freshKeychain()
        try skipIfKeychainUnavailable(keychain)
        let settings = AppSettings(defaults: freshDefaults(), keychain: keychain)
        settings.adoptExtraServersFromEnvironment(["STRATA_SERVER_2": "not a url"])
        XCTAssertEqual(settings.serverCount, 1)
        XCTAssertFalse(settings.isConfigured(.secondary))

        settings.adoptExtraServersFromEnvironment([
            "STRATA_SERVER_2": " http://192.168.1.172:8080 ",
            "STRATA_API_KEY_2": "k2",
            "STRATA_NAME_2": "Coder",
            "STRATA_SERVER_4": "http://192.168.1.174:8080",
            "STRATA_NAME_4": "Laptop",
        ])
        XCTAssertEqual(settings.serverCount, 4, "the highest server the environment offers sets the count")
        XCTAssertEqual(settings.baseURLString(for: .secondary), "http://192.168.1.172:8080")
        XCTAssertEqual(keychain.get("apiKey.secondary"), "k2")
        XCTAssertEqual(settings.displayName(for: .secondary), "Coder")
        XCTAssertFalse(settings.isConfigured(.third), "nothing was offered for the third")
        XCTAssertEqual(settings.baseURLString(for: .fourth), "http://192.168.1.174:8080")
        XCTAssertEqual(settings.displayName(for: .fourth), "Laptop")

        settings.adoptExtraServersFromEnvironment([
            "STRATA_SERVER_2": "http://10.0.0.1:8080",
            "STRATA_SERVER_4": "http://10.0.0.4:8080",
        ])
        XCTAssertEqual(settings.baseURLString(for: .secondary), "http://192.168.1.172:8080", "a saved server wins")
        XCTAssertEqual(settings.baseURLString(for: .fourth), "http://192.168.1.174:8080")
        XCTAssertEqual(settings.serverCount, 4)
    }
    #endif
}

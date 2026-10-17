import XCTest
import Security
@testable import StrataCore

final class KeychainTests: XCTestCase {
    private let keychain = Keychain(service: "com.jacou.StrataMonitor.tests")
    private let account = "test.apiKey"

    override func setUp() {
        keychain.delete(account)
    }

    override func tearDown() {
        keychain.delete(account)
    }

    func testRoundTrip() throws {
        XCTAssertNil(keychain.get(account))

        do {
            try keychain.set("hunter2", account: account)
        } catch KeychainError.unexpectedStatus(let status) {
            // A test host without keychain entitlements cannot store anything.
            if status == errSecMissingEntitlement || status == errSecNotAvailable {
                throw XCTSkip("Keychain unavailable in this test host (\(status))")
            }
            throw KeychainError.unexpectedStatus(status)
        }

        XCTAssertEqual(keychain.get(account), "hunter2")
    }

    func testOverwrite() throws {
        try skipIfKeychainUnavailable()
        try keychain.set("first", account: account)
        try keychain.set("second", account: account)
        XCTAssertEqual(keychain.get(account), "second")
    }

    func testDelete() throws {
        try skipIfKeychainUnavailable()
        try keychain.set("gone", account: account)
        keychain.delete(account)
        XCTAssertNil(keychain.get(account))
    }

    func testAccountsAreSeparate() throws {
        try skipIfKeychainUnavailable()
        try keychain.set("a", account: "test.a")
        try keychain.set("b", account: "test.b")
        XCTAssertEqual(keychain.get("test.a"), "a")
        XCTAssertEqual(keychain.get("test.b"), "b")
        keychain.delete("test.a")
        keychain.delete("test.b")
    }

    private func skipIfKeychainUnavailable() throws {
        do {
            try keychain.set("probe", account: account)
        } catch KeychainError.unexpectedStatus(let status) {
            throw XCTSkip("Keychain unavailable in this test host (\(status))")
        }
    }
}

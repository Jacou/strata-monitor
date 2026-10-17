import Foundation
import XCTest
@testable import StrataCore

/// Loads the JSON fixtures that `Package.swift` adds to the test target as resources.
///
/// `testClass` is kept from the old Xcode-test-bundle days so the call sites read the same;
/// SwiftPM hands the resources to `Bundle.module`.
enum Fixtures {
    /// SwiftPM gives the test target a resource bundle; the Xcode test bundles put the same
    /// fixtures next to the compiled tests.
    private static func bundles(_ testClass: AnyClass?) -> [Bundle] {
        var all: [Bundle] = []
        #if SWIFT_PACKAGE
        all.append(Bundle.module)
        #endif
        if let testClass { all.append(Bundle(for: testClass)) }
        all.append(.main)
        return all
    }

    static func url(_ name: String, testClass: AnyClass? = nil) throws -> URL {
        for bundle in bundles(testClass) {
            if let url = bundle.url(forResource: name, withExtension: "json") { return url }
            if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") { return url }
            for path in bundle.paths(forResourcesOfType: "json", inDirectory: nil) where path.hasSuffix("/\(name).json") {
                return URL(fileURLWithPath: path)
            }
        }
        // Handy when running the tests straight from the source tree.
        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/StrataCoreTests/Fixtures/\(name).json")
        if FileManager.default.fileExists(atPath: fallback.path) { return fallback }

        throw NSError(
            domain: "Fixtures",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name).json"]
        )
    }

    static func data(_ name: String, testClass: AnyClass? = nil) throws -> Data {
        try Data(contentsOf: url(name, testClass: testClass))
    }

    static func metrics(named name: String = "metrics_idle", testClass: AnyClass? = nil) throws -> Metrics {
        try JSONDecoder().decode(Metrics.self, from: data(name, testClass: testClass))
    }

    static func health(testClass: AnyClass? = nil) throws -> Health {
        try JSONDecoder().decode(Health.self, from: data("health", testClass: testClass))
    }

    static func json(_ text: String) -> Data { Data(text.utf8) }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: json(text))
    }
}

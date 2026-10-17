// swift-tools-version: 6.0
import PackageDescription

/// The parts of Strata Monitor that are not iOS: the models, the client, the poller, the
/// settings, the palette and the views that draw them. The iOS app and the macOS menu bar app
/// both build on this.
let package = Package(
    name: "StrataCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "StrataCore", targets: ["StrataCore"])
    ],
    targets: [
        .target(
            name: "StrataCore",
            path: "Sources/StrataCore"
        ),
        .testTarget(
            name: "StrataCoreTests",
            dependencies: ["StrataCore"],
            path: "Tests/StrataCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

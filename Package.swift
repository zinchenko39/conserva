// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Conserva",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that does not need AppKit: the shelf model, storage, sorting incoming things into kinds.
        .target(name: "ConservaCore", path: "Sources/ConservaCore"),
        .executableTarget(
            name: "Conserva",
            dependencies: ["ConservaCore"],
            path: "Sources/Conserva",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ConservaCoreTests", dependencies: ["ConservaCore"], path: "Tests/ConservaCoreTests"),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

// Platform-agnostic modules (no SwiftUI/UIKit) so the domain model, persistence and their
// tests run on any Swift 6 toolchain, including Linux CI. See docs/architecture/IOS_ARCHITECTURE.md.
let package = Package(
    name: "DoddyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DoddyCore", targets: ["DoddyCore"]),
        .library(name: "DoddyDesignTokens", targets: ["DoddyDesignTokens"]),
        .library(name: "DoddyPersistence", targets: ["DoddyPersistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.9.0"),
    ],
    targets: [
        .target(name: "DoddyCore"),
        .target(name: "DoddyDesignTokens"),
        .target(
            name: "DoddyPersistence",
            dependencies: ["DoddyCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "DoddyCoreTests", dependencies: ["DoddyCore"]),
        .testTarget(name: "DoddyDesignTokensTests", dependencies: ["DoddyDesignTokens"]),
        .testTarget(name: "DoddyPersistenceTests", dependencies: ["DoddyPersistence"]),
    ]
)

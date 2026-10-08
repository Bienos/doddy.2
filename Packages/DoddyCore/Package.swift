// swift-tools-version: 6.0
import PackageDescription

// Platform-agnostic modules (no SwiftUI/UIKit) so the domain model and its tests
// run on any Swift 6 toolchain, including Linux CI. See docs/architecture/IOS_ARCHITECTURE.md.
let package = Package(
    name: "DoddyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DoddyCore", targets: ["DoddyCore"]),
        .library(name: "DoddyDesignTokens", targets: ["DoddyDesignTokens"]),
    ],
    targets: [
        .target(name: "DoddyCore"),
        .target(name: "DoddyDesignTokens"),
        .testTarget(name: "DoddyCoreTests", dependencies: ["DoddyCore"]),
        .testTarget(name: "DoddyDesignTokensTests", dependencies: ["DoddyDesignTokens"]),
    ]
)

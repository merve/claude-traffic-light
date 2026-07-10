// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ClaudeStatus",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        // Pure (Foundation) logic — the testable core.
        .target(
            name: "ClaudeStatusCore",
            path: "Sources/ClaudeStatusCore"
        ),
        // AppKit application (menu bar, icon, menu).
        .executableTarget(
            name: "ClaudeStatus",
            dependencies: ["ClaudeStatusCore"],
            path: "Sources/ClaudeStatus"
        ),
        // Floating desktop widget (draggable, pinnable traffic light + session list).
        .executableTarget(
            name: "ClaudeWidget",
            dependencies: ["ClaudeStatusCore"],
            path: "Sources/ClaudeWidget"
        ),
        // Core tests.
        .testTarget(
            name: "ClaudeStatusCoreTests",
            dependencies: ["ClaudeStatusCore"],
            path: "Tests/ClaudeStatusCoreTests"
        )
    ]
)

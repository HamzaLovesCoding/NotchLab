// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchApp",
            path: "Sources/NotchApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Small command-line relay that Claude Code / Codex hooks run; ships inside the app.
        .executableTarget(
            name: "NotchHook",
            path: "Sources/NotchHook",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

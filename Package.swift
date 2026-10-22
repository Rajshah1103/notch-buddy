// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchHub",
    platforms: [.macOS(.v14)],
    targets: [
        // Spaces/windows/AX. The only place private macOS APIs live.
        .target(name: "WindowEngine"),
        // Notch panel, geometry and hover. Knows nothing about windows or integrations.
        .target(name: "NotchCore"),
        // Live Claude Code activity and token counts, read from its local session transcripts.
        .target(name: "ClaudeUsage"),
        .executableTarget(name: "NotchHub", dependencies: ["WindowEngine", "NotchCore", "ClaudeUsage"]),
        .testTarget(name: "WindowEngineTests", dependencies: ["WindowEngine"]),
        .testTarget(name: "ClaudeUsageTests", dependencies: ["ClaudeUsage"]),
    ]
)

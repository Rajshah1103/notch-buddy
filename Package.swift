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
        // Pull requests that need you and the state of your own, from GitHub's GraphQL API.
        .target(name: "GitHubKit"),
        // Build state and live progress from a Jenkins server, which is usually behind a VPN.
        .target(name: "JenkinsKit"),
        // Today's meetings from the Calendar app (which can hold Google, iCloud and Exchange calendars), with
        // video-call links found in the invite.
        .target(name: "CalendarKit"),
        // Unread mail from Gmail (read-only), signed in with the user's own Google Cloud OAuth client.
        .target(name: "GmailKit"),
        // The buddy: moods, how the blob moves, and the rules for which event gets announced and when.
        .target(name: "BuddyKit"),
        // Lets scripts, harness hooks and connectors talk to the app: a local socket and its message format.
        .target(name: "ConnectorKit"),
        .executableTarget(name: "NotchHub", dependencies: ["ConnectorKit", "WindowEngine", "NotchCore", "ClaudeUsage", "GitHubKit", "JenkinsKit", "CalendarKit", "GmailKit", "BuddyKit"]),
        .testTarget(name: "WindowEngineTests", dependencies: ["WindowEngine"]),
        .testTarget(name: "ClaudeUsageTests", dependencies: ["ClaudeUsage"]),
        .testTarget(name: "GitHubKitTests", dependencies: ["GitHubKit"]),
        .testTarget(name: "JenkinsKitTests", dependencies: ["JenkinsKit"]),
        .testTarget(name: "CalendarKitTests", dependencies: ["CalendarKit"]),
        .testTarget(name: "GmailKitTests", dependencies: ["GmailKit"]),
        .testTarget(name: "BuddyKitTests", dependencies: ["BuddyKit"]),
        .testTarget(name: "ConnectorKitTests", dependencies: ["ConnectorKit"]),
    ]
)

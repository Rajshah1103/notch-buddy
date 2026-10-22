// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchHub",
    platforms: [.macOS(.v13)],
    targets: [
        // Spaces/windows/AX. The only place private macOS APIs live.
        .target(name: "WindowEngine"),
        // Notch panel, geometry and hover. Knows nothing about windows or integrations.
        .target(name: "NotchCore"),
        .executableTarget(name: "NotchHub", dependencies: ["WindowEngine", "NotchCore"]),
        .testTarget(name: "WindowEngineTests", dependencies: ["WindowEngine"]),
    ]
)

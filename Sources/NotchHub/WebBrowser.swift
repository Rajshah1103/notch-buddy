import AppKit
import WindowEngine

/// Opening typed addresses and searches in a new browser tab, in a chosen profile.
@MainActor
final class WebBrowser: ObservableObject {
    @Published private(set) var profiles: [BrowserProfile] = []
    @Published private(set) var lastUsed: String?
    @Published private(set) var browserName = "your browser"
    private(set) var bundleID: String?

    /// The first installed Chromium browser. Only these can open a tab in a chosen profile.
    private static let candidates = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac"]

    private var isPreview = false

    func reload() {
        guard !isPreview else { return }       // design renders use invented profiles, never the real ones
        let candidate = Self.candidates.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        bundleID = candidate
        guard let candidate else { profiles = []; browserName = "your browser"; return }
        browserName = FileManager.default.displayName(atPath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate)?.path ?? "")
            .replacingOccurrences(of: ".app", with: "")
        Task.detached {
            let list = BrowserProfiles.load(bundleID: candidate)
            await MainActor.run {
                self.profiles = list.profiles
                self.lastUsed = list.lastUsed
            }
        }
    }

    /// The profile to preselect: the one chosen last time here, else the one the browser used last.
    func defaultProfile(preferred: String?) -> BrowserProfile? {
        profiles.first { $0.directory == preferred } ?? profiles.first { $0.directory == lastUsed } ?? profiles.first
    }

    /// Opens `url` as a new tab. `open -n` starts a throwaway copy of the browser that hands the address
    /// to the running one and exits; that is how a profile can be named when the browser is already open.
    func open(_ url: URL, in profile: BrowserProfile?) {
        guard let bundleID else { NSWorkspace.shared.open(url); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments = ["-n", "-b", bundleID, "--args"]
        if let profile { arguments.append("--profile-directory=\(profile.directory)") }
        arguments.append(url.absoluteString)
        process.arguments = arguments
        PerfProbe.log("web open: \(url.host ?? "?") in profile folder \(profile?.directory ?? "(browser default)")")
        // Launched from a background app, the browser does not always come forward by itself.
        process.terminationHandler = { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
        }
        try? process.run()
    }

    /// For the snapshot tool.
    func loadForPreview(_ profiles: [BrowserProfile], lastUsed: String?) {
        self.profiles = profiles
        self.lastUsed = lastUsed
        browserName = "Google Chrome"
        isPreview = true
    }
}

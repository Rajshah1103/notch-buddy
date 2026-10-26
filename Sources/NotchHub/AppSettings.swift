import AppKit
import WindowEngine
import Carbon.HIToolbox
import ServiceManagement

struct HotKeyBinding: Codable, Equatable {
    var keyCode: Int
    /// Carbon flags: controlKey, optionKey, cmdKey, shiftKey.
    var modifiers: Int

    static let `default` = HotKeyBinding(keyCode: kVK_Space, modifiers: controlKey | optionKey)

    /// "⌃⌥Space"
    var display: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static let names: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Grave: "`", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
        kVK_ANSI_Slash: "/", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
    ]

    static func keyName(_ code: Int) -> String { names[code] ?? "Key \(code)" }

    /// Carbon flags from an AppKit event's modifier flags.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return result
    }
}

/// User preferences, persisted in UserDefaults. Views bind to these; the app delegate reacts to changes.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// How long the pointer must rest on the notch before it opens, in milliseconds.
    @Published var hoverDelayMs: Double { didSet { defaults.set(hoverDelayMs, forKey: "hoverDelayMs"); changed() } }
    @Published var showClaudeActivity: Bool { didSet { defaults.set(showClaudeActivity, forKey: "showClaudeActivity"); changed() } }
    /// Used when you type something that is not an address into search and open it on the web.
    @Published var searchEngine: SearchEngine { didSet { defaults.set(searchEngine.rawValue, forKey: "searchEngine"); changed() } }
    /// The browser profile last chosen for opening web searches (its folder name).
    @Published var webProfile: String? { didSet { defaults.set(webProfile, forKey: "webProfile") } }
    /// Rank results you open often higher. Everything learned stays on this Mac.
    @Published var learnFromUse: Bool { didSet { defaults.set(learnFromUse, forKey: "learnFromUse") } }
    /// Apps (by bundle identifier, or name when there is none) that never appear in the notch.
    @Published var hiddenApps: Set<String> { didSet { defaults.set(Array(hiddenApps), forKey: "hiddenApps"); changed() } }
    @Published var showGitHub: Bool { didSet { defaults.set(showGitHub, forKey: "showGitHub"); changed() } }
    /// Fall back to the GitHub command line tool's login when no token has been pasted.
    @Published var githubUsesCommandLine: Bool { didSet { defaults.set(githubUsesCommandLine, forKey: "githubUsesCommandLine"); changed() } }
    /// Pop-out bubbles under the notch that announce events (new mail, builds, reviews, meetings).
    @Published var showBubbles: Bool { didSet { defaults.set(showBubbles, forKey: "showBubbles"); changed() } }
    /// The buddy comes out now and then to dance, wave and nap when nothing else is going on.
    @Published var idleBuddy: Bool { didSet { defaults.set(idleBuddy, forKey: "idleBuddy"); changed() } }
    /// Whether it says a word or two while it does.
    @Published var idleBuddyText: Bool { didSet { defaults.set(idleBuddyText, forKey: "idleBuddyText"); changed() } }
    @Published var showGmail: Bool { didSet { defaults.set(showGmail, forKey: "showGmail"); changed() } }
    @Published var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: "showCalendar"); changed() } }
    @Published var showJenkins: Bool { didSet { defaults.set(showJenkins, forKey: "showJenkins"); changed() } }
    @Published var jenkinsURL: String { didSet { defaults.set(jenkinsURL, forKey: "jenkinsURL"); changed() } }
    @Published var jenkinsUser: String { didSet { defaults.set(jenkinsUser, forKey: "jenkinsUser"); changed() } }
    /// Comma-separated; only jobs whose name contains one of these are shown. Empty shows all.
    @Published var jenkinsFilter: String { didSet { defaults.set(jenkinsFilter, forKey: "jenkinsFilter"); changed() } }
    @Published var searchHotKey: HotKeyBinding { didSet {
        if let data = try? JSONEncoder().encode(searchHotKey) { defaults.set(data, forKey: "searchHotKey") }
        changed()
    } }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: "hasOnboarded") }
        set { defaults.set(newValue, forKey: "hasOnboarded") }
    }

    /// Set by the app delegate; called after any change so the running app can follow.
    var onChange: (() -> Void)?

    private init() {
        hoverDelayMs = defaults.object(forKey: "hoverDelayMs") as? Double ?? 40
        showClaudeActivity = defaults.object(forKey: "showClaudeActivity") as? Bool ?? true
        searchEngine = SearchEngine(rawValue: defaults.string(forKey: "searchEngine") ?? "") ?? .google
        webProfile = defaults.string(forKey: "webProfile")
        learnFromUse = defaults.object(forKey: "learnFromUse") as? Bool ?? true
        hiddenApps = Set(defaults.stringArray(forKey: "hiddenApps") ?? [])
        showGitHub = defaults.object(forKey: "showGitHub") as? Bool ?? true
        githubUsesCommandLine = defaults.object(forKey: "githubUsesCommandLine") as? Bool ?? true
        showBubbles = defaults.object(forKey: "showBubbles") as? Bool ?? true
        idleBuddy = defaults.object(forKey: "idleBuddy") as? Bool ?? true
        idleBuddyText = defaults.object(forKey: "idleBuddyText") as? Bool ?? true
        showGmail = defaults.bool(forKey: "showGmail")       // off until chosen: it needs the user's own Google client
        showCalendar = defaults.bool(forKey: "showCalendar")      // off until chosen, so no permission prompt appears unasked
        showJenkins = defaults.bool(forKey: "showJenkins")
        jenkinsURL = defaults.string(forKey: "jenkinsURL") ?? ""
        jenkinsUser = defaults.string(forKey: "jenkinsUser") ?? ""
        jenkinsFilter = defaults.string(forKey: "jenkinsFilter") ?? ""
        searchHotKey = (defaults.data(forKey: "searchHotKey").flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) }) ?? .default
    }

    private func changed() { onChange?() }

    // MARK: - Launch at login

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
        objectWillChange.send()
    }
}

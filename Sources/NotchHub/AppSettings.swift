import AppKit
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
        hoverDelayMs = defaults.object(forKey: "hoverDelayMs") as? Double ?? 60
        showClaudeActivity = defaults.object(forKey: "showClaudeActivity") as? Bool ?? true
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

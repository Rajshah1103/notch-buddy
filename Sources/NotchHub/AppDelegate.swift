import AppKit
import Carbon.HIToolbox
import ClaudeUsage
import NotchCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowsModel()
    private let claude = ClaudeModel()
    private let settings = AppSettings.shared
    private let presenter = WindowPresenter()
    private var notch: NotchManager?
    private var statusItem: NSStatusItem?
    private var searchHotKey: HotKey?
    private var claudeRunning = false
    private var registeredHotKey: HotKeyBinding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = windows
        let claudeModel = claude
        notch = NotchManager(
            expandedSize: CGSize(width: 1000, height: 440),
            onPrefetch: { model.refresh(previews: false) },
            onExpand: { model.refresh(previews: true) },
            content: { state in AnyView(SwitcherView(model: model, claude: claudeModel, notch: state)) },
            liveContent: { state in AnyView(ClaudeLiveView(model: claudeModel, notch: state)) }
        )
        PerfProbe.startStallWatchdog()

        // While Claude Code works, the collapsed notch widens into a live activity.
        claude.onWorkingChange = { [weak self] working in
            PerfProbe.log("claude working = \(working)")
            self?.notch?.setLive(extra: working ? LiveLayout.extra : nil)
        }
        model.startTrackingRecents()
        notch?.start()
        model.refresh(previews: false)
        setUpStatusItem()

        // Settings drive the running app; apply them now and whenever they change.
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        if !settings.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showWelcome() }
        }
    }

    // MARK: - Settings

    private func applySettings() {
        notch?.hoverDelay = settings.hoverDelayMs / 1000

        if settings.showClaudeActivity, !claudeRunning {
            claudeRunning = true
            claude.start()
        } else if !settings.showClaudeActivity, claudeRunning {
            claudeRunning = false
            claude.stop()
        }

        // Re-register the search shortcut only when it changed (dropping the old one first).
        if registeredHotKey != settings.searchHotKey {
            registeredHotKey = settings.searchHotKey
            searchHotKey = nil
            searchHotKey = HotKey(keyCode: settings.searchHotKey.keyCode, modifiers: settings.searchHotKey.modifiers) { [weak self] in
                MainActor.assumeIsolated { self?.openSearch() }
            }
        }
    }

    // MARK: - Windows

    @objc private func showSettings() {
        presenter.show("settings", title: "Notch Hub Settings") {
            SettingsView(settings: settings) { [weak self] in self?.showWelcome() }
        }
    }

    private func showWelcome() {
        presenter.show("welcome", title: "Welcome to Notch Hub") {
            WelcomeView { [weak self] in
                self?.settings.hasOnboarded = true
                self?.presenter.close("welcome")
            }
        }
    }

    // MARK: - Menu bar item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Notch Hub")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openSearch() {
        windows.refresh(previews: true)
        notch?.toggleSearch()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let search = menu.addItem(withTitle: "Search…", action: #selector(openSearch), keyEquivalent: "")
        search.toolTip = settings.searchHotKey.display

        menu.addItem(.separator())
        // One line of status, only when something still needs attention.
        let missing = PermissionKind.allCases.filter { Permissions.state(of: $0) == .notGranted }
        if !missing.isEmpty {
            let item = menu.addItem(withTitle: "\(missing.count) permission\(missing.count == 1 ? "" : "s") needed…",
                                    action: #selector(showSettings), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        }
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Hub", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
    }
}

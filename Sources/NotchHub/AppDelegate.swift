import AppKit
import Carbon.HIToolbox
import ClaudeUsage
import NotchCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowsModel()
    private let claude = ClaudeModel()
    private let github = GitHubModel()
    private let web = WebBrowser()
    private let learning = LearningStore()
    private let jenkins = JenkinsModel()
    private let calendar = CalendarModel()
    private let gmail = GmailModel()
    private lazy var live = LiveActivityModel(claude: claude, jenkins: jenkins, calendar: calendar)
    private lazy var hub = IntegrationHub(integrations: [
        ClaudeIntegration(model: claude),
        GitHubIntegration(model: github),
        JenkinsIntegration(model: jenkins),
        CalendarIntegration(model: calendar),
        GmailIntegration(model: gmail),
    ])
    private let settings = AppSettings.shared
    private let presenter = WindowPresenter()
    private var notch: NotchManager?
    private var statusItem: NSStatusItem?
    private var searchHotKey: HotKey?
    private var registeredHotKey: HotKeyBinding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = windows
        let liveModel = live
        let hub = hub
        let web = web
        let learning = learning
        notch = NotchManager(
            expandedSize: CGSize(width: 1000, height: 440),
            onPrefetch: { model.refresh(previews: false) },
            onExpand: { model.refresh(previews: true); hub.refresh() },
            content: { state in AnyView(SwitcherView(model: model, hub: hub, web: web, learning: learning, notch: state)) },
            liveContent: { state in AnyView(LiveView(model: liveModel, notch: state)) }
        )
        notch?.trace = { PerfProbe.log($0) }
        PerfProbe.startStallWatchdog()

        // While Claude Code works, the collapsed notch widens into a live activity.
        live.onActiveChange = { [weak self] active in
            PerfProbe.log("live activity = \(active)")
            self?.notch?.setLive(extra: active ? LiveLayout.extra : nil)
        }
        AppActions.openSettings = { [weak self] in self?.showSettings() }
        model.startTrackingRecents()
        model.startTrackingSpaces()
        model.startWatchingTabs()
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

        hub.apply()      // start or stop each integration to match Settings
        windows.hiddenAppsChanged()

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
            SettingsView(settings: settings, learning: learning,
                         showWelcome: { [weak self] in self?.showWelcome() },
                         diagnostics: { [windows, settings] in Diagnostics.report(model: windows, settings: settings) })
        }
    }

    @objc private func showWelcomeWindow() { showWelcome() }

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
                                    action: #selector(showWelcomeWindow), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        }
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Hub", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
    }
}

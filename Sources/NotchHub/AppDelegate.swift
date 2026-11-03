import AppKit
import Carbon.HIToolbox
import BuddyKit
import ConnectorKit
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
    private let moments = MomentCenter()
    private var bridge: BuddyBridge?
    private var socket: SocketServer?
    private lazy var live = LiveActivityModel(claude: claude, jenkins: jenkins, calendar: calendar)
    private lazy var hub = IntegrationHub(integrations: [
        ClaudeIntegration(model: claude),
        GitHubIntegration(model: github),
        JenkinsIntegration(model: jenkins),
        CalendarIntegration(model: calendar),
        GmailIntegration(model: gmail),
    ] + ConnectorStore.load().map { found in
        ConnectorIntegration(model: ConnectorModel(found: found) { [moments] in moments.post(ExternalMoments.moment(from: $0)) })
    })
    private let settings = AppSettings.shared
    private let presenter = WindowPresenter()
    private var notch: NotchManager?
    private var statusItem: NSStatusItem?
    private var searchHotKey: HotKey?
    private var registeredHotKey: HotKeyBinding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()

        let model = windows
        let liveModel = live
        let hub = hub
        let web = web
        let learning = learning
        notch = NotchManager(
            expandedSize: CGSize(width: 1000, height: 440),
            onPrefetch: { model.refresh(previews: false) },
            onExpand: { model.refresh(previews: true); hub.refresh() },
            content: { state in AnyView(SwitcherView(model: model, hub: hub, web: web, learning: learning, live: liveModel, notch: state)) },
            liveContent: { [moments] state in AnyView(LiveView(model: liveModel, center: moments, notch: state)) }
        )
        notch?.trace = { PerfProbe.log($0) }
        moments.onBubble = { [weak self] size in self?.notch?.setBubble(size: size) }
        notch?.setBubbleHover { [weak self] inside in self?.moments.setHeld(inside) }
        moments.onActivate = { [weak self] moment, action in
            if action, let url = moment.url { LinkOpener.open(url, for: Self.linkKey(moment.source)) }
            else if let panel = moment.panel { self?.notch?.openPanel(panel) }
        }
        socket = SocketServer { [weak self] message in
            MainActor.assumeIsolated {
                if case .moment(let incoming) = message { self?.moments.post(ExternalMoments.moment(from: incoming)) }
            }
        }
        socket?.start()
        bridge = BuddyBridge(center: moments, claude: claude, gmail: gmail, jenkins: jenkins, github: github, calendar: calendar)
        PerfProbe.startStallWatchdog()

        // While Claude Code works, the collapsed notch widens into a live activity.
        live.onEarsChange = { [weak self] extra in
            PerfProbe.log("ears extra = \(Int(extra))")
            self?.notch?.setLive(extra: extra > 0 ? extra : nil)
        }
        live.isCalm = { [moments] in moments.showing == nil }
        AppActions.openSettings = { [weak self] in self?.showSettings() }
        model.startTrackingRecents()
        model.startTrackingSpaces()
        model.startWatchingTabs()
        LinkOpener.browser = web
        web.reload()
        notch?.start()
        // Debug: NOTCHHUB_DEMO_MOMENT=gmail|build-ok|build-fail|review|checks-bad|meeting|claude-done|claude-approve shows an
        // invented bubble a moment after launch, so the real window can be checked without any real mail or builds.
        if let kind = ProcessInfo.processInfo.environment["NOTCHHUB_DEMO_MOMENT"], let demo = Preview.DemoMoments.make(kind) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.moments.post(demo) }
        }
        model.refresh(previews: false)
        setUpStatusItem()

        // Settings drive the running app; apply them now and whenever they change.
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        if !settings.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showWelcome() }
        }
    }

    /// An app with no menu bar item has no Edit menu, and ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z are menu shortcuts: without
    /// one, text fields (the notch's search, token and client ID fields, Settings) cannot paste or copy.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        let appSlot = NSMenuItem()
        appSlot.submenu = NSMenu()                          // the application menu slot
        let editSlot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editSlot.submenu = edit
        main.addItem(appSlot)
        main.addItem(editSlot)
        NSApp.mainMenu = main
    }

    // MARK: - Settings

    private func applySettings() {
        notch?.hoverDelay = settings.hoverDelayMs / 1000
        live.idleText = settings.idleBuddyText
        live.idleEnabled = settings.idleBuddy

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

    /// Which setting decides the browser profile for a bubble's link.
    private static func linkKey(_ source: MomentSource) -> String {
        switch source {
        case .gmail: return "gmail"
        case .github: return "github"
        case .build: return "jenkins"
        case .calendar: return "calendar"
        default: return "other"
        }
    }

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

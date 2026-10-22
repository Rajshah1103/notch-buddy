import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import NotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowsModel()
    private var notch: NotchManager?
    private var statusItem: NSStatusItem?
    private var searchHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = windows
        notch = NotchManager(
            expandedSize: CGSize(width: 1000, height: 440),
            onPrefetch: { model.refresh(previews: false) },
            onExpand: { model.refresh(previews: true) },
            content: { state in AnyView(SwitcherView(model: model, notch: state)) }
        )
        PerfProbe.startStallWatchdog()
        model.startTrackingRecents()
        notch?.start()

        // Control-Option-Space opens search. Chosen because Spotlight, Raycast and Alfred
        // all use Command or Option with Space.
        searchHotKey = HotKey(keyCode: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in
            MainActor.assumeIsolated {
                self?.windows.refresh(previews: true)
                self?.notch?.toggleSearch()
            }
        }
        model.refresh(previews: false)
        setUpStatusItem()
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

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
    }

    @objc private func openSearch() {
        windows.refresh(previews: true)
        notch?.toggleSearch()
    }

    @objc private func grantAccessibility() { Permissions.requestAccessibility() }
    @objc private func grantScreenRecording() { Permissions.requestScreenRecording() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let search = menu.addItem(withTitle: "Search…", action: #selector(openSearch), keyEquivalent: "")
        search.toolTip = "Control-Option-Space"
        menu.addItem(.separator())

        let accessibility = menu.addItem(withTitle: "Accessibility (jump to windows)",
                                         action: #selector(grantAccessibility), keyEquivalent: "")
        accessibility.state = Permissions.accessibilityGranted ? .on : .off
        let recording = menu.addItem(withTitle: "Screen Recording (window titles)",
                                     action: #selector(grantScreenRecording), keyEquivalent: "")
        recording.state = Permissions.screenRecordingGranted ? .on : .off

        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login",
                                 action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Hub", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
    }
}

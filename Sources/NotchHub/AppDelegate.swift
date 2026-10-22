import AppKit
import ServiceManagement
import SwiftUI
import NotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowsModel()
    private var notch: NotchManager?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = windows
        notch = NotchManager(
            expandedSize: CGSize(width: 1000, height: 340),
            onPrefetch: { model.refresh(previews: false) },
            onExpand: { model.refresh(previews: true) },
            content: { state in AnyView(WindowsView(model: model, notch: state)) }
        )
        notch?.start()
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

    @objc private func grantAccessibility() { Permissions.requestAccessibility() }
    @objc private func grantScreenRecording() { Permissions.requestScreenRecording() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

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

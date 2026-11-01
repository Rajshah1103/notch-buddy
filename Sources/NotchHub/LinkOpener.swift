import AppKit
import WindowEngine

/// Every web link the app opens for an integration (a pull request, a mail, a build, a meeting) goes through here,
/// so it can land in the Chrome profile chosen for that integration instead of whichever was used last.
@MainActor
enum LinkOpener {
    static var browser: WebBrowser?
    /// Stored in place of a profile folder when the choice is "ask each time".
    static let ask = "ask"

    static func open(_ url: URL, for integration: String) {
        guard let browser, url.scheme == "https" || url.scheme == "http" else { NSWorkspace.shared.open(url); return }
        switch AppSettings.shared.linkProfiles[integration] {
        case nil:
            NSWorkspace.shared.open(url)          // no choice made: the browser's own default, as before
        case ask?:
            choose(url, browser)
        case let directory?:
            browser.open(url, in: BrowserProfile(directory: directory, name: directory, email: nil))
        }
    }

    /// A small menu at the pointer listing the profiles; picking one opens the link there.
    private static func choose(_ url: URL, _ browser: WebBrowser) {
        let profiles = WebBrowser.installedProfiles()
        guard profiles.count > 1 else { browser.open(url, in: profiles.first); return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = MenuTarget { profile in browser.open(url, in: profile) }
        for profile in profiles {
            let title = profile.email.map { "\(profile.name) · \($0)" } ?? profile.name
            let item = NSMenuItem(title: title, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = profile
            menu.addItem(item)
        }
        menuTarget = target                         // a menu does not retain its targets
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static var menuTarget: MenuTarget?

    private final class MenuTarget: NSObject {
        let handler: (BrowserProfile) -> Void
        init(_ handler: @escaping (BrowserProfile) -> Void) { self.handler = handler }
        @objc func pick(_ sender: NSMenuItem) {
            if let profile = sender.representedObject as? BrowserProfile { handler(profile) }
        }
    }
}

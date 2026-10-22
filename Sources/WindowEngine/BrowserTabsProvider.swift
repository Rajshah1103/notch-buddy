import AppKit

/// Reads and activates tabs in Chromium-based browsers through their AppleScript dictionary.
/// The first call prompts the user to allow Automation for each browser.
public final class BrowserTabsProvider {
    /// Browsers that share Chrome's scripting dictionary, by bundle identifier.
    public static let supportedBundleIDs: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
    ]

    /// Apple Events are not thread safe, so all scripts run one at a time on this queue.
    private let queue = DispatchQueue(label: "notchhub.applescript", qos: .userInitiated)

    public init() {}

    public func windows(bundleID: String) async -> Result<[BrowserWindow], BrowserError> {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil else {
            return .failure(.notRunning)
        }
        let source = Self.readScript(bundleID: bundleID)
        return await run(source).map(BrowserTabsParser.parse)
    }

    public func activate(_ tab: BrowserTab, bundleID: String) {
        let source = """
        tell application id "\(bundleID)"
            set w to window id \(tab.windowID)
            if minimized of w then set minimized of w to false
            set active tab index of w to \(tab.index)
            set index of w to 1
            activate
        end tell
        """
        queue.async { _ = Self.execute(source) }
    }

    private func run(_ source: String) async -> Result<String, BrowserError> {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Self.execute(source)) }
        }
    }

    private static func execute(_ source: String) -> Result<String, BrowserError> {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.failed("invalid script")) }
        let output = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            // -1743: not authorized to send Apple events to the application.
            return .failure(code == -1743 ? .notAuthorized : .failed(error[NSAppleScript.errorMessage] as? String ?? "unknown"))
        }
        return .success(output.stringValue ?? "")
    }

    /// Fetches everything in one Apple event per property (cheap), then formats in-script.
    private static func readScript(bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            set ids to id of every window
            set frames to bounds of every window
            set actives to active tab index of every window
            set allTitles to title of every tab of every window
            set allURLs to URL of every tab of every window
        end tell
        set out to ""
        repeat with w from 1 to count of ids
            set b to item w of frames
            set out to out & "W" & tab & (item w of ids) & tab & (item 1 of b) & tab & (item 2 of b) & tab & (item 3 of b) & tab & (item 4 of b) & linefeed
            set titles to item w of allTitles
            set urls to item w of allURLs
            repeat with t from 1 to count of titles
                set isActive to 0
                if t = (item w of actives) then set isActive to 1
                set out to out & "T" & tab & (item w of ids) & tab & t & tab & isActive & tab & (item t of titles) & tab & (item t of urls) & linefeed
            end repeat
        end repeat
        return out
        """
    }
}

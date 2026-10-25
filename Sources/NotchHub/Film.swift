import AppKit
import SwiftUI

/// Launch-film stills: the real views, drawn from invented data on a transparent background. The frames themselves are
/// composed from these by `FilmComposer`, so the film never touches the user's windows, accounts or pointer.
@MainActor
enum Film {
    static func renderStill(_ name: String, to path: String) {
        PreviewSeed.film = true
        switch name {
        case "dock":      Preview.render(to: path, demo: true, app: "Visual Studio Code", light: false, search: nil)
        case "tabs":
            let title = "Grafana \u{00B7} p99 latency"
            Preview.render(to: path, demo: true, app: "Google Chrome", light: false, search: nil, tabShot: true, tabTitle: title)
        case "search":    Preview.render(to: path, demo: true, app: nil, light: false, search: "api")
        case "claude":    Preview.render(to: path, demo: true, app: nil, light: false, search: nil, claudePanel: true)
        case "gmail":     Preview.render(to: path, demo: true, app: nil, light: false, search: nil, gmailPanel: true)
        case "jenkins":   Preview.render(to: path, demo: true, app: nil, light: false, search: nil, jenkinsPanel: true)
        case "github":    Preview.render(to: path, demo: true, app: nil, light: false, search: nil, githubPanel: true)
        case "calendar":  Preview.render(to: path, demo: true, app: nil, light: false, search: nil, calendarPanel: true)
        case "ears-claude":  Preview.render(to: path, demo: true, app: nil, light: false, search: nil, live: true)
        case "ears-build":   Preview.render(to: path, demo: true, app: nil, light: false, search: nil, liveBuild: true)
        case "ears-meeting": Preview.render(to: path, demo: true, app: nil, light: false, search: nil, liveMeeting: true)
        default:
            if name.hasPrefix("search:") {
                Preview.render(to: path, demo: true, app: nil, light: false, search: String(name.dropFirst(7)))
            } else if name.hasPrefix("bubble-") {
                Preview.render(to: path, demo: true, app: nil, light: false, search: nil, demoMoment: String(name.dropFirst(7)))
            } else {
                print("unknown still \(name)")
            }
        }
    }
}

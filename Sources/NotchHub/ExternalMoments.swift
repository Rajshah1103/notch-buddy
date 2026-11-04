import BuddyKit
import ConnectorKit
import Foundation

/// Messages from the local socket, turned into the same moments the built-in sources make.
enum ExternalMoments {
    static func moment(from incoming: Message.Incoming) -> Moment {
        let known: [String: String] = ["claude": "sparkle", "gmail": "envelope.fill", "github": "arrow.triangle.pull",
                                       "build": "hammer.fill", "calendar": "calendar", "slack": "number"]
        let url = incoming.url.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        let headline = incoming.headline
        return Moment(id: incoming.id ?? "\(incoming.source):\(headline)",
                      source: MomentSource(incoming.source.lowercased()),
                      mood: incoming.mood.flatMap(Mood.init(rawValue:)) ?? .alert,
                      headline: headline, detail: incoming.detail,
                      symbol: incoming.symbol ?? known[incoming.source.lowercased()] ?? "bell.fill",
                      priority: min(max(incoming.priority ?? 50, 0), 89),     // outside scripts never skip the pacing rule
                      ttl: min(max(incoming.ttl ?? 4.5, 2), 15), group: incoming.group,
                      actionTitle: url == nil ? nil : "Open", url: url, tintHex: incoming.tint)
    }

    /// A bubble for the two moments in an AI session that want you: it needs approval, or it finished.
    static func moment(from event: Message.AgentEvent) -> Moment? {
        let name = AgentTracker.title(event.harness)
        switch event.state {
        case .needsApproval:
            return Moment(id: "agent:\(event.harness):\(event.session):approval", source: MomentSource(event.harness.lowercased()), mood: .needsYou,
                          headline: "\(name) needs your OK", detail: event.project, symbol: "hand.raised.fill", priority: 85, ttl: 7)
        case .done:
            return Moment(id: "agent:\(event.harness):\(event.session):done", source: MomentSource(event.harness.lowercased()), mood: .happy,
                          headline: "\(name) finished", detail: event.project, symbol: "checkmark.circle.fill", priority: 60)
        case .working, .idle:
            return nil
        }
    }
}

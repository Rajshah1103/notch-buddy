import BuddyKit
import CalendarKit
import ClaudeUsage
import Foundation
import GitHubKit
import GmailKit
import JenkinsKit

/// What the buddy announces, worked out from how each source changed. Pure functions: each takes what it
/// knew before and what it sees now, and returns the new moments plus what to remember. A first look
/// (nothing remembered yet) announces nothing, so launching the app never replays old news.
enum MomentSources {
    // MARK: Gmail

    static func mail(previous: Set<String>?, now snapshot: GmailSnapshot) -> (moments: [Moment], known: Set<String>) {
        let ids = Set(snapshot.messages.map(\.id))
        guard let previous else { return ([], ids) }
        let fresh = snapshot.messages.filter { !previous.contains($0.id) }.prefix(3)
        let moments = fresh.reversed().map { message in
            Moment(id: "mail-\(message.id)", source: .gmail, mood: .excited, headline: "new mail",
                   detail: "\(message.from) \u{00B7} \(message.subject)", symbol: "envelope.fill", priority: 55,
                   group: "mail", manyHeadline: "%d new mails", panel: "gmail")
        }
        return (moments, previous.union(ids))
    }

    // MARK: Builds

    static func builds(previous: [String: BuildState]?, now snapshot: JenkinsSnapshot) -> (moments: [Moment], known: [String: BuildState]) {
        let states = Dictionary(snapshot.jobs.map { ($0.id, $0.state) }, uniquingKeysWith: { $1 })
        guard let previous else { return ([], states) }
        var moments: [Moment] = []
        for job in snapshot.jobs {
            let before = previous[job.id]
            let number = job.buildNumber.map { "\(job.id)-\($0)" } ?? job.id
            switch (before, job.state) {
            case (.some(let was), .succeeded) where was.isRunning:
                moments.append(Moment(id: "build-ok-\(number)", source: .build, mood: .proud, headline: "build's green",
                                      detail: job.name, symbol: "hammer.fill", priority: 60, panel: "jenkins"))
            case (.some(let was), .failed) where was != .failed, (.some(let was), .unstable) where was != .unstable:
                moments.append(Moment(id: "build-bad-\(number)", source: .build, mood: .sad, headline: "build broke",
                                      detail: job.name, symbol: "hammer.fill", priority: 85, ttl: 6, panel: "jenkins"))
            default: break
            }
        }
        return (moments, states)
    }

    // MARK: GitHub

    struct GitHubMemory: Equatable {
        var reviews: Set<String>
        var checks: [String: CheckState]
    }

    static func github(previous: GitHubMemory?, now snapshot: GitHubSnapshot) -> (moments: [Moment], known: GitHubMemory) {
        let memory = GitHubMemory(reviews: Set(snapshot.reviewRequested.map(\.id)),
                                  checks: Dictionary(snapshot.mine.map { ($0.id, $0.checks) }, uniquingKeysWith: { $1 }))
        guard let previous else { return ([], memory) }
        var moments: [Moment] = []
        for pr in snapshot.reviewRequested where !previous.reviews.contains(pr.id) {
            moments.append(Moment(id: "review-\(pr.id)", source: .github, mood: .alert, headline: "review pls",
                                  detail: "\(pr.shortReference) \u{00B7} \(pr.title)", symbol: "arrow.triangle.pull", priority: 65,
                                  group: "review", manyHeadline: "%d reviews waiting", panel: "github"))
        }
        for pr in snapshot.mine {
            guard let was = previous.checks[pr.id], was == .pending else { continue }
            if pr.checks == .failing {
                moments.append(Moment(id: "checks-bad-\(pr.id)-\(pr.updatedAt.timeIntervalSince1970)", source: .github, mood: .shocked,
                                      headline: "your checks failed", detail: "\(pr.shortReference) \u{00B7} \(pr.title)",
                                      symbol: "arrow.triangle.pull", priority: 80, ttl: 6, panel: "github"))
            } else if pr.checks == .passing {
                moments.append(Moment(id: "checks-ok-\(pr.id)-\(pr.updatedAt.timeIntervalSince1970)", source: .github, mood: .proud,
                                      headline: "checks passed", detail: "\(pr.shortReference) \u{00B7} \(pr.title)",
                                      symbol: "arrow.triangle.pull", priority: 55, panel: "github"))
            }
        }
        return (moments, memory)
    }

    // MARK: Claude

    static func claude(needsYou: [ClaudeSession], announced: inout Set<String>) -> [Moment] {
        var moments: [Moment] = []
        for session in needsYou {
            guard let attention = session.attention else { continue }
            let id = "claude-\(attention)-\(session.id)-\(Int(session.lastActivity.timeIntervalSince1970))"
            guard announced.insert(id).inserted else { continue }
            switch attention {
            case .finished:
                moments.append(Moment(id: id, source: .claude, mood: .happy, headline: "ate that", detail: session.displayName,
                                      symbol: "sparkle", priority: 60, panel: "claude"))
            case .approval:
                moments.append(Moment(id: id, source: .claude, mood: .needsYou, headline: "needs ur ok", detail: session.displayName,
                                      symbol: "sparkle", priority: 85, ttl: 6, panel: "claude"))
            }
        }
        return moments
    }

    // MARK: Calendar

    static func meetings(_ list: [Meeting], now: Date, announced: inout Set<String>) -> [Moment] {
        var moments: [Moment] = []
        for meeting in list where !meeting.isAllDay {
            let away = meeting.start.timeIntervalSince(now)
            if away > 0, away <= 5 * 60, announced.insert("meet5-\(meeting.id)").inserted {
                let minutes = max(1, Int((away / 60).rounded(.up)))
                moments.append(Moment(id: "meet5-\(meeting.id)", source: .calendar, mood: .clockWatching,
                                      headline: "meeting in \(minutes)m", detail: meeting.title, symbol: "calendar", priority: 70, ttl: 7,
                                      actionTitle: meeting.joinURL == nil ? nil : "Join", url: meeting.joinURL, panel: "calendar"))
            } else if away <= 0, away > -60, announced.insert("meet0-\(meeting.id)").inserted {
                moments.append(Moment(id: "meet0-\(meeting.id)", source: .calendar, mood: .clockWatching,
                                      headline: "starts now", detail: meeting.title, symbol: "calendar", priority: 92, ttl: 10,
                                      actionTitle: meeting.joinURL == nil ? nil : "Join", url: meeting.joinURL, panel: "calendar"))
            }
        }
        return moments
    }
}

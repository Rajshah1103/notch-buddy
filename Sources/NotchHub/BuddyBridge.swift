import BuddyKit
import CalendarKit
import Combine
import ClaudeUsage
import Foundation
import GitHubKit
import JenkinsKit

/// Listens to every source and turns what changed into moments for the buddy. It holds the memory each
/// detector needs ("what did I already announce?") and nothing else.
@MainActor
final class BuddyBridge {
    private let center: MomentCenter
    private var subscriptions = Set<AnyCancellable>()
    private var mailKnown: Set<String>?
    private var buildKnown: [String: BuildState]?
    private var githubKnown: MomentSources.GitHubMemory?
    private var claudeAnnounced: Set<String> = []
    private var meetingAnnounced: Set<String> = []
    private var meetings: [Meeting] = []
    private var clock: Timer?

    init(center: MomentCenter, claude: ClaudeModel, gmail: GmailModel, jenkins: JenkinsModel, github: GitHubModel, calendar: CalendarModel) {
        self.center = center

        claude.$needsYou.sink { [weak self] list in
            guard let self else { return }
            self.center.post(MomentSources.claude(needsYou: list, announced: &self.claudeAnnounced))
        }.store(in: &subscriptions)

        gmail.$snapshot.sink { [weak self] snapshot in
            guard let self, let snapshot else { self?.mailKnown = nil; return }
            let result = MomentSources.mail(previous: self.mailKnown, now: snapshot)
            self.mailKnown = result.known
            self.center.post(result.moments)
        }.store(in: &subscriptions)

        jenkins.$snapshot.sink { [weak self] snapshot in
            guard let self, let snapshot else { self?.buildKnown = nil; return }
            let result = MomentSources.builds(previous: self.buildKnown, now: snapshot)
            self.buildKnown = result.known
            self.center.post(result.moments)
        }.store(in: &subscriptions)

        github.$snapshot.sink { [weak self] snapshot in
            guard let self, let snapshot else { self?.githubKnown = nil; return }
            let result = MomentSources.github(previous: self.githubKnown, now: snapshot)
            self.githubKnown = result.known
            self.center.post(result.moments)
        }.store(in: &subscriptions)

        calendar.$state.sink { [weak self] state in
            if case .ready(let list) = state { self?.meetings = list } else { self?.meetings = [] }
            self?.checkMeetings()
        }.store(in: &subscriptions)
        // Meetings approach with the clock, not with a data change: look every 20 seconds.
        clock = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMeetings() }
        }
    }

    private func checkMeetings() {
        center.post(MomentSources.meetings(meetings, now: Date(), announced: &meetingAnnounced))
    }
}

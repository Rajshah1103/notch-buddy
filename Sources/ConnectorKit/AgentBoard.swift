import Foundation

/// Which AI harness sessions are working or waiting for you, from the events their hooks send. Pure: the caller
/// passes the time. A hook can miss its "done" (a crash, a closed terminal), so a session that goes quiet expires.
public struct AgentBoard: Equatable, Sendable {
    public struct Session: Equatable, Sendable {
        public var harness: String
        public var id: String
        public var needsApproval: Bool
        public var project: String?
        public var since: Date
        public var updated: Date
    }

    public private(set) var sessions: [Session] = []

    /// How long a working session may stay silent, and a waiting one, before it is dropped.
    public static let workingExpiry: TimeInterval = 20 * 60
    public static let waitingExpiry: TimeInterval = 60 * 60

    public init() {}

    public var working: [Session] { sessions.filter { !$0.needsApproval } }
    public var waiting: [Session] { sessions.filter(\.needsApproval) }

    /// Applies one event. Returns true if what is on the board changed.
    @discardableResult
    public mutating func apply(_ event: Message.AgentEvent, now: Date) -> Bool {
        let before = sessions
        let index = sessions.firstIndex { $0.harness == event.harness && $0.id == event.session }
        switch event.state {
        case .done, .idle:
            if let index { sessions.remove(at: index) }
        case .working, .needsApproval:
            let waiting = event.state == .needsApproval
            if let index {
                if sessions[index].needsApproval != waiting { sessions[index].since = now }
                sessions[index].needsApproval = waiting
                sessions[index].project = event.project ?? sessions[index].project
                sessions[index].updated = now
            } else {
                sessions.append(Session(harness: event.harness, id: event.session, needsApproval: waiting,
                                        project: event.project, since: now, updated: now))
                if sessions.count > 20 { sessions.removeFirst() }          // a runaway sender cannot grow it
            }
        }
        return sessions != before
    }

    /// Drops sessions that went quiet. Returns true if any were dropped.
    @discardableResult
    public mutating func prune(now: Date) -> Bool {
        let before = sessions.count
        sessions.removeAll { now.timeIntervalSince($0.updated) > ($0.needsApproval ? Self.waitingExpiry : Self.workingExpiry) }
        return sessions.count != before
    }

    /// When the next session would expire, so a timer can be armed for exactly then.
    public var nextExpiry: Date? {
        sessions.map { $0.updated.addingTimeInterval($0.needsApproval ? Self.waitingExpiry : Self.workingExpiry) }.min()
    }
}

import Foundation

public enum BuildState: Hashable, Sendable {
    /// `progress` is 0...1 when Jenkins has a duration estimate for the job, nil otherwise.
    case running(progress: Double?)
    case succeeded
    case failed
    case unstable
    case aborted
    case notBuilt
    case disabled

    public var isRunning: Bool { if case .running = self { return true } else { return false } }
}

public struct JenkinsJob: Identifiable, Hashable, Sendable {
    public var id: String { fullName }
    /// "folder/job" for jobs inside folders.
    public let fullName: String
    public let url: URL
    public let state: BuildState
    public let buildNumber: Int?
    /// When the last build started.
    public let startedAt: Date?
    /// When the last build finished; nil while running or if it never ran.
    public let finishedAt: Date?

    public init(fullName: String, url: URL, state: BuildState, buildNumber: Int?, startedAt: Date?, finishedAt: Date?) {
        self.fullName = fullName
        self.url = url
        self.state = state
        self.buildNumber = buildNumber
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    /// The last path component: "deploy-prod" for "payments/deploy-prod".
    public var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
    /// The folder it lives in, if any: "payments".
    public var folder: String? {
        let parts = fullName.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }
}

public struct JenkinsSnapshot: Equatable, Sendable {
    public var jobs: [JenkinsJob]
    public var fetchedAt: Date

    public init(jobs: [JenkinsJob], fetchedAt: Date) {
        self.jobs = jobs
        self.fetchedAt = fetchedAt
    }

    public static let empty = JenkinsSnapshot(jobs: [], fetchedAt: .distantPast)

    public var running: [JenkinsJob] { jobs.filter { $0.state.isRunning } }
    public var failing: [JenkinsJob] { jobs.filter { $0.state == .failed || $0.state == .unstable } }

    /// What is worth a glance, in order: running, then broken, then recently finished. Everything
    /// else (thousands of idle jobs on a big server) stays out of the way.
    public func relevant(now: Date = Date(), recentWithin: TimeInterval = 24 * 3600) -> [JenkinsJob] {
        let rank: (JenkinsJob) -> Int = {
            switch $0.state {
            case .running: return 0
            case .failed, .unstable: return 1
            default: return 2
            }
        }
        return jobs.filter { job in
            switch job.state {
            case .running, .failed, .unstable: return true
            case .succeeded, .aborted: return (job.finishedAt ?? .distantPast) > now.addingTimeInterval(-recentWithin)
            case .notBuilt, .disabled: return false
            }
        }
        .sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return (a.startedAt ?? .distantPast) > (b.startedAt ?? .distantPast)
        }
    }
}

public struct JenkinsConfig: Equatable, Sendable {
    public var baseURL: URL
    public var username: String
    public var token: String
    /// Only jobs whose full name contains one of these (case-insensitive). Empty means all.
    public var filters: [String]

    public init(baseURL: URL, username: String, token: String, filters: [String] = []) {
        self.baseURL = baseURL
        self.username = username
        self.token = token
        self.filters = filters
    }
}

public enum JenkinsError: Error, Equatable, Sendable {
    case unauthorized
    /// No connection: typically the VPN is not on.
    case unreachable
    case notJenkins
    case failed(String)

    public var message: String {
        switch self {
        case .unauthorized: return "Jenkins rejected the username or token"
        case .unreachable: return "Can't reach Jenkins. Is your VPN connected?"
        case .notJenkins: return "That address doesn't look like Jenkins"
        case .failed(let reason): return reason
        }
    }
}

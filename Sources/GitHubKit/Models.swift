import Foundation

public enum CheckState: Equatable, Sendable {
    case passing, pending, failing
    /// No checks configured, or none reported yet.
    case none
}

public struct PullRequest: Identifiable, Hashable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    public let url: URL
    /// "owner/name"
    public let repository: String
    public let author: String
    public let isDraft: Bool
    public let reviewDecision: String?      // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED
    public let checks: CheckState
    public let updatedAt: Date

    public init(id: String, number: Int, title: String, url: URL, repository: String, author: String,
                isDraft: Bool, reviewDecision: String?, checks: CheckState, updatedAt: Date) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.author = author
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.updatedAt = updatedAt
    }

    /// "repo #123": the repository name without its owner.
    public var shortReference: String { "\(repository.split(separator: "/").last.map(String.init) ?? repository) #\(number)" }
}

public struct GitHubSnapshot: Equatable, Sendable {
    public var login: String
    /// Open pull requests waiting for your review.
    public var reviewRequested: [PullRequest]
    /// Your own open pull requests.
    public var mine: [PullRequest]
    public var fetchedAt: Date

    public init(login: String, reviewRequested: [PullRequest], mine: [PullRequest], fetchedAt: Date) {
        self.login = login
        self.reviewRequested = reviewRequested
        self.mine = mine
        self.fetchedAt = fetchedAt
    }

    public static let empty = GitHubSnapshot(login: "", reviewRequested: [], mine: [], fetchedAt: .distantPast)

    /// Your pull requests whose checks are still running.
    public var runningChecks: Int { mine.filter { $0.checks == .pending }.count }
    public var failingChecks: Int { mine.filter { $0.checks == .failing }.count }
}

public enum GitHubError: Error, Equatable, Sendable {
    case noToken
    case unauthorized
    case rateLimited
    case offline
    case failed(String)

    public var message: String {
        switch self {
        case .noToken: return "Not connected"
        case .unauthorized: return "GitHub rejected the token"
        case .rateLimited: return "GitHub rate limit reached; trying again soon"
        case .offline: return "Can't reach GitHub"
        case .failed(let reason): return reason
        }
    }
}

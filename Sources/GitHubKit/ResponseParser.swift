import Foundation

/// Turns GitHub's GraphQL response into a snapshot. Pure, so it can be tested with fixtures.
public enum ResponseParser {
    public static let query = """
    query {
      viewer {
        login
        pullRequests(states: OPEN, first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { ...pr } }
      }
      reviews: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 20) {
        nodes { ... on PullRequest { ...pr } }
      }
    }
    fragment pr on PullRequest {
      id number title url isDraft reviewDecision updatedAt
      repository { nameWithOwner }
      author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    public static func parse(_ data: Data, now: Date = Date()) throws -> GitHubSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubError.failed("Unexpected response")
        }
        if let errors = root["errors"] as? [[String: Any]], root["data"] == nil {
            let type = errors.first?["type"] as? String
            if type == "RATE_LIMITED" { throw GitHubError.rateLimited }
            throw GitHubError.failed(errors.first?["message"] as? String ?? "GitHub returned an error")
        }
        guard let payload = root["data"] as? [String: Any],
              let viewer = payload["viewer"] as? [String: Any],
              let login = viewer["login"] as? String
        else { throw GitHubError.failed("Unexpected response") }

        let mine = ((viewer["pullRequests"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap(pullRequest)
        let reviews = ((payload["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap(pullRequest)
        return GitHubSnapshot(login: login, reviewRequested: reviews, mine: mine, fetchedAt: now)
    }

    static func pullRequest(_ node: [String: Any]) -> PullRequest? {
        guard let id = node["id"] as? String, let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = (node["url"] as? String).flatMap(URL.init(string:)),
              let repository = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
        else { return nil }

        let rollup = (((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any]
        return PullRequest(
            id: id, number: number, title: title, url: url, repository: repository,
            author: (node["author"] as? [String: Any])?["login"] as? String ?? "ghost",
            isDraft: node["isDraft"] as? Bool ?? false,
            reviewDecision: node["reviewDecision"] as? String,
            checks: checkState(rollup?["state"] as? String),
            updatedAt: (node["updatedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast)
    }

    static func checkState(_ rollup: String?) -> CheckState {
        switch rollup {
        case "SUCCESS": return .passing
        case "PENDING", "EXPECTED": return .pending
        case "FAILURE", "ERROR": return .failing
        default: return .none
        }
    }
}

import Foundation
import Testing
@testable import GitHubKit

struct ResponseParserTests {
    private func response(_ nodes: String, reviews: String = "[]") -> Data {
        Data("""
        {"data":{"viewer":{"login":"raj","pullRequests":{"nodes":\(nodes)}},"reviews":{"nodes":\(reviews)}}}
        """.utf8)
    }

    private func node(_ number: Int, state: String?, draft: Bool = false) -> String {
        let rollup = state.map { "{\"state\":\"\($0)\"}" } ?? "null"
        return """
        {"id":"PR_\(number)","number":\(number),"title":"Fix \(number)","url":"https://github.com/acme/api/pull/\(number)",
         "isDraft":\(draft),"reviewDecision":"REVIEW_REQUIRED","updatedAt":"2026-10-23T10:00:00Z",
         "repository":{"nameWithOwner":"acme/api"},"author":{"login":"raj"},
         "commits":{"nodes":[{"commit":{"statusCheckRollup":\(rollup)}}]}}
        """
    }

    @Test func mapsCheckStates() throws {
        let data = response("[\(node(1, state: "SUCCESS")),\(node(2, state: "PENDING")),\(node(3, state: "FAILURE")),\(node(4, state: nil))]")
        let snapshot = try ResponseParser.parse(data)
        #expect(snapshot.mine.map(\.checks) == [.passing, .pending, .failing, .none])
        #expect(snapshot.runningChecks == 1)
        #expect(snapshot.failingChecks == 1)
    }

    @Test func readsReviewRequestsSeparately() throws {
        let snapshot = try ResponseParser.parse(response("[\(node(1, state: "SUCCESS"))]", reviews: "[\(node(9, state: "PENDING"))]"))
        #expect(snapshot.login == "raj")
        #expect(snapshot.mine.map(\.number) == [1])
        #expect(snapshot.reviewRequested.map(\.number) == [9])
        #expect(snapshot.reviewRequested[0].shortReference == "api #9")
    }

    @Test func skipsSearchHitsThatAreNotPullRequests() throws {
        // A search can return an issue, which comes back as an empty object for the PullRequest fragment.
        let snapshot = try ResponseParser.parse(response("[]", reviews: "[{},\(node(5, state: "SUCCESS"))]"))
        #expect(snapshot.reviewRequested.map(\.number) == [5])
    }

    @Test func reportsRateLimitingAndOtherErrors() {
        let limited = Data(#"{"errors":[{"type":"RATE_LIMITED","message":"slow down"}]}"#.utf8)
        #expect(throws: GitHubError.rateLimited) { try ResponseParser.parse(limited) }
        let other = Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8)
        #expect(throws: GitHubError.failed("Bad credentials")) { try ResponseParser.parse(other) }
    }
}

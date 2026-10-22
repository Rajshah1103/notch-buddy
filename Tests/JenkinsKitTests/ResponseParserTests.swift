import Foundation
import Testing
@testable import JenkinsKit

struct ResponseParserTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var ms: Double { now.timeIntervalSince1970 * 1000 }

    private func job(_ name: String, color: String, build: String? = nil, folder: Bool = false, children: String = "[]") -> String {
        if folder { return #"{"name":"\#(name)","fullName":"\#(name)","url":"https://ci.acme.dev/job/\#(name)/","jobs":\#(children)}"# }
        return #"{"name":"\#(name)","fullName":"\#(name)","url":"https://ci.acme.dev/job/\#(name)/","color":"\#(color)","lastBuild":\#(build ?? "null")}"#
    }

    private func response(_ jobs: String...) -> Data { Data(#"{"jobs":[\#(jobs.joined(separator: ","))]}"#.utf8) }

    private func build(_ number: Int, building: Bool = false, result: String? = "SUCCESS", startedAgo: Double = 600,
                       duration: Double = 120_000, estimate: Double = 120_000) -> String {
        let r = result.map { "\"\($0)\"" } ?? "null"
        return #"{"number":\#(number),"building":\#(building),"result":\#(r),"timestamp":\#(ms - startedAgo * 1000),"estimatedDuration":\#(estimate),"duration":\#(duration),"url":"https://ci.acme.dev/job/x/\#(number)/"}"#
    }

    @Test func mapsResultsToStates() throws {
        let data = response(
            job("ok", color: "blue", build: build(1, result: "SUCCESS")),
            job("bad", color: "red", build: build(2, result: "FAILURE")),
            job("flaky", color: "yellow", build: build(3, result: "UNSTABLE")),
            job("stopped", color: "aborted", build: build(4, result: "ABORTED")),
            job("off", color: "disabled"),
            job("fresh", color: "notbuilt"))
        let states = try ResponseParser.parse(data, now: now).jobs.map(\.state)
        #expect(states == [.succeeded, .failed, .unstable, .aborted, .disabled, .notBuilt])
    }

    @Test func runningBuildsReportProgressFromTheEstimate() throws {
        // Started 60 s ago, expected to take 120 s: half way.
        let data = response(job("deploy", color: "blue_anime", build: build(7, building: true, result: nil, startedAgo: 60, estimate: 120_000)))
        let job = try #require(try ResponseParser.parse(data, now: now).jobs.first)
        guard case .running(let progress) = job.state else { Issue.record("should be running"); return }
        #expect(abs((progress ?? 0) - 0.5) < 0.01)
        #expect(job.finishedAt == nil)
    }

    @Test func progressNeverReachesOneBeforeTheBuildEnds() throws {
        // Running longer than estimated: show nearly done, not 150%.
        let data = response(job("slow", color: "blue_anime", build: build(7, building: true, result: nil, startedAgo: 600, estimate: 120_000)))
        guard case .running(let progress)? = try ResponseParser.parse(data, now: now).jobs.first?.state else { Issue.record("running"); return }
        #expect((progress ?? 0) <= 0.99)
    }

    @Test func noEstimateMeansNoProgressNumber() throws {
        let data = response(job("new", color: "blue_anime", build: build(1, building: true, result: nil, estimate: 0)))
        #expect(try ResponseParser.parse(data, now: now).jobs.first?.state == .running(progress: nil))
    }

    @Test func foldersAreFlattenedAndKeepTheirPath() throws {
        let inner = #"{"name":"deploy","fullName":"payments/deploy","url":"https://ci.acme.dev/job/payments/job/deploy/","color":"blue","lastBuild":\#(build(1))}"#
        let data = response(job("payments", color: "", folder: true, children: "[\(inner)]"))
        let parsed = try ResponseParser.parse(data, now: now).jobs
        #expect(parsed.count == 1)
        #expect(parsed[0].fullName == "payments/deploy")
        #expect(parsed[0].name == "deploy")
        #expect(parsed[0].folder == "payments")
    }

    @Test func filtersMatchAnyNeedleCaseInsensitively() throws {
        let data = response(job("Deploy-Prod", color: "blue", build: build(1)), job("lint", color: "blue", build: build(2)),
                            job("payments-api", color: "blue", build: build(3)))
        let jobs = try ResponseParser.parse(data, filters: ["deploy", " PAYMENTS "], now: now).jobs.map(\.name)
        #expect(jobs == ["Deploy-Prod", "payments-api"])
    }

    @Test func rejectsPagesThatAreNotJenkins() {
        #expect(throws: JenkinsError.notJenkins) { try ResponseParser.parse(Data("<html>login</html>".utf8)) }
        #expect(throws: JenkinsError.notJenkins) { try ResponseParser.parse(Data(#"{"hello":"world"}"#.utf8)) }
    }

    @Test func relevantShowsRunningThenBrokenThenRecentOnly() throws {
        let data = response(
            job("old-ok", color: "blue", build: build(1, startedAgo: 3 * 86_400)),
            job("recent-ok", color: "blue", build: build(2, startedAgo: 3_600)),
            job("broken", color: "red", build: build(3, result: "FAILURE", startedAgo: 5 * 86_400)),
            job("running", color: "blue_anime", build: build(4, building: true, result: nil, startedAgo: 30)),
            job("off", color: "disabled"))
        let relevant = try ResponseParser.parse(data, now: now).relevant(now: now).map(\.name)
        #expect(relevant == ["running", "broken", "recent-ok"])    // old success and disabled job stay out
    }
}

import Foundation

/// Turns Jenkins' JSON API response into jobs. Pure, so it is tested with fixtures.
public enum ResponseParser {
    /// Two folder levels deep, only the fields we use (the `tree` parameter keeps big servers fast).
    public static let treeQuery: String = {
        let build = "lastBuild[number,building,result,timestamp,estimatedDuration,duration,url]"
        let leaf = "name,fullName,url,color,\(build)"
        return "jobs[\(leaf),jobs[\(leaf),jobs[\(leaf)]]]"
    }()

    public static func parse(_ data: Data, filters: [String] = [], now: Date = Date()) throws -> JenkinsSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = root["jobs"] as? [[String: Any]]
        else { throw JenkinsError.notJenkins }

        let needles = filters.map { $0.lowercased() }.filter { !$0.isEmpty }
        let parsed = flatten(jobs, now: now).filter { job in
            needles.isEmpty || needles.contains { job.fullName.lowercased().contains($0) }
        }
        return JenkinsSnapshot(jobs: parsed, fetchedAt: now)
    }

    /// Walks folders; a folder is anything with children, a job is anything with a name and a color.
    private static func flatten(_ nodes: [[String: Any]], now: Date) -> [JenkinsJob] {
        nodes.flatMap { node -> [JenkinsJob] in
            if let children = node["jobs"] as? [[String: Any]] { return flatten(children, now: now) }
            return job(node, now: now).map { [$0] } ?? []
        }
    }

    static func job(_ node: [String: Any], now: Date) -> JenkinsJob? {
        guard let name = node["name"] as? String,
              let url = (node["url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        let fullName = node["fullName"] as? String ?? name
        let build = node["lastBuild"] as? [String: Any]
        let color = node["color"] as? String ?? ""

        let started = (build?["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        let duration = build?["duration"] as? Double ?? 0
        let building = build?["building"] as? Bool ?? color.hasSuffix("_anime")

        let state: BuildState
        if color == "disabled" {
            state = .disabled
        } else if building, let started {
            let estimate = build?["estimatedDuration"] as? Double ?? 0
            state = .running(progress: estimate > 0 ? min(0.99, max(0, now.timeIntervalSince(started) * 1000 / estimate)) : nil)
        } else {
            switch build?["result"] as? String {
            case "SUCCESS": state = .succeeded
            case "FAILURE": state = .failed
            case "UNSTABLE": state = .unstable
            case "ABORTED": state = .aborted
            default: state = build == nil ? .notBuilt : .notBuilt
            }
        }

        let finished = (building || started == nil) ? nil : started.map { $0.addingTimeInterval(duration / 1000) }
        return JenkinsJob(fullName: fullName, url: url, state: state, buildNumber: build?["number"] as? Int,
                          startedAt: started, finishedAt: finished)
    }
}

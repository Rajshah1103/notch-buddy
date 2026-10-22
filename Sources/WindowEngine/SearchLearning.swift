import Foundation

/// What search has learned from what you open. Everything is stored on this Mac and used only to nudge
/// the order of results: things you open often and recently rise, and so does whatever you picked the last
/// times you typed the same thing.
public struct SearchLearning: Codable, Equatable, Sendable {
    struct Stat: Codable, Equatable, Sendable {
        var opens: Int
        var last: Date
    }

    private var stats: [String: Stat] = [:]
    /// For each thing you typed, how often each result was chosen.
    private var byQuery: [String: [String: Int]] = [:]

    public init() {}

    private let maxKeys = 600

    /// A key that stays the same when a window id or a page title changes: a site for tabs, the app and
    /// its window title otherwise.
    public static func key(for entry: Entry, appName: String) -> String {
        entry.host.isEmpty ? "\(appName)|\(entry.title)" : "tab|\(entry.host)"
    }

    private static func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Remember that `key` was opened, optionally after typing `query`.
    public mutating func record(key: String, query: String = "", at date: Date = Date()) {
        var stat = stats[key] ?? Stat(opens: 0, last: date)
        stat.opens += 1
        stat.last = date
        stats[key] = stat

        let typed = Self.normalize(query)
        if typed.count >= 2 { byQuery[typed, default: [:]][key, default: 0] += 1 }
        prune(now: date)
    }

    /// Extra score for a result: frequency and recency of opening it, plus a larger lift if you chose it
    /// before after typing something that matches what is typed now.
    public func boost(key: String, query: String, now: Date = Date()) -> Double {
        var total = 0.0
        if let stat = stats[key] {
            let days = max(0, now.timeIntervalSince(stat.last) / 86_400)
            let frequency = min(18, log2(1 + Double(stat.opens)) * 5)
            total += frequency * exp(-days / 21)        // fades over a few weeks of not using it
        }
        let typed = Self.normalize(query)
        if typed.count >= 2 {
            var picks = 0
            for (earlier, results) in byQuery where earlier.hasPrefix(typed) || typed.hasPrefix(earlier) {
                picks += results[key] ?? 0
            }
            total += 35 * Double(min(picks, 3))
        }
        return total
    }

    public var isEmpty: Bool { stats.isEmpty && byQuery.isEmpty }

    /// Keeps the file small: drop what has not been opened for months, then the least used.
    private mutating func prune(now: Date) {
        guard stats.count > maxKeys else { return }
        let cutoff = now.addingTimeInterval(-120 * 86_400)
        stats = stats.filter { $0.value.last > cutoff }
        if stats.count > maxKeys {
            let keep = Set(stats.sorted { $0.value.opens > $1.value.opens }.prefix(maxKeys).map(\.key))
            stats = stats.filter { keep.contains($0.key) }
        }
        byQuery = byQuery.mapValues { $0.filter { stats[$0.key] != nil } }.filter { !$0.value.isEmpty }
    }
}

import Foundation

/// One result: a window, tab or app, with the app it belongs to.
public struct SearchResult: Identifiable, Hashable {
    public var id: String { entry.id }
    public let entry: Entry
    public let appName: String
    public let appPID: Int32
}

public extension Entry {
    /// Same entry with a different subtitle (search shows "App · site" so results say where they live).
    func withSubtitle(_ subtitle: String) -> Entry {
        Entry(id: id, title: title, subtitle: subtitle, detail: detail, url: url, place: place, section: nil,
              isActive: isActive, thumbnailWindowID: thumbnailWindowID, target: target)
    }
}

/// Typing finds anything open: every term must match, and matches at the start of the title or of
/// a word rank above matches buried in the middle.
public enum Search {
    /// `boost` adds to a result's score (used to rank what you open often higher); it defaults to nothing.
    public static func results(for query: String, in groups: [AppGroup], limit: Int = .max,
                               boost: (Entry, String) -> Double = { _, _ in 0 }) -> [SearchResult] {
        let terms = fold(query).split(separator: " ").map(String.init)

        var scored: [(result: SearchResult, score: Double, order: Int)] = []
        var order = 0
        for group in groups {
            for entry in group.entries {
                defer { order += 1 }
                let result = SearchResult(entry: entry, appName: group.name, appPID: group.pid)
                let learned = boost(entry, group.name)
                if terms.isEmpty {
                    // Nothing typed: what you open often first, then recency order.
                    scored.append((result, (entry.isActive ? 1 : 0) + learned, order))
                    continue
                }
                if let score = score(terms, entry: entry, appName: group.name) { scored.append((result, score + learned, order)) }
            }
        }
        // Higher score first; ties keep recency order (apps are already most-recent-first).
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        return scored.prefix(limit).map(\.result)
    }

    private static func score(_ terms: [String], entry: Entry, appName: String) -> Double? {
        // Only the title tolerates typos (subsequence); other fields must match for real.
        let fields: [(text: String, weight: Double, fuzzy: Bool)] = [
            (fold(entry.title), 3, true), (fold(entry.subtitle), 2, false), (fold(appName), 1.5, false), (fold(entry.url), 1, false),
        ]
        var total = 0.0
        for term in terms {
            // Every term has to match somewhere; its best field counts.
            guard let best = fields.compactMap({ field in matchScore(term, in: field.text, fuzzy: field.fuzzy).map { $0 * field.weight } }).max()
            else { return nil }
            total += best
        }
        return total + (entry.isActive ? 5 : 0)
    }

    private static func matchScore(_ term: String, in text: String, fuzzy: Bool) -> Double? {
        guard !text.isEmpty else { return nil }
        if text.hasPrefix(term) { return 100 }
        if text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(term) }) { return 60 }
        if text.contains(term) { return 30 }
        return fuzzy && isSubsequence(term, of: text) ? 8 : nil   // "grfn" finds "grafana"
    }

    private static func isSubsequence(_ term: String, of text: String) -> Bool {
        guard term.count >= 4 else { return false }   // shorter terms match far too much by chance
        var index = text.startIndex
        for ch in term {
            guard let found = text[index...].firstIndex(of: ch) else { return false }
            index = text.index(after: found)
        }
        return true
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}

import Foundation

/// Where a moment comes from. Open on purpose: the built-in sources are constants, and a connector or a
/// script brings its own id (`MomentSource("gitlab")`).
public struct MomentSource: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ id: String) { self.rawValue = id }

    public static let claude = MomentSource("claude")
    public static let gmail = MomentSource("gmail")
    public static let build = MomentSource("build")
    public static let github = MomentSource("github")
    public static let calendar = MomentSource("calendar")
    public static let slack = MomentSource("slack")
}

/// Something worth announcing: a short-lived event the buddy reacts to and a bubble describes.
public struct Moment: Equatable, Identifiable, Sendable {
    /// Identifies the event. The same id is never announced twice in a short while.
    public let id: String
    public let source: MomentSource
    public let mood: Mood
    public var headline: String
    public var detail: String?
    /// SF Symbol for the source.
    public let symbol: String
    /// Bigger is more important. 90 and up skips the pacing rule.
    public let priority: Int
    /// How long the bubble stays up, unless the pointer is on it.
    public let ttl: TimeInterval
    /// Events of one kind arriving together merge: "new mail" becomes "3 new mails".
    public let group: String?
    public var count: Int
    /// Headline when merged, with `%d` for the count.
    public let manyHeadline: String?
    public let actionTitle: String?
    public let url: URL?
    /// The integration panel a click opens (its id), when the event belongs to one.
    public let panel: String?
    /// A colour of its own as `#RRGGBB`, for sources the app does not know.
    public let tintHex: String?

    public init(id: String, source: MomentSource, mood: Mood, headline: String, detail: String? = nil, symbol: String,
                priority: Int = 50, ttl: TimeInterval = 4.5, group: String? = nil, count: Int = 1,
                manyHeadline: String? = nil, actionTitle: String? = nil, url: URL? = nil, panel: String? = nil, tintHex: String? = nil) {
        self.id = id; self.source = source; self.mood = mood; self.headline = headline; self.detail = detail
        self.symbol = symbol; self.priority = priority; self.ttl = ttl; self.group = group; self.count = count
        self.manyHeadline = manyHeadline; self.actionTitle = actionTitle; self.url = url; self.panel = panel; self.tintHex = tintHex
    }
}

/// Decides what the bubble shows and when. Pure (the caller passes the time), so the rules are testable:
/// one bubble at a time, a pause between bubbles, bursts merged, repeats ignored, and the queue kept short.
public struct MomentQueue {
    public private(set) var showing: Moment?
    public private(set) var pending: [Moment] = []

    private var shownAt: Date?
    private var lastStart: Date = .distantPast
    private var recent: [String: Date] = [:]

    public let minGap: TimeInterval
    public let capacity: Int
    public let repeatWindow: TimeInterval

    public init(minGap: TimeInterval = 8, capacity: Int = 3, repeatWindow: TimeInterval = 120) {
        self.minGap = minGap; self.capacity = capacity; self.repeatWindow = repeatWindow
    }

    /// Adds an event. Returns true if anything about what is shown or queued changed.
    @discardableResult
    public mutating func add(_ moment: Moment, now: Date) -> Bool {
        recent = recent.filter { now.timeIntervalSince($0.value) < repeatWindow }
        if recent[moment.id] != nil { return false }                    // already announced lately
        if pending.contains(where: { $0.id == moment.id }) { return false }

        // Merge with a waiting event of the same kind.
        if let group = moment.group, let index = pending.firstIndex(where: { $0.group == group }) {
            pending[index] = merged(pending[index], with: moment)
            return true
        }
        pending.append(moment)
        pending.sort { $0.priority > $1.priority }                      // stable for equal priority
        if pending.count > capacity { pending.removeLast() }
        return true
    }

    private func merged(_ a: Moment, with b: Moment) -> Moment {
        var result = b.priority > a.priority ? b : a
        result.count = a.count + b.count
        if let many = a.manyHeadline ?? b.manyHeadline { result.headline = many.replacingOccurrences(of: "%d", with: "\(result.count)") }
        result.detail = b.detail ?? a.detail
        return result
    }

    /// Moves time forward: ends an expired bubble and starts the next one when the pause allows.
    /// `held` is true while the pointer is on the bubble. Returns true if what is showing changed.
    @discardableResult
    public mutating func advance(now: Date, held: Bool = false) -> Bool {
        var changed = false
        if let current = showing, let start = shownAt, !held, now.timeIntervalSince(start) >= current.ttl {
            showing = nil; shownAt = nil; changed = true
        }
        if showing == nil, let next = pending.first {
            let urgent = next.priority >= 90
            if urgent || now.timeIntervalSince(lastStart) >= minGap {
                pending.removeFirst()
                showing = next; shownAt = now; lastStart = now
                recent[next.id] = now
                changed = true
            }
        }
        return changed
    }

    /// The next time `advance` could change something, so a caller can sleep until then.
    public func nextWake(now: Date) -> Date? {
        var times: [Date] = []
        if let current = showing, let start = shownAt { times.append(start.addingTimeInterval(current.ttl)) }
        if showing == nil, !pending.isEmpty { times.append(lastStart.addingTimeInterval(minGap)) }
        return times.filter { $0 > now }.min()
    }

    /// Ends the bubble now (a click, or the user dismissing it).
    public mutating func dismiss() { showing = nil; shownAt = nil }
}

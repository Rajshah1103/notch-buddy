import Foundation

/// One line of JSON sent to Notch Hub by a script, a harness hook or `notchhub emit`.
public enum Message: Equatable, Sendable {
    case moment(Incoming)
    case agent(AgentEvent)

    /// A bubble request. Everything but `source` and `headline` is optional.
    public struct Incoming: Equatable, Sendable {
        public var source: String
        public var headline: String
        public var detail: String?
        public var mood: String?
        public var symbol: String?
        public var url: String?
        public var tint: String?
        public var ttl: Double?
        public var priority: Int?
        public var group: String?
        public var id: String?
    }

    /// What an AI harness is doing, as reported by its own hooks.
    public struct AgentEvent: Equatable, Sendable {
        public enum State: String, Sendable { case working, needsApproval = "needs-approval", done, idle }
        public var harness: String
        public var session: String
        public var state: State
        public var project: String?
    }

    public enum ParseError: Error, Equatable { case tooLong, notJSON, unknownType(String), missing(String) }

    /// Longest accepted line; anything bigger is dropped instead of buffered.
    public static let maxLine = 16 * 1024

    public static func parse(_ line: Data) throws -> Message {
        guard line.count <= maxLine else { throw ParseError.tooLong }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw ParseError.notJSON }
        func string(_ key: String) -> String? { (object[key] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
        switch object["type"] as? String ?? "moment" {
        case "moment":
            guard let source = string("source") else { throw ParseError.missing("source") }
            guard let headline = string("headline") else { throw ParseError.missing("headline") }
            return .moment(Incoming(source: String(source.prefix(40)), headline: String(headline.prefix(120)),
                                    detail: string("detail").map { String($0.prefix(200)) }, mood: string("mood"),
                                    symbol: string("symbol"), url: string("url"), tint: string("tint"),
                                    ttl: object["ttl"] as? Double, priority: object["priority"] as? Int,
                                    group: string("group"), id: string("id")))
        case "agent":
            guard let harness = string("harness") else { throw ParseError.missing("harness") }
            guard let session = string("session") else { throw ParseError.missing("session") }
            guard let state = string("state").flatMap(AgentEvent.State.init(rawValue:)) else { throw ParseError.missing("state") }
            return .agent(AgentEvent(harness: String(harness.prefix(40)), session: String(session.prefix(80)), state: state, project: string("project")))
        case let other:
            throw ParseError.unknownType(other)
        }
    }
}

/// Splits a byte stream into lines, never holding more than `Message.maxLine` of an unfinished one.
public struct LineBuffer {
    private var pending = Data()
    private var skipping = false
    public init() {}

    /// Feeds bytes; returns the complete lines. An over-long line is dropped as a whole.
    public mutating func feed(_ data: Data) -> [Data] {
        var lines: [Data] = []
        for byte in data {
            if byte == 0x0A {
                if !skipping, !pending.isEmpty { lines.append(pending) }
                pending.removeAll(keepingCapacity: true); skipping = false
            } else if !skipping {
                pending.append(byte)
                if pending.count > Message.maxLine { pending.removeAll(); skipping = true }
            }
        }
        return lines
    }
}

/// At most `limit` events per `window` seconds; the rest are dropped. Pure: the caller passes the time.
public struct RateLimit {
    public let limit: Int
    public let window: Double
    private var stamps: [Double] = []
    public init(limit: Int = 20, window: Double = 10) { self.limit = limit; self.window = window }

    public mutating func allow(now: Double) -> Bool {
        stamps.removeAll { now - $0 >= window }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }
}

import Foundation

/// What one transcript line contributes. Transcript lines are JSON objects; only assistant
/// messages with usage matter.
public struct TranscriptLine: Equatable {
    public var cwd: String?                 // set by the store from the transcript head, not per line
    public var sessionID: String?
    public var timestamp: Date?
    /// For assistant messages: the message id and what it consumed.
    public var messageID: String?
    public var inputTokens = 0       // fresh input, including tokens written to the cache
    public var outputTokens = 0
}

/// Reads four numbers out of lines that can be megabytes long. It scans bytes in place instead of
/// parsing JSON: parsing every message of a day's transcripts allocated hundreds of megabytes.
public enum TranscriptParser {
    public static func parse(_ line: Data) -> TranscriptLine? {
        line.withUnsafeBytes { parse($0) }
    }

    static func parse(_ line: UnsafeRawBufferPointer) -> TranscriptLine? {
        guard find("\"role\":\"assistant\"", in: line) != nil,
              let usageAt = find("\"usage\":{", in: line)
        else { return nil }

        // The message's own id is the first "id" after the start of the message object.
        guard let messageAt = find("\"message\":{", in: line),
              let id = string(after: "\"id\":\"", in: line, from: messageAt)
        else { return nil }

        // Usage numbers sit within a few hundred bytes of the start of the usage object.
        let window = UnsafeRawBufferPointer(rebasing: line[usageAt..<min(line.count, usageAt + 600)])
        var result = TranscriptLine()
        result.messageID = id
        result.inputTokens = (integer(after: "\"input_tokens\":", in: window) ?? 0)
            + (integer(after: "\"cache_creation_input_tokens\":", in: window) ?? 0)   // cache reads are free re-reads
        result.outputTokens = integer(after: "\"output_tokens\":", in: window) ?? 0
        if let stamp = string(after: "\"timestamp\":\"", in: line, from: 0) { result.timestamp = parseDate(stamp) }
        return result
    }

    // MARK: - Byte scanning

    private static func find(_ needle: String, in haystack: UnsafeRawBufferPointer, from start: Int = 0) -> Int? {
        guard let base = haystack.baseAddress, start < haystack.count else { return nil }
        return needle.withCString { pattern in
            guard let hit = memmem(base + start, haystack.count - start, pattern, strlen(pattern)) else { return nil }
            return base.distance(to: hit)
        }
    }

    private static func integer(after key: String, in bytes: UnsafeRawBufferPointer) -> Int? {
        guard let at = find(key, in: bytes) else { return nil }
        var value = 0
        var index = at + key.utf8.count
        var sawDigit = false
        while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
            value = value * 10 + Int(bytes[index] - 0x30)
            index += 1
            sawDigit = true
        }
        return sawDigit ? value : nil
    }

    private static func string(after key: String, in bytes: UnsafeRawBufferPointer, from start: Int) -> String? {
        guard let at = find(key, in: bytes, from: start) else { return nil }
        let begin = at + key.utf8.count
        guard let end = (begin..<bytes.count).first(where: { bytes[$0] == 0x22 }) else { return nil }   // closing quote
        return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[begin..<end]), as: UTF8.self)
    }

    // MARK: - Dates

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    private static func parseDate(_ text: String) -> Date? {
        withFraction.date(from: text) ?? plain.date(from: text)
    }
}

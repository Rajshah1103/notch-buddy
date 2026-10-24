import Foundation

/// Transcripts are append-only and chronological, and can be hundreds of megabytes. To total up
/// today's usage we find where today begins with a binary search instead of reading everything.
public enum TranscriptSeeker {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let key = Data("\"timestamp\":\"".utf8)

    /// A byte offset, aligned to a line start, at or shortly before the first line stamped at or after
    /// `cutoff`. Lines before it may still be read (they are filtered by timestamp later); no wanted
    /// line is skipped.
    public static func offset(of cutoff: Date, in handle: FileHandle, size: UInt64, granularity: UInt64 = 64 * 1024) -> UInt64 {
        var lo: UInt64 = 0
        var hi = size
        while hi - lo > granularity {
            let mid = lo + (hi - lo) / 2
            if let probe = firstTimestamp(after: mid, in: handle, limit: hi) {
                if probe.date < cutoff { lo = probe.position } else { hi = mid }
            } else {
                hi = mid   // nothing usable between here and the end of the range
            }
        }
        return lo == 0 ? 0 : alignedToLineStart(lo, in: handle)
    }

    /// The first timestamp at or after `position`, however long the lines in between are. Transcript
    /// lines can be megabytes (tool output, images), so this scans forward in chunks instead of
    /// assuming a whole line fits in one read.
    static func firstTimestamp(after position: UInt64, in handle: FileHandle, limit: UInt64) -> (position: UInt64, date: Date)? {
        let chunkSize = 1 << 20
        let overlap = key.count + 40        // a key or its value may straddle two chunks
        var cursor = position
        while cursor < limit {
            guard (try? handle.seek(toOffset: cursor)) != nil,
                  let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty
            else { return nil }
            if let found = chunk.range(of: key) {
                let start = found.upperBound
                if let end = chunk[start...].firstIndex(of: 0x22),
                   let text = String(data: chunk[start..<end], encoding: .utf8), let date = formatter.date(from: text) {
                    return (cursor + UInt64(found.lowerBound), date)
                }
            }
            if chunk.count < chunkSize { return nil }
            cursor += UInt64(chunk.count - overlap)
        }
        return nil
    }

    /// The start of the first full line at or after `position` (skips the partial line we landed in).
    private static func alignedToLineStart(_ position: UInt64, in handle: FileHandle) -> UInt64 {
        var cursor = position
        while true {
            guard (try? handle.seek(toOffset: cursor)) != nil,
                  let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty
            else { return position }
            if let newline = chunk.firstIndex(of: 0x0A) { return cursor + UInt64(newline) + 1 }
            cursor += UInt64(chunk.count)
        }
    }

    /// The working folder of a session, from the start of its transcript (no JSON parsing).
    public static func folder(inHeadOf handle: FileHandle) -> String? {
        guard (try? handle.seek(toOffset: 0)) != nil,
              let head = try? handle.read(upToCount: 256 * 1024),
              let found = head.range(of: Data("\"cwd\":\"".utf8))
        else { return nil }
        let start = found.upperBound
        guard let end = head[start...].firstIndex(of: 0x22) else { return nil }
        return String(data: head[start..<end], encoding: .utf8)
    }

    /// The chat's name from the end of its transcript: a `/rename` (agentName) beats the title Claude
    /// Code generated (aiTitle). Both are re-written every turn, so the last one in the tail is current.
    public static func title(inTailOf handle: FileHandle, size: UInt64, tail: UInt64 = 1 << 20) -> String? {
        let start = size > tail ? size - tail : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.read(upToCount: Int(tail)) else { return nil }
        return lastValue(of: "agentName", in: data) ?? lastValue(of: "aiTitle", in: data)
    }

    /// The last `"key":"value"` in `data`, unescaped. Escaped copies inside message text do not match.
    static func lastValue(of key: String, in data: Data) -> String? {
        let needle = Data("\"\(key)\":\"".utf8)
        var searchEnd = data.endIndex
        while let hit = data.range(of: needle, options: .backwards, in: data.startIndex..<searchEnd) {
            let begin = hit.upperBound
            var i = begin
            while i < data.endIndex, data[i] != 0x22 { i += data[i] == 0x5C ? 2 : 1 }   // skip \" and \\
            if i < data.endIndex,
               let text = try? JSONSerialization.jsonObject(with: Data([0x22]) + data[begin..<i] + Data([0x22]),
                                                            options: .fragmentsAllowed) as? String,
               !text.isEmpty {
                return text
            }
            searchEnd = hit.lowerBound
        }
        return nil
    }
}

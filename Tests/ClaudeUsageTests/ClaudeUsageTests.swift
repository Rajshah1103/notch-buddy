import Foundation
import Testing
@testable import ClaudeUsage

struct TranscriptParserTests {
    private func parse(_ json: String) -> TranscriptLine? { TranscriptParser.parse(Data(json.utf8)) }

    @Test func readsUsageFromAssistantMessages() {
        let line = parse(#"{"timestamp":"2026-10-23T10:00:00.000Z","message":{"id":"m1","role":"assistant","usage":{"input_tokens":10,"cache_creation_input_tokens":90,"cache_read_input_tokens":5000,"output_tokens":40}}}"#)
        #expect(line?.messageID == "m1")
        #expect(line?.inputTokens == 100)      // fresh + cache writes; cache reads are not new work
        #expect(line?.outputTokens == 40)
        #expect(line?.timestamp != nil)
    }

    @Test func ignoresEverythingElse() {
        #expect(parse(#"{"type":"mode","mode":"x"}"#) == nil)
        #expect(parse("not json at all") == nil)
        #expect(parse(#"{"message":{"role":"user","usage":{"input_tokens":5}}}"#) == nil)   // only assistant messages count
    }
}

struct SessionStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ id: String, input: Int = 10, output: Int = 5, at: Date) -> TranscriptLine {
        var l = TranscriptLine()
        l.messageID = id; l.inputTokens = input; l.outputTokens = output; l.timestamp = at
        return l
    }

    @Test func recentWritesMeanWorkingAndQuietMeansIdle() {
        var clock = t0
        let store = SessionStore(workingWindow: 30, now: { clock })
        store.ingest(fileID: "a", lines: [line("m1", at: t0)], modified: t0)
        #expect(store.snapshot().isWorking)
        clock = t0.addingTimeInterval(31)
        #expect(!store.snapshot().isWorking)
        #expect(store.snapshot().sessions.count == 1)
    }

    @Test func streamedUpdatesToOneMessageAreNotDoubleCounted() {
        let store = SessionStore(now: { self.t0 })
        store.ingest(fileID: "a", lines: [line("m1", output: 5, at: t0)], modified: t0)
        store.ingest(fileID: "a", lines: [line("m1", output: 50, at: t0)], modified: t0)
        #expect(store.snapshot().sessions[0].outputTokens == 50)
    }

    @Test func todayOnlyCountsTodaysMessages() {
        let store = SessionStore(now: { self.t0 })
        let yesterday = t0.addingTimeInterval(-26 * 3600)
        store.ingest(fileID: "a", lines: [line("old", at: yesterday), line("new", at: t0)], modified: t0)
        #expect(store.snapshot().tokensToday == 15)
    }

    @Test func aNewBurstStartsAfterQuiet() {
        var clock = t0
        let store = SessionStore(workingWindow: 30, now: { clock })
        store.ingest(fileID: "a", lines: [], modified: t0)
        let later = t0.addingTimeInterval(120)
        clock = later
        store.ingest(fileID: "a", lines: [], modified: later)
        #expect(store.snapshot().workingSince == later)
    }
}

struct TranscriptSeekerTests {
    private func writeTranscript(lines: Int) throws -> (URL, [Date]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seek-\(UUID().uuidString).jsonl")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var text = #"{"type":"user","cwd":"/Users/raj/notch-hub","timestamp":"\#(formatter.string(from: base))"}"# + "\n"
        var dates: [Date] = []
        for i in 0..<lines {
            let date = base.addingTimeInterval(Double(i) * 60)
            dates.append(date)
            // Padding makes the file big enough for the search to take several steps.
            text += #"{"type":"assistant","timestamp":"\#(formatter.string(from: date))","pad":"\#(String(repeating: "x", count: 400))"}"# + "\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return (url, dates)
    }

    @Test func findsWhereTodayBeginsWithoutReadingEverything() throws {
        let (url, dates) = try writeTranscript(lines: 2_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        let size = try handle.seekToEnd()
        let cutoff = dates[1_500]
        let offset = TranscriptSeeker.offset(of: cutoff, in: handle, size: size)

        // It must land before the cutoff line (never skip wanted lines) and well after the start.
        try handle.seek(toOffset: offset)
        let rest = try #require(try handle.readToEnd())
        #expect(rest.range(of: Data(ISO8601DateFormatter().string(from: dates[1_500]).prefix(19).utf8)) != nil)
        #expect(offset > size / 2)
    }

    @Test func readsTheFolderFromTheTranscriptHead() throws {
        let (url, _) = try writeTranscript(lines: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        #expect(TranscriptSeeker.folder(inHeadOf: handle) == "/Users/raj/notch-hub")
    }
}

struct ChatTitleTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func takesTheLastTitleAndUnescapesIt() {
        let log = data(#"{"aiTitle":"Old"}"# + "\n" + #"{"aiTitle":"New \"quoted\" name"}"# + "\n")
        #expect(TranscriptSeeker.lastValue(of: "aiTitle", in: log) == #"New "quoted" name"#)
    }

    @Test func ignoresEscapedCopiesInsideMessageText() {
        let log = data(#"{"aiTitle":"Real"}"# + "\n" + #"{"text":"\"aiTitle\":\"fake\""}"# + "\n")
        #expect(TranscriptSeeker.lastValue(of: "aiTitle", in: log) == "Real")
    }

    @Test func emptyOrMissingTitlesAreNil() {
        #expect(TranscriptSeeker.lastValue(of: "aiTitle", in: data(#"{"aiTitle":""}"#)) == nil)
        #expect(TranscriptSeeker.lastValue(of: "agentName", in: data(#"{"aiTitle":"x"}"#)) == nil)
    }

    @Test func sessionsShowTheTitleThenTheFolder() {
        let store = SessionStore()
        store.ingest(fileID: "a", folder: "/work/api", title: "Fix login bug", lines: [], modified: Date())
        store.ingest(fileID: "b", folder: "/work/web", lines: [], modified: Date())
        let names = Dictionary(uniqueKeysWithValues: store.snapshot().sessions.map { ($0.id, $0.displayName) })
        #expect(names["a"] == "Fix login bug")
        #expect(names["b"] == "web")
    }
}

struct TokenFormatTests {
    @Test func formatsCompactly() {
        #expect(TokenFormat.short(950) == "950")
        #expect(TokenFormat.short(12_400) == "12.4k")
        #expect(TokenFormat.short(3_000_000) == "3M")
        #expect(TokenFormat.short(3_200_000) == "3.2M")
    }
}

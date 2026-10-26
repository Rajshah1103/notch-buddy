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
        #expect(parse(#"{"message":{"role":"user","usage":{"input_tokens":5}}}"#)?.messageID == nil)   // only assistant messages count
    }
}

struct TurnTests {
    private func turn(_ json: String) -> Turn? { TranscriptParser.parse(Data(json.utf8))?.turn }

    @Test func classifiesWhoSpokeLast() {
        #expect(turn(#"{"message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text"}]}}"#) == .ended)
        #expect(turn(#"{"message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]}}"#) == .toolUse)
        #expect(turn(#"{"message":{"role":"assistant","content":[{"type":"thinking"}]}}"#) == .other)
        #expect(turn(#"{"message":{"role":"user","content":[{"type":"tool_result"}]}}"#) == .user)
        #expect(turn(#"{"type":"attachment"}"#) == nil)
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func store(_ turn: Turn, _ clock: Box) -> SessionStore {
        let store = SessionStore(workingWindow: 30, now: { clock.now })
        var l = TranscriptLine(); l.turn = turn
        store.ingest(fileID: "a", lines: [l], modified: t0)
        return store
    }
    final class Box { var now: Date; init(_ now: Date) { self.now = now } }

    @Test func anUnansweredToolCallAsksForApprovalAfterAPause() {
        let clock = Box(t0)
        let s = store(.toolUse, clock)
        #expect(s.snapshot().sessions[0].attention == nil)       // might just be a running tool
        #expect(s.snapshot().isWorking)
        clock.now = t0.addingTimeInterval(21)
        #expect(s.snapshot().sessions[0].attention == .approval)
        #expect(!s.snapshot().isWorking)                            // waiting is not working
    }

    @Test func aFinishedTurnAsksForAWhileThenStops() {
        let clock = Box(t0)
        let s = store(.ended, clock)
        clock.now = t0.addingTimeInterval(5)
        #expect(s.snapshot().sessions[0].attention == .finished)
        clock.now = t0.addingTimeInterval(11 * 60)
        #expect(s.snapshot().sessions[0].attention == nil)
    }

    @Test func aPromptOrToolResultMeansWorking() {
        let clock = Box(t0)
        let s = store(.user, clock)
        clock.now = t0.addingTimeInterval(120)             // a long generation writes nothing for a while
        #expect(s.snapshot().sessions[0].attention == nil)
        #expect(s.snapshot().isWorking)
        clock.now = t0.addingTimeInterval(200)
        #expect(!s.snapshot().isWorking)
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

struct UsageStatsTests {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))! }

    /// `perDay[0]` is today, `perDay[1]` yesterday, and so on.
    private func stats(_ perDay: [Int], hours: [Int]? = nil) -> UsageStats {
        let today = calendar.startOfDay(for: now)
        var daily: [Date: Int] = [:]
        for (back, tokens) in perDay.enumerated() where tokens > 0 { daily[calendar.date(byAdding: .day, value: -back, to: today)!] = tokens }
        return UsageStats(history: UsageHistory(daily: daily, hours: hours ?? Array(repeating: 0, count: 24), chats: [:]), now: now, calendar: calendar)
    }

    @Test func totalsAndAveragesCoverTheWindowEndingToday() {
        let s = stats([10, 20, 30])
        #expect(s.series(days: 3) == [30, 20, 10])
        #expect(s.total(days: 30) == 60)
        #expect(s.average(days: 30) == 2)
        #expect(s.busiest(days: 30)?.tokens == 30)
    }

    @Test func streakCountsBackFromTodayOrYesterday() {
        #expect(stats([5, 5, 5, 0, 5]).streak == 3)
        #expect(stats([0, 5, 5]).streak == 2)      // today has not started yet
        #expect(stats([0, 0, 5]).streak == 0)
    }

    @Test func trendComparesWithThePreviousPeriod() {
        let s = stats(Array(repeating: 200, count: 30) + Array(repeating: 100, count: 30))
        #expect(s.trend(days: 30) == 1.0)
        #expect(stats(Array(repeating: 100, count: 30)).trend(days: 30) == nil)
    }

    @Test func forecastAddsTheRecentPaceForTheDaysLeft() {
        let s = stats(Array(repeating: 100, count: 25))             // Oct 1...25, 100 a day
        let f = s.monthForecast
        #expect(f.soFar == 2_500)
        #expect(f.daysLeft == 6)
        #expect(f.projected == 2_500 + 100 * 6)
    }

    @Test func personaFollowsHabitsThenVolume() {
        var night = Array(repeating: 0, count: 24); night[23] = 100; night[1] = 100; night[12] = 50
        #expect(stats([100, 0, 100], hours: night).persona.name == "The Midnight Prompter")
        #expect(stats([]).persona.name == "The Quiet Type")
        #expect(stats([0, 9_000_000, 0, 9_000_000]).persona.name != "The Quiet Type")
        var noon = Array(repeating: 0, count: 24); noon[12] = 100
        #expect(stats([10_000, 0, 10_000], hours: noon).persona.name == "The Polite Prompter")
        #expect(stats([1], hours: noon).peakHour == 12)
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

struct QuietSessionTests {
    @Test func aSessionClaudeReportsIdleIsNotWorkingEvenIfItsTranscriptWasJustTouched() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = SessionStore(workingWindow: 30, now: { now })
        store.ingest(fileID: "a", folder: "/p/a", lines: [], modified: now.addingTimeInterval(-5))
        #expect(store.snapshot().working.count == 1)
        store.setQuiet(["a"])
        #expect(store.snapshot().working.isEmpty)
        #expect(store.snapshot().sessions.count == 1)          // still listed, just not working
    }
}

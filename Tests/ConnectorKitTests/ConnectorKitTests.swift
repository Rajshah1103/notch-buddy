import Foundation
import Testing
@testable import ConnectorKit

struct MessageTests {
    private func parse(_ text: String) throws -> Message { try Message.parse(Data(text.utf8)) }

    @Test func momentNeedsSourceAndHeadline() throws {
        #expect(throws: Message.ParseError.missing("headline")) { try parse(#"{"source":"gitlab"}"#) }
        #expect(throws: Message.ParseError.missing("source")) { try parse(#"{"headline":"hi"}"#) }
        guard case .moment(let m) = try parse(##"{"source":"gitlab","headline":"Pipeline failed","tint":"#FC6D26","ttl":6}"##) else { Issue.record("not a moment"); return }
        #expect(m.source == "gitlab" && m.headline == "Pipeline failed" && m.tint == "#FC6D26" && m.ttl == 6)
    }

    @Test func agentStatesParse() throws {
        guard case .agent(let a) = try parse(#"{"type":"agent","harness":"codex","session":"s1","state":"needs-approval"}"#) else { Issue.record("not an agent"); return }
        #expect(a.state == .needsApproval && a.harness == "codex")
        #expect(throws: Message.ParseError.missing("state")) { try parse(#"{"type":"agent","harness":"codex","session":"s1","state":"bogus"}"#) }
    }

    @Test func badInputIsRejected() {
        #expect(throws: Message.ParseError.notJSON) { try parse("hello") }
        #expect(throws: Message.ParseError.unknownType("rm")) { try parse(#"{"type":"rm"}"#) }
        #expect(throws: Message.ParseError.tooLong) { try Message.parse(Data(repeating: 0x61, count: Message.maxLine + 1)) }
    }

    @Test func textIsTrimmedAndCapped() throws {
        guard case .moment(let m) = try parse(#"{"source":"  x ","headline":"\#(String(repeating: "a", count: 500))"}"#) else { return }
        #expect(m.source == "x" && m.headline.count == 120)
    }
}

struct LineBufferTests {
    @Test func splitsAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.feed(Data("{\"a\":1}\n{\"b".utf8)).count == 1)
        #expect(buffer.feed(Data("\":2}\n".utf8)).count == 1)
    }

    @Test func dropsAnOverlongLineWholeAndRecovers() {
        var buffer = LineBuffer()
        let big = Data(repeating: 0x61, count: Message.maxLine * 3)
        #expect(buffer.feed(big).isEmpty)
        let lines = buffer.feed(Data("tail\nok\n".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["ok"])
    }
}

struct RateLimitTests {
    @Test func dropsTheBurstAndRecovers() {
        var limit = RateLimit(limit: 3, window: 10)
        #expect((0..<5).map { limit.allow(now: Double($0)) } == [true, true, true, false, false])
        #expect(limit.allow(now: 11))
    }
}

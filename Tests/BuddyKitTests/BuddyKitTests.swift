import Foundation
import Testing
@testable import BuddyKit

struct BuddyAnimatorTests {
    @Test func everyMoodHasABoundedPose() {
        for mood in Mood.allCases {
            for step in 0..<400 {
                let p = BuddyAnimator.pose(mood: mood, time: Double(step) * 0.05, sinceChange: Double(step) * 0.05)
                #expect(p.scaleX > 0.6 && p.scaleX < 1.4)
                #expect(p.scaleY > 0.6 && p.scaleY < 1.4)
                #expect(p.blink >= 0 && p.blink <= 1)
                #expect(abs(p.lift) < 0.3)
            }
        }
    }

    @Test func sleepyIsAlwaysShutAndOthersBlinkBriefly() {
        #expect(BuddyAnimator.pose(mood: .sleepy, time: 1.234, sinceChange: 9).blink == 1)
        #expect(BuddyAnimator.pose(mood: .working, time: 1.0, sinceChange: 9).blink == 0)
        #expect(BuddyAnimator.pose(mood: .working, time: 3.7 + 0.1, sinceChange: 9).blink > 0.9)
    }

    @Test func aChangeOfMoodPopsAndSettles() {
        let early = BuddyAnimator.pose(mood: .happy, time: 100, sinceChange: 0.1)
        let late = BuddyAnimator.pose(mood: .happy, time: 100, sinceChange: 5)
        #expect(abs(early.scaleY - 1) > abs(late.scaleY - 1) || early.scaleY != late.scaleY)
        #expect(late.lift == 0)                    // the happy hops have ended
    }
}

struct MomentQueueTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func moment(_ id: String, priority: Int = 50, group: String? = nil, many: String? = nil, ttl: TimeInterval = 4) -> Moment {
        Moment(id: id, source: .gmail, mood: .excited, headline: "one", symbol: "envelope", priority: priority, ttl: ttl,
               group: group, manyHeadline: many)
    }

    @Test func showsOneAtATimeAndPacesTheNext() {
        var q = MomentQueue(minGap: 8)
        q.add(moment("a"), now: t0); q.add(moment("b"), now: t0)
        q.advance(now: t0)
        #expect(q.showing?.id == "a")
        q.advance(now: t0.addingTimeInterval(5))                     // a ended, but the pause is not over
        #expect(q.showing == nil)
        q.advance(now: t0.addingTimeInterval(8.1))
        #expect(q.showing?.id == "b")
    }

    @Test func holdingKeepsABubbleUp() {
        var q = MomentQueue()
        q.add(moment("a"), now: t0); q.advance(now: t0)
        q.advance(now: t0.addingTimeInterval(30), held: true)
        #expect(q.showing?.id == "a")
        q.advance(now: t0.addingTimeInterval(31), held: false)
        #expect(q.showing == nil)
    }

    @Test func urgentOnesSkipThePause() {
        var q = MomentQueue(minGap: 8)
        q.add(moment("a"), now: t0); q.advance(now: t0)
        q.add(moment("fire", priority: 95), now: t0.addingTimeInterval(1))
        q.advance(now: t0.addingTimeInterval(5))                     // a has ended
        #expect(q.showing?.id == "fire")
    }

    @Test func repeatsAreIgnoredForAWhile() {
        var q = MomentQueue(repeatWindow: 120)
        q.add(moment("a"), now: t0); q.advance(now: t0)
        #expect(q.add(moment("a"), now: t0.addingTimeInterval(10)) == false)
        #expect(q.add(moment("a"), now: t0.addingTimeInterval(200)) == true)
    }

    @Test func burstsOfOneKindMerge() {
        var q = MomentQueue()
        q.add(moment("x"), now: t0); q.advance(now: t0)               // x is on screen
        q.add(moment("m1", group: "mail", many: "%d new mails"), now: t0)
        q.add(moment("m2", group: "mail", many: "%d new mails"), now: t0)
        q.add(moment("m3", group: "mail", many: "%d new mails"), now: t0)
        #expect(q.pending.count == 1)
        #expect(q.pending[0].count == 3)
        #expect(q.pending[0].headline == "3 new mails")
    }

    @Test func theQueueStaysShortAndKeepsTheImportant() {
        var q = MomentQueue(capacity: 3)
        q.add(moment("show"), now: t0); q.advance(now: t0)
        for (i, p) in [10, 20, 30, 40, 50].enumerated() { q.add(moment("p\(i)", priority: p), now: t0) }
        #expect(q.pending.map(\.priority) == [50, 40, 30])
    }

    @Test func nextWakeSaysWhenToLookAgain() {
        var q = MomentQueue(minGap: 8)
        q.add(moment("a", ttl: 4), now: t0); q.advance(now: t0)
        #expect(q.nextWake(now: t0) == t0.addingTimeInterval(4))
    }
}

struct AnticTests {
    @Test func everyAnticStaysBoundedAndEndsAtRest() {
        for antic in Antic.allCases {
            let rest = antic == .peek ? Antic.hiddenDX : 0
            for step in 0...200 {
                let t = antic.duration * Double(step) / 200
                let f = antic.frame(at: t, travel: 6)
                #expect(f.pose.scaleX > 0.6 && f.pose.scaleX < 1.4)
                #expect(f.pose.scaleY > 0.6 && f.pose.scaleY < 1.4)
                #expect(abs(f.pose.lift) < 0.3)
                #expect(f.dx >= -0.5 && f.dx <= 6)
                #expect(f.captionOpacity >= 0 && f.captionOpacity <= 1)
            }
            let first = antic.frame(at: 0), last = antic.frame(at: antic.duration)
            #expect(abs(first.dx - rest) < 0.001 && abs(last.dx - rest) < 0.001)
            #expect(first.roll.truncatingRemainder(dividingBy: 360) == 0 && last.roll.truncatingRemainder(dividingBy: 360) == 0)
            #expect(first.captionOpacity == 0 && last.captionOpacity == 0)
        }
    }

    @Test func captionsAreShortAndNeverEmpty() {
        for antic in Antic.allCases {
            for caption in antic.captions {
                let words = caption.split(separator: " ").count
                #expect(words >= 1 && words <= 4)
            }
        }
    }
}

struct IdleDirectorTests {
    private func director() -> IdleDirector {
        var d = IdleDirector(seed: 7)
        d.firstDelay = 60...60
        d.gap = 100...100
        return d
    }

    @Test func firstCameoWaitsThenGapsApply() {
        var d = director()
        #expect(d.update(now: 0, isIdle: true, userIdle: 1) == .rest)
        #expect(d.update(now: 59, isIdle: true, userIdle: 1) == .rest)
        guard case .play(let first, _) = d.update(now: 60, isIdle: true, userIdle: 1) else { return Issue.record("no cameo") }
        #expect(Antic.cameos.contains(first))
        #expect(d.update(now: 60 + first.duration + 99, isIdle: true, userIdle: 1) == .rest)
        guard case .play(let second, _) = d.update(now: 60 + first.duration + 100, isIdle: true, userIdle: 1) else { return Issue.record("no second cameo") }
        #expect(second != first)
    }

    @Test func neverRepeatsAnAnticBackToBack() {
        var d = director()
        var last: Antic?
        var now = 0.0
        for _ in 0..<60 {
            now += 400
            if case .play(let a, _) = d.update(now: now, isIdle: true, userIdle: 1) {
                #expect(a != last)
                last = a
            }
        }
    }

    @Test func anythingElseOwningTheNotchRestartsTheWait() {
        var d = director()
        _ = d.update(now: 0, isIdle: true, userIdle: 1)
        #expect(d.update(now: 50, isIdle: false, userIdle: 1) == .rest)
        #expect(d.update(now: 70, isIdle: true, userIdle: 1) == .rest)        // the wait starts over at 70
        #expect(d.update(now: 129, isIdle: true, userIdle: 1) == .rest)
        #expect(d.update(now: 130, isIdle: true, userIdle: 1) != .rest)
    }

    @Test func napsAfterALongBreakAndWavesOnceOnReturn() {
        var d = director()
        _ = d.update(now: 0, isIdle: true, userIdle: 1)
        guard case .play(let nap, _) = d.update(now: 30, isIdle: true, userIdle: 600) else { return Issue.record("no nap") }
        #expect(nap == .nap)
        #expect(d.update(now: 40, isIdle: true, userIdle: 610) == .rest)      // stays tucked while asleep
        guard case .play(let wake, _) = d.update(now: 50, isIdle: true, userIdle: 2) else { return Issue.record("no wave") }
        #expect(wake == .wakeWave)
        #expect(d.update(now: 52, isIdle: true, userIdle: 3) == .rest)        // only once
    }
}

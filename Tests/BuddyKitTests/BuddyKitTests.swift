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
        #expect(BuddyAnimator.pose(mood: .working, time: 3.7 + 0.07, sinceChange: 9).blink > 0.9)
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

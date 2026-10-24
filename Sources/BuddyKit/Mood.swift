import Foundation

/// How the buddy feels. Each mood has its own face and motion.
public enum Mood: String, CaseIterable, Sendable {
    case sleepy         // nothing going on
    case working        // Claude is cooking
    case thinking
    case needsYou       // waiting for an approval
    case happy          // finished
    case proud          // a build went green
    case sad            // a build broke
    case excited        // new mail
    case alert          // a review request
    case clockWatching  // a meeting is close
    case shocked        // your checks failed
}

/// How the buddy's body is moving at one instant. Everything is a pure function of time, so animation needs
/// no stored state: a view just asks "what is the pose now?" on each tick.
public struct Pose: Equatable {
    public var scaleX: Double = 1
    public var scaleY: Double = 1
    /// Vertical offset as a fraction of the buddy's size; positive is up.
    public var lift: Double = 0
    /// 0 is open, 1 is shut.
    public var blink: Double = 0
    /// Where the eyes look, -1...1 on each axis.
    public var lookX: Double = 0
    public var lookY: Double = 0
    /// Horizontal shiver as a fraction of size.
    public var shake: Double = 0
}

public enum BuddyAnimator {
    /// `time` is seconds since any fixed moment; `sinceChange` is seconds since the mood last changed.
    public static func pose(mood: Mood, time t: Double, sinceChange dt: Double) -> Pose {
        var p = Pose()

        // Always alive: a slow breath.
        let breath = sin(t * 2 * .pi / 2.8)
        let amount = mood == .sleepy ? 0.04 : 0.022
        p.scaleY += amount * breath
        p.scaleX -= amount * 0.6 * breath

        // A quick squash-and-stretch when the mood changes, settling in about half a second.
        let pop = exp(-7 * max(dt, 0)) * sin(16 * max(dt, 0)) * 0.22
        p.scaleY += pop
        p.scaleX -= pop * 0.7

        switch mood {
        case .sleepy:
            p.blink = 1
        case .working:
            p.lift = 0.012 * sin(t * 14)                       // typing jitter
            p.lookY = -0.5
            p.lookX = 0.35 * sin(t * 1.6)
        case .thinking:
            p.lookY = 0.6
            p.lookX = 0.6 * sin(t * 0.9)
        case .needsYou:
            // Hops at first, then a small nudge every few seconds: still asking, but cheap to draw.
            let settle = max(0, 1 - dt / 3)
            let phase = t.truncatingRemainder(dividingBy: 5)
            p.lift = 0.10 * abs(sin(t * 3.2)) * settle + (phase < 0.6 ? 0.08 * abs(sin(phase / 0.6 * .pi)) : 0)
        case .happy, .proud:
            let settle = max(0, 1 - dt / 1.4)
            p.lift = 0.14 * settle * abs(sin(t * 5))           // a few happy hops, then calm
        case .sad:
            p.scaleY *= 0.92
            p.lookY = -0.7
            p.shake = 0.012 * sin(t * 1.3)
        case .excited:
            p.lift = 0.16 * abs(sin(t * 6.5)) * max(0.12, 1 - dt / 3)
        case .alert:
            p.lookX = sin(t * 5) > 0 ? 0.7 : -0.7
        case .clockWatching:
            p.lookX = sin(t * 2.2) > 0 ? 0.8 : -0.8
            p.lookY = 0.2
        case .shocked:
            p.shake = 0.02 * sin(t * 32) * max(0, 1 - dt / 1.2)
            p.scaleY += 0.06 * max(0, 1 - dt / 0.5)
        }

        // Blink: shut for a fifth of a second every few seconds (never while asleep, which is shut already).
        if mood != .sleepy {
            let phase = t.truncatingRemainder(dividingBy: 3.7)
            if phase < 0.2 { p.blink = 1 - abs(phase - 0.1) / 0.1 }
        }
        return p
    }
}

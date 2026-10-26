import Foundation

/// A little bit of idle personality: the buddy pops out beside the notch, does one thing, and tucks back in.
/// Like `BuddyAnimator`, every frame is a pure function of time, so an antic needs no stored state.
public enum Antic: CaseIterable, Sendable {
    case dance, wave, peek, yawn, vibeCheck, spin, sneak
    /// Falls asleep after a long idle spell; not part of the random cameos.
    case nap
    /// Greets you when you come back after a long break.
    case wakeWave

    /// The ones picked at random while you are around.
    public static let cameos: [Antic] = [.dance, .wave, .peek, .yawn, .vibeCheck, .spin, .sneak]

    public var duration: Double {
        switch self {
        case .dance: 4.5
        case .wave, .wakeWave: 3
        case .peek: 3.6
        case .yawn: 3.6
        case .vibeCheck: 3.4
        case .spin: 2.6
        case .sneak: 5
        case .nap: 7
        }
    }

    /// Short enough for an ear (about ten characters), a few ways to say it, picked by `variant`.
    public var captions: [String] {
        switch self {
        case .dance: ["vibing", "no thoughts", "party"]
        case .wave: ["hi bestie", "sup", "hiii"]
        case .peek: ["sup", "boo", "hehe"]
        case .yawn: ["so tired", "need nap", "sleepy"]
        case .vibeCheck: ["vibe check", "rizz?", "all good?"]
        case .spin: ["slay", "iconic", "main char"]
        case .sneak: ["psst", "sneaky", "on a quest"]
        case .nap: ["zzz", "gn", "brb"]
        case .wakeWave: ["oh hi", "ur back", "wb"]
        }
    }

    public func caption(variant: Int) -> String { captions[abs(variant) % captions.count] }

    /// One instant of an antic. `dx` is sideways travel in buddy sizes (positive is toward the notch from the
    /// left ear), `roll` is a rotation in degrees.
    public struct Frame: Equatable {
        public var mood: Mood
        public var pose: Pose
        public var dx: Double
        public var roll: Double
        /// 0 to 1: the caption fades in after the buddy appears and out before it leaves.
        public var captionOpacity: Double
    }

    /// How far the buddy sits behind the notch when it is hidden, in buddy sizes.
    public static let hiddenDX = 2.3

    /// `travel` is the distance in buddy sizes from one ear's buddy position to the other's, for `sneak`.
    public func frame(at t: Double, travel: Double = 6) -> Frame {
        let d = duration
        let t = min(max(t, 0), d)
        let env = smooth(t / 0.35) * smooth((d - t) / 0.35)

        var mood = Mood.happy
        var dx = 0.0, roll = 0.0
        var lift: Double?, lookX: Double?, scaleY = 0.0
        // The caption lives in the right ear, so it steps aside while the buddy walks through it.
        var captionRoom = 1.0

        switch self {
        case .dance:
            mood = .excited
            lift = 0.14 * abs(sin(t * 7)) * env
            roll = 12 * sin(t * 7) * env
            dx = 0.45 * sin(t * 3.5) * env
        case .wave, .wakeWave:
            mood = .happy
            lift = 0.04 * abs(sin(t * 4)) * env
            roll = 16 * sin(t * 9) * env
        case .peek:
            mood = .thinking
            let out = smooth(t / 0.5), back = smooth((t - (d - 0.5)) / 0.5)
            dx = Self.hiddenDX * (1 - out + back)
            lookX = -0.8 * sin(max(0, t - 0.5) * 2.4)
        case .yawn:
            mood = .sleepy
            let stretch = bump((t - 0.7) / 1.6)
            scaleY = 0.1 * stretch
            lift = 0.05 * stretch
        case .vibeCheck:
            mood = .alert
            let hop = bump((t - 1.4) / 0.5)
            lift = 0.12 * hop
        case .spin:
            mood = .excited
            let turn = clamp((t - 0.4) / 0.9)
            roll = 360 * smooth(turn)
            lift = 0.18 * sin(.pi * turn)
        case .sneak:
            mood = .alert
            let half = d / 2
            let along = t < half ? smooth(t / half) : 1 - smooth((t - half) / half)
            dx = travel * along
            captionRoom = 1 - smooth(along * 1.6)
            lift = 0.04 * abs(sin(t * 9)) * env
            lookX = t < half ? 0.8 : -0.8
        case .nap:
            mood = .sleepy
        }

        var pose = BuddyAnimator.pose(mood: mood, time: t, sinceChange: t)
        if let lift { pose.lift = lift }
        if let lookX { pose.lookX = lookX }
        pose.scaleY += scaleY
        pose.scaleX -= scaleY * 0.5
        let caption = smooth((t - 0.5) / 0.3) * smooth((d - 0.3 - t) / 0.3) * captionRoom
        return Frame(mood: mood, pose: pose, dx: dx, roll: roll, captionOpacity: caption)
    }
}

private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
private func smooth(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
/// 0 outside 0...1, rising and falling once inside.
private func bump(_ x: Double) -> Double { x <= 0 || x >= 1 ? 0 : sin(.pi * x) }

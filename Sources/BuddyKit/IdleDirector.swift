import Foundation

/// Decides when the buddy should step out and do something while nothing else is going on. Pure: the caller
/// supplies the clock and how long you have been away, so the pacing is easy to test.
public struct IdleDirector {
    public enum Decision: Equatable {
        /// Nothing to show right now.
        case rest
        case play(Antic, variant: Int)
    }

    /// Seconds between the notch becoming idle and the first cameo, and between cameos after that.
    public var firstDelay: ClosedRange<Double> = 60...120
    public var gap: ClosedRange<Double> = 60...180
    /// How long without touching the Mac before the buddy falls asleep.
    public var napAfter: Double = 600

    private var generator: SplitMix64
    private var idleSince: Double?
    private var nextAt = 0.0
    private var last: Antic?
    /// Asleep, and waiting for you to come back.
    private var away = false

    public init(seed: UInt64 = .random(in: .min ... .max)) {
        generator = SplitMix64(seed: seed)
    }

    /// Call on a slow tick. `isIdle` is false while anything else owns the notch (an activity, a bubble).
    public mutating func update(now: Double, isIdle: Bool, userIdle: Double) -> Decision {
        guard isIdle else {
            idleSince = nil
            return .rest
        }
        if idleSince == nil {
            idleSince = now
            nextAt = now + Double.random(in: firstDelay, using: &generator)
        }
        if away {
            guard userIdle < 5 else { return .rest }
            away = false
            nextAt = now + Antic.wakeWave.duration + Double.random(in: gap, using: &generator)
            return .play(.wakeWave, variant: variant())
        }
        if userIdle >= napAfter {
            away = true
            return .play(.nap, variant: variant())
        }
        guard now >= nextAt else { return .rest }
        let pool = Antic.cameos.filter { $0 != last }
        let antic = pool.randomElement(using: &generator) ?? .dance
        last = antic
        nextAt = now + antic.duration + Double.random(in: gap, using: &generator)
        return .play(antic, variant: variant())
    }

    private mutating func variant() -> Int { Int.random(in: 0..<1000, using: &generator) }
}

/// A small seedable generator (SplitMix64), so pacing can be tested without real randomness.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

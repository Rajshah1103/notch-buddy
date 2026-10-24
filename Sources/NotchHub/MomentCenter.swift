import AppKit
import BuddyKit
import Combine
import SwiftUI

/// Owns the one bubble: takes moments from every source, runs them through `MomentQueue`, and tells the notch
/// when to grow or shrink the bubble. Event driven: a timer is armed only for the next change, never polled.
@MainActor
final class MomentCenter: ObservableObject {
    /// The bubble's size; the notch grows to this when a moment shows.
    static let bubbleSize = CGSize(width: 372, height: 56)

    @Published private(set) var showing: Moment?

    /// Called with the bubble's size when one appears, nil when it goes.
    var onBubble: ((CGSize?) -> Void)?
    /// A click on the bubble (or its action button).
    var onActivate: ((Moment, _ action: Bool) -> Void)?

    private var queue = MomentQueue()
    private var held = false
    private var wake: Timer?

    func post(_ moment: Moment) {
        guard AppSettings.shared.showBubbles else { return }
        queue.add(moment, now: Date())
        tick()
    }

    /// For the snapshot tool: show this moment without any timing.
    func loadForPreview(_ moment: Moment?) { showing = moment }

    func post(_ moments: [Moment]) { moments.forEach(post) }

    /// The pointer is on the bubble: keep it up.
    func setHeld(_ on: Bool) {
        guard held != on else { return }
        held = on
        tick()
    }

    func activate(action: Bool) {
        guard let moment = showing else { return }
        onActivate?(moment, action)
        dismiss()
    }

    func dismiss() {
        queue.dismiss()
        held = false
        tick()
    }

    private func tick() {
        wake?.invalidate(); wake = nil
        let before = showing
        queue.advance(now: Date(), held: held)
        if queue.showing != before {
            let appearing = before == nil && queue.showing != nil
            let vanishing = before != nil && queue.showing == nil
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { showing = queue.showing }
            if appearing { onBubble?(Self.bubbleSize) }
            if vanishing { onBubble?(nil) }
        }
        if !held, let next = queue.nextWake(now: Date()) {
            wake = Timer.scheduledTimer(withTimeInterval: max(0.05, next.timeIntervalSinceNow + 0.02), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }
}

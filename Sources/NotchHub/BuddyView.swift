import BuddyKit
import SwiftUI

/// The notch buddy: a soft blob with a face. It is drawn with one Canvas and moved by `BuddyAnimator`, a pure
/// function of time, so it needs no per-frame state and costs almost nothing. It only ticks while it is on screen.
struct BuddyView: View {
    let mood: Mood
    var tint: Color = Theme.claude
    var size: CGFloat = 22
    /// A fixed moment, for offscreen renders (a timeline does not run there).
    var fixedTime: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changedAt = Date.timeIntervalSinceReferenceDate
    /// Right after a mood change the buddy moves a lot, so it ticks fast; then it settles to a slow tick.
    /// Ticking costs CPU for as long as the view is on screen, so the slow rate is what runs most of the time.
    @State private var lively = true
    @State private var settleWork: DispatchWorkItem?

    var body: some View {
        Group {
            if let fixedTime {
                canvas(time: fixedTime, since: 9)
            } else if reduceMotion {
                canvas(time: 0.5, since: 9)                  // a still pose, no ticking at all
            } else {
                // Calm rate measured at about 0.5% of a core at 2 fps, and about 1% at 5 to 8 fps.
                TimelineView(.animation(minimumInterval: lively ? 1.0 / 20 : 1.0 / 2)) { context in
                    let now = context.date.timeIntervalSinceReferenceDate
                    canvas(time: now, since: now - changedAt)
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { startLively() }
        .onAppear { startLively() }
        .accessibilityHidden(true)
    }

    private func startLively() {
        changedAt = Date.timeIntervalSinceReferenceDate
        lively = true
        settleWork?.cancel()
        let work = DispatchWorkItem { lively = false }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    private func canvas(time: Double, since: Double) -> some View {
        let pose = BuddyAnimator.pose(mood: mood, time: time, sinceChange: since)
        return Canvas { context, canvasSize in
            BuddyArt.draw(in: &context, size: canvasSize, mood: mood, tint: tint, pose: pose)
        }
    }
}

enum BuddyArt {
    static func draw(in context: inout GraphicsContext, size: CGSize, mood: Mood, tint: Color, pose: Pose) {
        let s = min(size.width, size.height)
        let ink = Color.black.opacity(0.86)
        let lineWidth = max(1.1, s * 0.07)

        // Body, squashed and lifted about its base.
        var body = context
        body.translateBy(x: size.width / 2 + pose.shake * s, y: size.height * 0.94 - pose.lift * s)
        body.scaleBy(x: pose.scaleX, y: pose.scaleY)
        body.translateBy(x: -size.width / 2, y: -size.height * 0.94)

        let w = s * 0.9, h = s * 0.8
        let rect = CGRect(x: (size.width - w) / 2, y: size.height * 0.94 - h, width: w, height: h)
        body.fill(blob(in: rect), with: .linearGradient(
            Gradient(colors: [tint.opacity(1), tint.opacity(0.78)]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        // A soft highlight so it reads as a glossy blob and not a flat shape.
        body.fill(Path(ellipseIn: CGRect(x: rect.minX + w * 0.16, y: rect.minY + h * 0.1, width: w * 0.28, height: h * 0.16)),
                  with: .color(.white.opacity(0.32)))

        // Face.
        let cx = rect.midX, ey = rect.minY + h * 0.46
        let gap = w * 0.2
        let lx = pose.lookX * w * 0.04, ly = -pose.lookY * h * 0.04
        let eyeW = w * 0.15, eyeH = h * 0.22
        let open = 1 - pose.blink

        func round(_ x: CGFloat, openness: CGFloat = 1, scale: CGFloat = 1) {
            let hh = max(lineWidth * 0.5, eyeH * scale * openness)
            body.fill(Path(ellipseIn: CGRect(x: x - eyeW * scale / 2 + lx, y: ey - hh / 2 + ly, width: eyeW * scale, height: hh)), with: .color(ink))
        }
        func arc(_ x: CGFloat, up: Bool) {            // ^ (happy) or v (droopy) eye
            var p = Path()
            let r = eyeW * 0.62
            p.addArc(center: CGPoint(x: x + lx, y: ey + (up ? r * 0.5 : -r * 0.5) + ly), radius: r,
                     startAngle: .degrees(up ? 200 : 20), endAngle: .degrees(up ? 340 : 160), clockwise: false)
            body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        func mouth(_ kind: Mouth) {
            let my = rect.minY + h * 0.72
            var p = Path()
            switch kind {
            case .smile:
                p.addArc(center: CGPoint(x: cx, y: my - w * 0.04), radius: w * 0.11, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            case .grin:
                p.addArc(center: CGPoint(x: cx, y: my - w * 0.06), radius: w * 0.16, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                p.closeSubpath()
                body.fill(p, with: .color(ink))
            case .flat:
                p.move(to: CGPoint(x: cx - w * 0.08, y: my)); p.addLine(to: CGPoint(x: cx + w * 0.08, y: my))
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            case .frown:
                p.addArc(center: CGPoint(x: cx, y: my + w * 0.1), radius: w * 0.11, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                body.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            case .o(let r):
                body.fill(Path(ellipseIn: CGRect(x: cx - w * r, y: my - w * r * 0.9, width: w * r * 2, height: w * r * 2.1)), with: .color(ink))
            }
        }

        switch mood {
        case .sleepy:
            arc(cx - gap, up: false); arc(cx + gap, up: false); mouth(.flat)
        case .working:
            round(cx - gap, openness: 0.55 * open); round(cx + gap, openness: 0.55 * open); mouth(.flat)
        case .thinking:
            round(cx - gap, openness: open); round(cx + gap, openness: open); mouth(.flat)
        case .needsYou:
            round(cx - gap, openness: open, scale: 1.25); round(cx + gap, openness: open, scale: 1.25); mouth(.o(0.06))
        case .happy:
            arc(cx - gap, up: true); arc(cx + gap, up: true); mouth(.smile)
        case .proud:
            arc(cx - gap, up: true); arc(cx + gap, up: true); mouth(.grin)
        case .sad:
            arc(cx - gap, up: false); arc(cx + gap, up: false); mouth(.frown)
        case .excited:
            round(cx - gap, openness: open, scale: 1.2); round(cx + gap, openness: open, scale: 1.2); mouth(.grin)
        case .alert:
            round(cx - gap, openness: open); round(cx + gap, openness: open); mouth(.flat)
            var brows = Path()
            // Inner ends raised: an eager "hey, look at this", not an angry face.
            brows.move(to: CGPoint(x: cx - gap - eyeW * 0.8, y: ey - eyeH * 0.6)); brows.addLine(to: CGPoint(x: cx - gap + eyeW * 0.6, y: ey - eyeH * 1.0))
            brows.move(to: CGPoint(x: cx + gap + eyeW * 0.8, y: ey - eyeH * 0.6)); brows.addLine(to: CGPoint(x: cx + gap - eyeW * 0.6, y: ey - eyeH * 1.0))
            body.stroke(brows, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        case .clockWatching:
            round(cx - gap, openness: open); round(cx + gap, openness: open); mouth(.flat)
        case .shocked:
            round(cx - gap, openness: open, scale: 0.6); round(cx + gap, openness: open, scale: 0.6); mouth(.o(0.1))
        }

        // Extras that only fit when the buddy is big enough to show them.
        guard s >= 26 else { return }
        switch mood {
        case .needsYou:                                           // a hand up
            let hand = CGRect(x: rect.maxX - w * 0.04, y: rect.minY - h * 0.02, width: w * 0.2, height: w * 0.2)
            context.fill(Path(ellipseIn: hand), with: .color(tint))
        case .happy, .proud:
            sparkle(&context, at: CGPoint(x: rect.maxX + w * 0.02, y: rect.minY + h * 0.06), r: w * 0.1, color: .white)
        case .sad:                                                // a tear
            context.fill(Path(ellipseIn: CGRect(x: cx + gap * 1.3, y: ey + eyeH * 0.8, width: w * 0.06, height: w * 0.09)), with: .color(.cyan.opacity(0.85)))
        case .clockWatching:                                      // a tiny clock face
            let face = CGRect(x: rect.maxX - w * 0.1, y: rect.minY - h * 0.04, width: w * 0.26, height: w * 0.26)
            context.fill(Path(ellipseIn: face), with: .color(.white))
            var hands = Path()
            hands.move(to: CGPoint(x: face.midX, y: face.midY)); hands.addLine(to: CGPoint(x: face.midX, y: face.minY + face.height * 0.2))
            hands.move(to: CGPoint(x: face.midX, y: face.midY)); hands.addLine(to: CGPoint(x: face.maxX - face.width * 0.22, y: face.midY))
            context.stroke(hands, with: .color(.black.opacity(0.8)), style: StrokeStyle(lineWidth: max(1, s * 0.03), lineCap: .round))
        case .sleepy:
            context.draw(Text("z").font(.system(size: s * 0.28, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.7)),
                         at: CGPoint(x: rect.maxX + w * 0.04, y: rect.minY + h * 0.05))
        case .thinking:
            context.draw(Text("…").font(.system(size: s * 0.3, weight: .bold)).foregroundColor(.white.opacity(0.75)),
                         at: CGPoint(x: rect.maxX, y: rect.minY))
        default: break
        }
    }

    private enum Mouth { case smile, grin, flat, frown, o(CGFloat) }

    /// A rounded blob: wider at the bottom than the top, like a drop of jelly.
    private static func blob(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.midY + r.height * 0.1),
                   control1: CGPoint(x: r.midX + r.width * 0.34, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + r.height * 0.18))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.02), control2: CGPoint(x: r.midX + r.width * 0.32, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.1),
                   control1: CGPoint(x: r.midX - r.width * 0.32, y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - r.height * 0.02))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + r.height * 0.18), control2: CGPoint(x: r.midX - r.width * 0.34, y: r.minY))
        p.closeSubpath()
        return p
    }

    private static func sparkle(_ context: inout GraphicsContext, at c: CGPoint, r: CGFloat, color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.15))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.15, y: c.y + r * 0.15))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.15, y: c.y + r * 0.15))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.15))
        context.fill(p, with: .color(color))
    }
}

extension Mood {
    /// What the sheet and settings call it.
    var label: String {
        switch self {
        case .sleepy: return "sleepy"
        case .working: return "working"
        case .thinking: return "thinking"
        case .needsYou: return "needs you"
        case .happy: return "done"
        case .proud: return "green"
        case .sad: return "broke"
        case .excited: return "new mail"
        case .alert: return "review"
        case .clockWatching: return "meeting"
        case .shocked: return "failed"
        }
    }
}

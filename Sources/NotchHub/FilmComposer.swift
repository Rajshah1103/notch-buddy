import AppKit
import BuddyKit
import SwiftUI
import UniformTypeIdentifiers

/// Composes the launch-film frames from the stills `Film.renderStill` writes. Every animation is a pure function of
/// time, so a frame is identical on every run, and nothing here touches the live app, the pointer or real data.
@MainActor
enum FilmComposer {
    /// Scene order and length in seconds. The narration for each scene starts half a second in.
    static let scenes: [(name: String, duration: Double)] = [
        ("00_cold", 4.8), ("01_switcher", 6.2), ("02_tabs", 6.0), ("03_search", 5.4), ("04_claude", 11.6),
        ("05_gmail", 5.2), ("06_ci", 8.4), ("07_meet", 4.4), ("08_outro", 5.5),
    ]

    static func render(stills: String, out: String, scene only: String, aspect: String, fps: Int) {
        _ = NSApplication.shared
        let size = aspect == "1x1" ? CGSize(width: 1080, height: 1080) : CGSize(width: 1920, height: 1080)
        let library = FilmStills(directory: stills)
        var offset = 0.0
        for (name, duration) in scenes {
            defer { offset += duration }
            guard only == "all" || only == name else { continue }
            let dir = "\(out)/\(aspect)/\(name)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let frames = Int((duration * Double(fps)).rounded())
            for n in 0..<frames {
                let t = Double(n) / Double(fps)
                let view = FilmFrame(scene: name, duration: duration, t: t, globalT: offset + t, size: size, stills: library)
                    .frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                renderer.isOpaque = true
                guard let image = renderer.cgImage,
                      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: String(format: "%@/%05d.png", dir, n + 1)) as CFURL,
                                                                        UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
            print("\(aspect) \(name): \(frames) frames")
        }
    }
}

@MainActor
final class FilmStills {
    private let directory: String
    private var cache: [String: NSImage] = [:]
    init(directory: String) { self.directory = directory }

    func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let image = NSImage(contentsOfFile: "\(directory)/\(name).png") else { return nil }
        cache[name] = image
        return image
    }

    /// Logical size in points: panels are drawn at 2x, ears and bubbles at 3x.
    func logicalSize(_ name: String) -> CGSize {
        guard let rep = image(name)?.representations.first else { return .zero }
        let scale: CGFloat = name.hasPrefix("ears") || name.hasPrefix("bubble") ? 3 : 2
        return CGSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
    }
}

// MARK: - Easing

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func ease(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
private func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }
/// A soft spring with a little overshoot; `x` is seconds since the start, it settles in about 0.7 s.
private func spring(_ x: Double) -> Double { x <= 0 ? 0 : x >= 1.4 ? 1 : 1 - exp(-7.5 * x) * cos(9.5 * x) }

// MARK: - Frame

private struct Caption { let lead: String; let accent: String; let from: Double; let to: Double; var mid = false }
private struct PillStep { let name: String; let at: Double }
private struct CursorKey { let t: Double; let x: Double; let y: Double }

private struct FilmFrame: View {
    let scene: String
    let duration: Double
    let t: Double
    let globalT: Double
    let size: CGSize
    let stills: FilmStills

    private let accent = Color(red: 0.98, green: 0.52, blue: 0.3)
    private var k: Double { size.width > size.height ? size.width * 0.78 / 1000 : size.width * 0.94 / 1000 }
    private var notch: CGSize {
        let ears = stills.logicalSize("ears-claude")
        return CGSize(width: max(120, ears.width - 112), height: max(24, ears.height))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            stage
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(camera.zoom, anchor: UnitPoint(x: camera.anchorX, y: 0))
            overlay
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    // MARK: Wallpaper

    private var wallpaper: some View {
        let drift = globalT * 0.05
        return ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.2), Color(red: 0.2, green: 0.08, blue: 0.27)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.25, green: 0.4, blue: 0.95).opacity(0.28)).frame(width: size.width * 0.7).blur(radius: 120)
                .offset(x: cos(drift) * size.width * 0.22 - size.width * 0.15, y: sin(drift) * 120 + size.height * 0.2)
            Circle().fill(Color(red: 0.95, green: 0.35, blue: 0.5).opacity(0.22)).frame(width: size.width * 0.55).blur(radius: 130)
                .offset(x: sin(drift * 1.3) * size.width * 0.2 + size.width * 0.25, y: cos(drift) * 100 + size.height * 0.28)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Camera

    private var camera: (zoom: Double, anchorX: Double) {
        let slow = 1 + 0.015 * (t / duration)
        /// Close on the pill while a bubble or the ears are up, back out when a panel opens.
        func pillZoom(until a: Double) -> Double { 1 + 0.9 * (1 - ease((t - a) / 0.6)) }
        let wide = size.width > size.height
        let boost = wide ? 1.0 : 0.62
        func z(_ v: Double) -> Double { 1 + (v - 1) * boost }
        switch scene {
        case "00_cold": return (z(pillZoom(until: 4.7)) * slow, 0.5)
        case "02_tabs": return (slow + 0.10 * ease((t - 1.6) / 1.4), 0.5 + 0.12 * ease((t - 1.6) / 1.4))
        case "04_claude":
            let push = ease((t - 7.0) / 1.6) * (1 - ease((t - 10.8) / 0.6))
            return (z(pillZoom(until: 5.7)) * (slow + 0.22 * push), 0.5 + 0.2 * push)
        case "05_gmail": return (z(pillZoom(until: 3.3)) * slow, 0.5)
        case "06_ci": return (z(pillZoom(until: 6.2)) * slow, 0.5)
        case "07_meet": return (z(pillZoom(until: 99)) * slow, 0.5)
        default: return (slow, 0.5)
        }
    }

    // MARK: Stage (everything that lives in the notch)

    private var cx: Double { size.width / 2 }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            if camera.zoom < 1.3 { menuBar } else { menuStrip }
            // The physical notch, always there.
            UnevenRoundedRectangle(bottomLeadingRadius: 10 * k, bottomTrailingRadius: 10 * k, style: .continuous)
                .fill(Color.black)
                .frame(width: notch.width * k, height: notch.height * k)
                .position(x: cx, y: notch.height * k / 2)
            content
            cursorLayer
        }
    }

    private var menuStrip: some View {
        let h = notch.height * k
        return Rectangle().fill(Color.black.opacity(0.28)).frame(width: size.width, height: h).position(x: cx, y: h / 2)
    }

    /// A dim menu bar behind the notch, so the top of the screen reads as a Mac.
    private var menuBar: some View {
        let h = notch.height * k
        let f = Font.system(size: 13 * k, weight: .medium)
        return ZStack {
            Rectangle().fill(Color.black.opacity(0.28)).frame(width: size.width, height: h).position(x: cx, y: h / 2)
            HStack(spacing: 22 * k) {
                Text("Finder").font(.system(size: 13 * k, weight: .bold))
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0).font(f) }
            }
            .foregroundColor(.white.opacity(0.75)).position(x: 190 * k, y: h / 2)
            HStack(spacing: 18 * k) {
                Image(systemName: "wifi").font(f)
                Image(systemName: "battery.100").font(f)
                Text("9:41").font(f)
            }
            .foregroundColor(.white.opacity(0.75)).position(x: size.width - 110 * k, y: h / 2)
        }
    }

    @ViewBuilder private var content: some View {
        switch scene {
        case "00_cold":
            pills([PillStep(name: "ears-claude", at: 3.2)], from: 3.2, to: 4.6)
        case "01_switcher":
            panel("dock", open: 0.3, close: 5.5)
        case "02_tabs":
            panel("tabs", open: 0.3, close: 5.4)
        case "03_search":
            ZStack(alignment: .topLeading) {
                panels([PillStep(name: "search_", at: 1.1), PillStep(name: "search_a", at: 2.0), PillStep(name: "search_ap", at: 2.18),
                        PillStep(name: "search_api", at: 2.36)], open: 1.1, close: 4.6)
            }
        case "04_claude":
            ZStack(alignment: .topLeading) {
                pills([PillStep(name: "ears-claude", at: 0.3), PillStep(name: "bubble-claude-approve", at: 3.4)], from: 0.3, to: 5.9)
                panel("claude", open: 6.0, close: 11.0)
            }
        case "05_gmail":
            ZStack(alignment: .topLeading) {
                pills([PillStep(name: "bubble-gmail", at: 0.5), PillStep(name: "bubble-gmail3", at: 2.3)], from: 0.5, to: 3.4)
                panel("gmail", open: 3.5, close: 4.9)
            }
        case "06_ci":
            ZStack(alignment: .topLeading) {
                pills([PillStep(name: "bubble-build-ok", at: 0.4), PillStep(name: "bubble-build-fail", at: 1.9), PillStep(name: "bubble-review", at: 3.4),
                       PillStep(name: "bubble-checks-bad", at: 4.9)], from: 0.4, to: 6.3)
                panel("jenkins", open: 6.4, close: 8.1)
            }
        case "07_meet":
            pills([PillStep(name: "bubble-meeting", at: 0.4), PillStep(name: "bubble-meeting-now", at: 2.4)], from: 0.4, to: 4.2)
        case "08_outro":
            EmptyView()
        default:
            EmptyView()
        }
    }

    /// The open panel; it grows out of the notch and shrinks back into it.
    private func panel(_ name: String, open: Double, close: Double) -> some View {
        panels([PillStep(name: name, at: open)], open: open, close: close)
    }

    private func panels(_ steps: [PillStep], open: Double, close: Double) -> some View {
        let g = openAmount(open: open, close: close)
        let logical = stills.logicalSize(steps[0].name)
        let current = steps.last { t >= $0.at } ?? steps[0]
        return Group {
            if g > 0.001, let image = stills.image(current.name) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: logical.width * k, height: logical.height * k)
                    .opacity(clamp((g - 0.3) / 0.45))
                    .scaleEffect(x: lerp(notch.width / logical.width, 1, g), y: lerp(notch.height / logical.height, 1, g), anchor: .top)
                    .position(x: cx, y: logical.height * k / 2)
                    .shadow(color: .black.opacity(0.45 * g), radius: 40 * k, y: 20 * k)
            }
        }
    }

    /// Ears and bubbles. `steps` swap the pill in place with a short cross-fade.
    private func pills(_ steps: [PillStep], from: Double, to: Double) -> some View {
        let g = openAmount(open: from, close: to, openDuration: 0.5, closeDuration: 0.3)
        let index = steps.lastIndex { t >= $0.at } ?? 0
        let current = steps[index]
        let fade = ease((t - current.at) / 0.12)
        return ZStack(alignment: .topLeading) {
            if g > 0.001 {
                if index > 0 { pill(steps[index - 1], g: g, opacity: 1) }
                pill(current, g: g, opacity: index > 0 ? fade : 1)
            }
        }
    }

    private func pill(_ step: PillStep, g: Double, opacity: Double) -> some View {
        let logical = stills.logicalSize(step.name)
        let bump = step.at > 0 && t >= step.at ? 1 + 0.03 * sin(clamp((t - step.at) / 0.4) * .pi) : 1
        return Group {
            if let image = stills.image(step.name) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: logical.width * k, height: logical.height * k)
                    .scaleEffect(x: lerp(notch.width / logical.width, 1, min(1.06, g)) * bump,
                                 y: lerp(notch.height / logical.height, 1, min(1.06, g)), anchor: .top)
                    .opacity(opacity * clamp(g * 4))
                    .position(x: cx, y: logical.height * k / 2)
            }
        }
    }

    private func openAmount(open: Double, close: Double, openDuration: Double = 0.6, closeDuration: Double = 0.38) -> Double {
        var g = spring((t - open) / openDuration)
        if t > close { g = min(g, 1 - ease((t - close) / closeDuration)) }
        return max(0, g)
    }

    // MARK: Cursor

    private var cursorKeys: [CursorKey] {
        switch scene {
        case "01_switcher": return [CursorKey(t: 1.3, x: 760, y: 90), CursorKey(t: 2.3, x: 330, y: 120), CursorKey(t: 3.4, x: 150, y: 152), CursorKey(t: 4.2, x: 150, y: 152)]
        case "02_tabs": return [CursorKey(t: 1.0, x: 800, y: 60), CursorKey(t: 1.9, x: 330, y: 150), CursorKey(t: 3.0, x: 150, y: 245), CursorKey(t: 4.6, x: 150, y: 245)]
        case "04_claude": return [CursorKey(t: 6.7, x: 850, y: 120), CursorKey(t: 7.6, x: 790, y: 250), CursorKey(t: 10.4, x: 790, y: 250)]
        case "07_meet": return [CursorKey(t: 2.3, x: 800, y: 170), CursorKey(t: 3.3, x: 632, y: 64), CursorKey(t: 4.2, x: 632, y: 64)]
        default: return []
        }
    }
    private var clicks: [Double] {
        switch scene {
        case "01_switcher": return [3.7]
        case "02_tabs": return [3.4]
        case "07_meet": return [3.6]
        default: return []
        }
    }

    private func cursorPoint() -> (x: Double, y: Double)? {
        let keys = cursorKeys
        guard let first = keys.first, let last = keys.last, t >= first.t - 0.2, t <= last.t + 0.6 else { return nil }
        if t <= first.t { return (first.x, first.y) }
        for i in 1..<keys.count where t <= keys[i].t {
            let a = keys[i - 1], b = keys[i], f = ease((t - a.t) / (b.t - a.t))
            return (lerp(a.x, b.x, f), lerp(a.y, b.y, f))
        }
        return (last.x, last.y)
    }

    @ViewBuilder private var cursorLayer: some View {
        if let p = cursorPoint(), let first = cursorKeys.first, let last = cursorKeys.last {
            let alpha = ease((t - (first.t - 0.2)) / 0.2) * (1 - ease((t - last.t) / 0.5))
            let press = clicks.contains { t >= $0 && t < $0 + 0.15 } ? 0.88 : 1
            let tip = CGPoint(x: cx + (p.x - 500) * k, y: p.y * k)
            ZStack {
                ForEach(clicks, id: \.self) { c in
                    let f = clamp((t - c) / 0.5)
                    if f > 0 && f < 1 {
                        Circle().stroke(Color.white.opacity(0.8 * (1 - f)), lineWidth: 3 * k)
                            .frame(width: 70 * k * f + 8, height: 70 * k * f + 8)
                            .position(x: tip.x, y: tip.y)
                    }
                }
                CursorArrow()
                    .fill(Color.white).overlay(CursorArrow().stroke(Color.black, lineWidth: 1.4))
                    .frame(width: 22 * k, height: 32 * k)
                    .scaleEffect(press, anchor: .topLeading)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                    .position(x: tip.x + 11 * k, y: tip.y + 16 * k)
            }
            .opacity(alpha)
        }
    }

    // MARK: Overlay (canvas space: captions, keys, outro)

    private var captions: [Caption] {
        switch scene {
        case "00_cold": return [Caption(lead: "your notch is ", accent: "wasted space.", from: 0.4, to: 2.9, mid: true), Caption(lead: "until ", accent: "now.", from: 3.0, to: 4.7, mid: true)]
        case "01_switcher": return [Caption(lead: "every window. ", accent: "one hover.", from: 1.0, to: 5.6)]
        case "02_tabs": return [Caption(lead: "tabs ", accent: "you can actually find.", from: 0.9, to: 5.5)]
        case "03_search": return [Caption(lead: "search ", accent: "everything.", from: 2.4, to: 5.0)]
        case "04_claude": return [Caption(lead: "claude is ", accent: "cooking.", from: 0.5, to: 3.2, mid: true), Caption(lead: "it tells you when it ", accent: "needs ur ok.", from: 3.5, to: 5.7, mid: true),
                                  Caption(lead: "your usage, ", accent: "roasted.", from: 6.6, to: 11.2)]
        case "05_gmail": return [Caption(lead: "mail, ", accent: "without opening mail.", from: 0.7, to: 3.4, mid: true)]
        case "06_ci": return [Caption(lead: "builds. reviews. ", accent: "checks.", from: 0.4, to: 6.2, mid: true), Caption(lead: "it all ", accent: "finds you.", from: 6.5, to: 8.2)]
        case "07_meet": return [Caption(lead: "never ", accent: "late again.", from: 0.8, to: 4.2, mid: true)]
        default: return []
        }
    }

    private var overlay: some View {
        ZStack {
            ForEach(Array(captions.enumerated()), id: \.offset) { _, c in captionView(c) }
            if scene == "03_search" { keycaps }
            if scene == "08_outro" { outro }
        }
        .frame(width: size.width, height: size.height)
    }

    private func captionView(_ c: Caption) -> some View {
        let inn = ease((t - c.from) / 0.35), out = ease((t - c.to) / 0.25)
        let alpha = inn * (1 - out)
        let font = Font.system(size: size.width > size.height ? (c.mid ? 84 : 68) : (c.mid ? 70 : 58), weight: .bold, design: .rounded)
        return (Text(c.lead).foregroundColor(.white) + Text(c.accent).foregroundColor(accent))
            .font(font)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
            .multilineTextAlignment(.center)
            .frame(width: size.width * 0.92)
            .opacity(alpha)
            .scaleEffect(0.96 + 0.04 * inn)
            .offset(y: (1 - inn) * 18)
            .position(x: size.width / 2, y: c.mid ? size.height * 0.56 : size.height - (size.width > size.height ? 150 : 130))
    }

    private var keycaps: some View {
        let keys = ["\u{2303}", "\u{2325}", "space"]
        let appear = ease((t - 0.2) / 0.3), gone = ease((t - 1.3) / 0.3)
        let unit = size.width > size.height ? 1.0 : 0.8
        return HStack(spacing: 22 * unit) {
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                let pressed = clamp((t - (0.65 + 0.12 * Double(i))) / 0.1)
                Text(key).font(.system(size: key == "space" ? 40 : 64, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: (key == "space" ? 300 : 130) * unit, height: 130 * unit)
                    .background(RoundedRectangle(cornerRadius: 26 * unit, style: .continuous)
                        .fill(Color.white.opacity(0.14 + 0.16 * pressed))
                        .overlay(RoundedRectangle(cornerRadius: 26 * unit, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 2)))
                    .scaleEffect(1 - 0.07 * pressed)
                    .offset(y: 8 * pressed)
            }
        }
        .opacity(appear * (1 - gone))
        .offset(y: (1 - appear) * 30)
        .position(x: size.width / 2, y: size.height * 0.46)
    }

    private var outro: some View {
        let moods = Mood.allCases
        let tints: [Mood: Color] = [.sleepy: Color(white: 0.7), .working: accent, .thinking: accent, .needsYou: accent, .happy: .green, .proud: .green,
                                    .sad: .red, .excited: Color(red: 0.92, green: 0.3, blue: 0.25), .alert: .purple, .clockWatching: .blue, .shocked: .red]
        let wide = size.width > size.height
        let buddy = wide ? 92.0 : 60.0
        let title = ease((t - 1.5) / 0.5), tag = ease((t - 2.2) / 0.5), foot = ease((t - 3.0) / 0.5)
        return ZStack {
            HStack(spacing: wide ? 26 : 12) {
                ForEach(Array(moods.enumerated()), id: \.offset) { i, mood in
                    let appear = spring((t - 0.1 - Double(i) * 0.09) / 0.7)
                    BuddyView(mood: mood, tint: tints[mood] ?? accent, size: buddy, fixedTime: globalT + Double(i) * 0.43)
                        .scaleEffect(max(0, appear))
                        .offset(y: (1 - min(1, appear)) * 40)
                }
            }
            .position(x: size.width / 2, y: size.height * (wide ? 0.34 : 0.3))
            Text("Notch Hub").font(.system(size: wide ? 150 : 104, weight: .heavy, design: .rounded)).foregroundColor(.white)
                .opacity(title).offset(y: (1 - title) * 24)
                .position(x: size.width / 2, y: size.height * 0.56)
            (Text("your notch finally has ").foregroundColor(.white.opacity(0.85)) + Text("a job.").foregroundColor(accent))
                .font(.system(size: wide ? 54 : 40, weight: .bold, design: .rounded))
                .opacity(tag).offset(y: (1 - tag) * 18)
                .position(x: size.width / 2, y: size.height * 0.69)
            Text("for Mac")
                .font(.system(size: wide ? 30 : 24, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 26).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .opacity(foot)
                .position(x: size.width / 2, y: size.height * 0.8)
        }
    }
}

private struct CursorArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 0, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.26, y: h * 0.66))
        p.addLine(to: CGPoint(x: w * 0.46, y: h * 1.0))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.6))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.58))
        p.closeSubpath()
        return p
    }
}

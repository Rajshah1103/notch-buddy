// Generates Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: the artwork sits inside the canvas with room for a soft shadow.
    let tile = CGRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: s * 0.185, yRadius: s * 0.185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); squircle.fill()
    ctx.restoreGState()

    squircle.addClip()
    NSGradient(colors: [NSColor(red: 0.30, green: 0.36, blue: 0.62, alpha: 1), NSColor(red: 0.10, green: 0.10, blue: 0.20, alpha: 1)])!
        .draw(in: tile, angle: -60)

    // The open notch: black, flared at the top, rounded at the bottom, hanging from the top edge.
    let w = tile.width * 0.74, h = tile.height * 0.52
    let x0 = tile.midX - w / 2, top = tile.maxY
    let flare = tile.width * 0.035, r = tile.width * 0.10
    let path = NSBezierPath()
    path.move(to: CGPoint(x: x0 - flare, y: top))
    path.line(to: CGPoint(x: x0 + w + flare, y: top))
    path.curve(to: CGPoint(x: x0 + w, y: top - flare), controlPoint1: CGPoint(x: x0 + w, y: top), controlPoint2: CGPoint(x: x0 + w, y: top))
    path.line(to: CGPoint(x: x0 + w, y: top - h + r))
    path.curve(to: CGPoint(x: x0 + w - r, y: top - h), controlPoint1: CGPoint(x: x0 + w, y: top - h + r * 0.45), controlPoint2: CGPoint(x: x0 + w - r * 0.45, y: top - h))
    path.line(to: CGPoint(x: x0 + r, y: top - h))
    path.curve(to: CGPoint(x: x0, y: top - h + r), controlPoint1: CGPoint(x: x0 + r * 0.45, y: top - h), controlPoint2: CGPoint(x: x0, y: top - h + r * 0.45))
    path.line(to: CGPoint(x: x0, y: top - flare))
    path.curve(to: CGPoint(x: x0 - flare, y: top), controlPoint1: CGPoint(x: x0, y: top), controlPoint2: CGPoint(x: x0, y: top))
    path.close()
    NSColor(white: 0.04, alpha: 1).setFill(); path.fill()

    // Four app tiles inside it: what the notch switches between.
    let colors: [NSColor] = [
        NSColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1), NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1),
        NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1), NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1),
    ]
    let side = w * 0.17, gap = w * 0.05
    let rowWidth = side * 4 + gap * 3
    let rowX = tile.midX - rowWidth / 2, rowY = top - h * 0.62
    for (i, color) in colors.enumerated() {
        let rect = CGRect(x: rowX + CGFloat(i) * (side + gap), y: rowY, width: side, height: side)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: side * 0.28, yRadius: side * 0.28).fill()
    }
    image.unlockFocus()

    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                     ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
print("iconset written")

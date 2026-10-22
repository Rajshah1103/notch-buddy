import AppKit
import NotchCore
import SwiftUI
import WindowEngine

struct WindowsView: View {
    @ObservedObject var model: WindowsModel
    let notch: NotchState

    var body: some View {
        VStack(spacing: 0) {
            header(notch.geometry)
            cards
            PermissionHint(model: model)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)   // clear the flared top corners
    }

    // MARK: - Header (the "ears" beside the hardware notch)

    @ViewBuilder
    private func header(_ g: NotchGeometry) -> some View {
        if g.hasNotch {
            HStack(spacing: 0) {
                SpaceDots(spaces: model.snapshot.spaces)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                Color.clear.frame(width: g.collapsedSize.width)
                Text(summary)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
            }
            .frame(height: g.collapsedSize.height)
        } else {
            Color.clear.frame(height: 14)
        }
    }

    private var summary: String {
        let count = model.snapshot.spaces.reduce(0) { $0 + $1.windows.count } + model.snapshot.minimized.count
        return count == 1 ? "1 window" : "\(count) windows"
    }

    // MARK: - Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(model.snapshot.spaces.enumerated()), id: \.element.id) { index, space in
                        Card(title: "Desktop \(space.index)", symbol: nil, isCurrent: space.isCurrent,
                             count: space.windows.count) {
                            ForEach(space.windows) { window in
                                WindowTile(model: model, pid: window.pid, appName: window.appName,
                                           title: window.title, windowID: window.id) {
                                    model.focus(window, in: space)
                                    notch.collapse()
                                }
                            }
                        }
                        .id(space.id)
                    }
                    if !model.snapshot.minimized.isEmpty {
                        Card(title: "Minimized", symbol: "arrow.down.right.and.arrow.up.left", isCurrent: false,
                             count: model.snapshot.minimized.count) {
                            ForEach(model.snapshot.minimized) { window in
                                WindowTile(model: model, pid: window.pid, appName: window.appName,
                                           title: window.title, windowID: window.id) {
                                    model.focus(window, in: nil)
                                    notch.collapse()
                                }
                            }
                        }
                    }
                    if !model.snapshot.windowlessApps.isEmpty {
                        Card(title: "No windows", symbol: "macwindow.badge.plus", isCurrent: false,
                             count: model.snapshot.windowlessApps.count) {
                            ForEach(model.snapshot.windowlessApps) { app in
                                WindowTile(model: model, pid: app.pid, appName: app.name,
                                           title: "", windowID: nil) {
                                    model.open(app)
                                    notch.collapse()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 4)
            }
            .mask(EdgeFade())
            .onAppear {
                if let current = model.snapshot.spaces.first(where: \.isCurrent) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Card

private struct Card<Content: View>: View {
    let title: String
    let symbol: String?
    let isCurrent: Bool
    let count: Int
    @ViewBuilder let content: Content

    private var columns: Int { min(2, max(1, count)) }
    private var width: CGFloat {
        CGFloat(columns) * Theme.tileWidth + CGFloat(columns - 1) * Theme.tileGap + Theme.cardPadding * 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if isCurrent {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                }
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 11, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: false) {
                FlowGrid(columns: columns) { content }
            }
        }
        .padding(Theme.cardPadding)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isCurrent ? Theme.currentEdge : Theme.cardEdge, lineWidth: isCurrent ? 1.25 : 0.5)
        )
    }
}

/// Lays children out in fixed-width columns without LazyVGrid's overhead (cards hold few tiles).
private struct FlowGrid: Layout {
    let columns: Int

    private func rows(_ subviews: Subviews) -> Int { (subviews.count + columns - 1) / columns }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let tile = subviews[0].sizeThatFits(.unspecified)
        let r = CGFloat(rows(subviews))
        return CGSize(width: CGFloat(columns) * tile.width + CGFloat(columns - 1) * Theme.tileGap,
                      height: r * tile.height + (r - 1) * Theme.tileGap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let tile = subviews[0].sizeThatFits(.unspecified)
        for (i, view) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(i % columns) * (tile.width + Theme.tileGap)
            let y = bounds.minY + CGFloat(i / columns) * (tile.height + Theme.tileGap)
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(tile))
        }
    }
}

// MARK: - Tile

private struct WindowTile: View {
    @ObservedObject var model: WindowsModel
    let pid: Int32
    let appName: String
    let title: String
    let windowID: UInt32?
    let action: () -> Void

    var body: some View {
        let icon = model.icons[pid]
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                preview(icon: icon)
                    .frame(width: Theme.tileWidth, height: Theme.tileHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                HStack(spacing: 5) {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 14, height: 14)
                    }
                    Text(title.isEmpty ? appName : title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .frame(width: Theme.tileWidth, alignment: .leading)
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(title.isEmpty ? appName : "\(appName), \(title)")
        .accessibilityHint("Switch to this window")
    }

    @ViewBuilder
    private func preview(icon: NSImage?) -> some View {
        if let windowID, let thumb = model.thumbnails[windowID] {
            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
        } else {
            // No preview (no Screen Recording, or the window is on another Desktop): quiet tile + icon.
            ZStack {
                LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom)
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 44, height: 44)
                }
            }
        }
    }
}

/// Press feedback starts on mouse-down. Hover lights the tile's edge with the accent color.
private struct TileButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: Theme.tileWidth, height: Theme.tileHeight)
                    .opacity(hovering || configuration.isPressed ? 1 : 0)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

// MARK: - Pieces

/// One capsule per Desktop; the current one stretches.
private struct SpaceDots: View {
    let spaces: [SpaceInfo]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(spaces) { space in
                Capsule()
                    .fill(space.isCurrent ? Theme.accent : Color.white.opacity(0.28))
                    .frame(width: space.isCurrent ? 16 : 5, height: 5)
            }
        }
    }
}

/// Fades the scroll edges instead of drawing a hard divider.
private struct EdgeFade: View {
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 28)
        }
    }
}

private struct PermissionHint: View {
    @ObservedObject var model: WindowsModel

    var body: some View {
        if !model.accessibilityGranted {
            hint("Allow Accessibility to jump between windows", action: Permissions.requestAccessibility)
        } else if !model.screenRecordingGranted {
            hint("Allow Screen Recording for live window previews", action: Permissions.requestScreenRecording)
        }
    }

    private func hint(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 11, weight: .medium))
                Text(text).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

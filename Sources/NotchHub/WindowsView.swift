import AppKit
import NotchCore
import SwiftUI
import WindowEngine

struct WindowsView: View {
    @ObservedObject var model: WindowsModel
    let notch: NotchState

    var body: some View {
        let geometry = notch.geometry
        VStack(spacing: 0) {
            header(geometry)
            cards
            PermissionHint(model: model)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Header (the "ears" beside the hardware notch)

    @ViewBuilder
    private func header(_ g: NotchGeometry) -> some View {
        if g.hasNotch {
            HStack(spacing: 0) {
                SpaceDots(spaces: model.snapshot.spaces)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
                Color.clear.frame(width: g.collapsedSize.width)
                Text(summary)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
            .frame(height: g.collapsedSize.height)
        } else {
            Color.clear.frame(height: 14)
        }
    }

    private var summary: String {
        let windows = model.snapshot.spaces.reduce(0) { $0 + $1.windows.count } + model.snapshot.minimized.count
        return "\(windows) windows"
    }

    // MARK: - Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(model.snapshot.spaces.enumerated()), id: \.element.id) { index, space in
                        Card(title: "Desktop \(space.index)", symbol: nil, isCurrent: space.isCurrent,
                             count: space.windows.count, tiles: space.windows.count) {
                            ForEach(space.windows) { window in
                                WindowTile(model: model, pid: window.pid, appName: window.appName,
                                           title: window.title, windowID: window.id) {
                                    model.focus(window, in: space)
                                    notch.collapse()
                                }
                            }
                        }
                        .reveal(index: index)
                        .id(space.id)
                    }
                    if !model.snapshot.minimized.isEmpty {
                        Card(title: "Minimized", symbol: "dock.rectangle", isCurrent: false,
                             count: model.snapshot.minimized.count, tiles: model.snapshot.minimized.count) {
                            ForEach(model.snapshot.minimized) { window in
                                WindowTile(model: model, pid: window.pid, appName: window.appName,
                                           title: window.title, windowID: window.id) {
                                    model.focus(window, in: nil)
                                    notch.collapse()
                                }
                            }
                        }
                        .reveal(index: model.snapshot.spaces.count)
                    }
                    if !model.snapshot.windowlessApps.isEmpty {
                        Card(title: "No window", symbol: "app.dashed", isCurrent: false,
                             count: model.snapshot.windowlessApps.count, tiles: model.snapshot.windowlessApps.count) {
                            ForEach(model.snapshot.windowlessApps) { app in
                                WindowTile(model: model, pid: app.pid, appName: app.name,
                                           title: "", windowID: nil) {
                                    model.open(app)
                                    notch.collapse()
                                }
                            }
                        }
                        .reveal(index: model.snapshot.spaces.count + 1)
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
    let tiles: Int
    @ViewBuilder let content: Content

    private var columns: Int { min(2, max(1, tiles)) }
    private var gridWidth: CGFloat {
        CGFloat(columns) * Theme.tileWidth + CGFloat(columns - 1) * Theme.tileGap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if isCurrent {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        .shadow(color: Theme.accent.opacity(0.8), radius: 4)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(Theme.tileWidth), spacing: Theme.tileGap),
                                         count: columns),
                          spacing: Theme.tileGap) {
                    content
                }
                .padding(.bottom, 14)
            }
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                }
            )
        }
        .padding(Theme.cardPadding)
        .frame(width: gridWidth + Theme.cardPadding * 2)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isCurrent ? Theme.currentEdge : Theme.cardEdge, lineWidth: isCurrent ? 1 : 0.5)
        )
        .shadow(color: isCurrent ? Theme.accent.opacity(0.22) : .clear, radius: 14)
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                preview
                    .frame(width: Theme.tileWidth, height: Theme.tileHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                Text(title.isEmpty ? appName : title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
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
    private var preview: some View {
        let icon = model.icons[pid]
        if let windowID, let thumb = model.thumbnails[windowID] {
            ZStack(alignment: .bottomLeading) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .padding(6)
                }
            }
        } else {
            // No thumbnail (no Screen Recording, or the window is on another Desktop): quiet tile + icon.
            ZStack {
                LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom)
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                }
            }
        }
    }
}

/// Press feedback starts on mouse-down. Hover lifts the tile slightly and lights its edge.
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
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : (hovering ? 1.02 : 1)))
            .animation(Theme.easeOut, value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

// MARK: - Pieces

/// One capsule per Space; the current one stretches. Springs retarget smoothly if Spaces change.
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
        .animation(.spring(response: 0.3, dampingFraction: 1), value: spaces.map(\.isCurrent))
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

private struct Reveal: ViewModifier {
    let index: Int
    @State private var shown = Theme.skipReveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .onAppear {
                // Short stagger: it is decorative and must never feel like waiting.
                withAnimation(Theme.easeOut.delay(Double(min(index, 5)) * 0.03)) { shown = true }
            }
    }
}

private extension View {
    func reveal(index: Int) -> some View { modifier(Reveal(index: index)) }
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

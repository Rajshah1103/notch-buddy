import AppKit
import Combine
import NotchCore
import SwiftUI
import WindowEngine

/// Apps first, then what is inside the selected app. Everything fits on screen: no scrolling.
struct SwitcherView: View {
    @ObservedObject var model: WindowsModel
    let notch: NotchState

    @State private var selectedID: Int32?
    /// Only the preview pane observes this, so moving across rows does not re-render the list.
    @StateObject private var hover = HoverStore()

    private var selected: AppGroup? {
        if let selectedID, let group = model.groups.first(where: { $0.id == selectedID }) { return group }
        return model.groups.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ears(notch.geometry)
            AppDock(groups: model.groups, icons: model.icons, selectedID: selected?.id,
                    onSelect: { selectedID = $0 }, onOpen: open)
                .padding(.top, 6)
            if let group = selected {
                Detail(model: model, group: group, hover: hover, onOpen: open)
                    .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) { Hint(model: model).padding(.bottom, 8) }
        .onReceive(notch.$isExpanded) { expanded in
            // Start each visit from the default: the app you are in, nothing hovered.
            if !expanded { selectedID = nil; hover.entry = nil }
        }
    }

    private func open(_ entry: Entry) {
        model.perform(entry)
        notch.collapse()
    }

    // MARK: - Header beside the hardware notch

    @ViewBuilder
    private func ears(_ g: NotchGeometry) -> some View {
        if g.hasNotch {
            HStack(spacing: 0) {
                Group {
                    // Full-screen apps get their own Space but are not Desktops; they are reached
                    // from the app row. Pills only appear when there is more than one Desktop.
                    let desktops = model.snapshot.spaces.filter { $0.kind == .desktop }
                    if desktops.count > 1 {
                        DesktopPills(spaces: desktops) { space in
                            model.switchTo(space)
                            notch.collapse()
                        }
                    }
                }
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
        let open = model.groups.flatMap(\.entries).filter { entry in
            if case .launch = entry.target { return false }
            return true
        }.count
        return "\(model.groups.count) apps · \(open) open"
    }
}

enum Layout {
    /// Height of the list area: the panel (440) minus the notch strip, app row, title and padding.
    static let listHeight: CGFloat = 288
}

/// The entry under the pointer. Kept out of SwiftUI state on the big views on purpose.
@MainActor
private final class HoverStore: ObservableObject {
    @Published var entry: Entry?
}

// MARK: - App row

private struct AppDock: View {
    let groups: [AppGroup]
    let icons: [Int32: NSImage]
    let selectedID: Int32?
    let onSelect: (Int32) -> Void
    let onOpen: (Entry) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(groups) { group in
                DockItem(group: group, icon: icons[group.pid], isSelected: group.id == selectedID,
                         onHover: { onSelect(group.id) },
                         onOpen: { if let entry = group.primary { onOpen(entry) } })
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DockItem: View {
    let group: AppGroup
    let icon: NSImage?
    let isSelected: Bool
    let onHover: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Color.clear }
                }
                .frame(width: 38, height: 38)
                .frame(width: 54, height: 54)

                if group.entries.count > 1 {
                    Text("\(group.entries.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(Theme.accent))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: 2, y: 2)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Theme.fillSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { if $0 { onHover() } }
        .accessibilityLabel(group.name)
        .accessibilityHint("Open \(group.name)")
    }
}

/// Feedback begins on mouse-down, not on release.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Detail: list on the left, preview on the right

private struct Detail: View {
    @ObservedObject var model: WindowsModel
    let group: AppGroup
    let hover: HoverStore
    let onOpen: (Entry) -> Void


    private var items: [PackItem<Entry>] {
        group.entries.flatMap { entry -> [PackItem<Entry>] in
            entry.section.map { [.header($0), .entry(entry)] } ?? [.entry(entry)]
        }
    }

    /// Row 34 + 2 spacing; heading 26 + 2 spacing. The height fits inside the panel under the app
    /// row, with room left for the "+N more" row. A long list trades the preview pane for a third
    /// column so more fits on screen without scrolling.
    private func pack() -> (PackedColumns<Entry>, wide: Bool) {
        let narrow = ColumnPacker.pack(items, columnHeight: Layout.listHeight, headerCost: 28, rowCost: 36, maxColumns: 2)
        guard narrow.overflow > 0 else { return (narrow, false) }
        return (ColumnPacker.pack(items, columnHeight: Layout.listHeight, headerCost: 28, rowCost: 36, maxColumns: 3), true)
    }

    var body: some View {
        let (packed, wide) = pack()
        let columnWidth: CGFloat = wide ? 300 : 292

        VStack(alignment: .leading, spacing: 8) {
            title
            HStack(alignment: .top, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(packed.columns.enumerated()), id: \.offset) { index, column in
                        VStack(spacing: 2) {
                            ForEach(Array(column.enumerated()), id: \.offset) { _, item in
                                switch item {
                                case .header(let text): SectionHeader(text: text)
                                case .entry(let entry):
                                    EntryRow(entry: entry, icon: model.icons[group.pid],
                                             onHover: { hover.entry = entry }, onOpen: { onOpen(entry) })
                                }
                            }
                            if packed.overflow > 0 && index == packed.columns.count - 1 {
                                Text("+\(packed.overflow) more")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: columnWidth)
                    }
                }
                if !wide { PreviewHost(model: model, hover: hover, group: group) }
            }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Text(group.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var subtitle: String {
        let n = group.entries.count
        if group.isBrowserWithTabs {
            let windows = Set(group.entries.compactMap(\.section)).count
            return "\(n) tabs in \(windows) window\(windows == 1 ? "" : "s")"
        }
        if case .launch = group.entries.first?.target { return "No windows open" }
        return "\(n) window\(n == 1 ? "" : "s")"
    }
}

/// Shows the hovered entry, or the group's main one when nothing is hovered.
private struct PreviewHost: View {
    @ObservedObject var model: WindowsModel
    @ObservedObject var hover: HoverStore
    let group: AppGroup

    var body: some View {
        if let entry = hover.entry ?? group.primary {
            PreviewPane(entry: entry, icon: model.icons[group.pid],
                        thumbnail: entry.thumbnailWindowID.flatMap { model.thumbnails[$0] })
        }
    }
}

private struct SectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .frame(height: 26, alignment: .bottomLeading)
    }
}

private struct EntryRow: View {
    let entry: Entry
    let icon: NSImage?
    let onHover: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Leading(entry: entry, icon: icon, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !entry.subtitle.isEmpty {
                        Text(entry.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if entry.isActive {
                    // The tab or window currently in front.
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovered ? Theme.fillHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
        .accessibilityLabel(entry.title)
        .accessibilityHint("Switch to this \(entry.url.isEmpty ? "window" : "tab")")
    }
}

/// App icon for windows; a colored monogram of the site for tabs, so tabs are told apart at a glance.
private struct Leading: View {
    let entry: Entry
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        if entry.url.isEmpty {
            Group {
                if let icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: size, height: size)
        } else {
            Monogram(host: entry.subtitle, size: size)
        }
    }
}

private struct Monogram: View {
    let host: String
    let size: CGFloat

    private var letter: String { host.first.map { String($0).uppercased() } ?? "•" }

    /// Same site, same color, every time.
    private var color: Color {
        var hash: UInt32 = 5381
        for byte in host.utf8 { hash = hash &* 33 &+ UInt32(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.5, brightness: 0.62)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
            )
    }
}

// MARK: - Preview pane: which one am I about to open?

private struct PreviewPane: View {
    let entry: Entry
    let icon: NSImage?
    let thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Theme.fillQuiet
                    Leading(entry: entry, icon: icon, size: 52)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))

            Text(entry.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 3) {
                if !entry.url.isEmpty {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text(location)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 300)
    }

    /// "github.com/acme/api/pull/482": the address without the scheme noise.
    private var address: String {
        entry.url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
    }

    /// "Desktop 3 · Tab 4 of 9 · Showing now": where it is, in the words a person would use.
    private var location: String {
        [entry.place.label, entry.detail, entry.isActive && !entry.url.isEmpty ? "Showing now" : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Desktop pills

/// Click a number to jump straight to that Desktop. Replaces the swipe.
private struct DesktopPills: View {
    let spaces: [SpaceInfo]
    let onSelect: (SpaceInfo) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(spaces) { space in
                Pill(number: space.index, isCurrent: space.isCurrent) { onSelect(space) }
            }
        }
    }

    private struct Pill: View {
        let number: Int
        let isCurrent: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.white : Theme.textSecondary)
                    .frame(width: 22, height: 20)
                    .background(
                        Capsule().fill(isCurrent ? Theme.accent : (hovering ? Theme.fillHover : Color.clear))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .onHover { hovering = $0 }
            .accessibilityLabel("Desktop \(number)")
        }
    }
}

// MARK: - Permission hints

private struct Hint: View {
    @ObservedObject var model: WindowsModel

    var body: some View {
        if !model.accessibilityGranted {
            hint("Allow Accessibility to jump between windows", action: Permissions.requestAccessibility)
        } else if !model.browsersNeedingAccess.isEmpty {
            hint("Allow Automation to see your browser tabs", action: Permissions.openAutomationSettings)
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

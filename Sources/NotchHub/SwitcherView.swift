import AppKit
import Combine
import NotchCore
import SwiftUI
import WindowEngine

/// Apps first, then what is inside the selected app. Everything fits on screen: no scrolling.
struct SwitcherView: View {
    @ObservedObject var model: WindowsModel
    @ObservedObject var hub: IntegrationHub
    @ObservedObject var web: WebBrowser
    @ObservedObject var learning: LearningStore
    let notch: NotchState

    @State private var selectedID: Int32?
    @State private var resetWork: DispatchWorkItem?
    @State private var pendingReset = false
    /// Only the preview pane observes this, so moving across rows does not re-render the list.
    @StateObject private var hover = HoverStore()
    /// Hit testing for hover: see PointerHover.swift.
    @StateObject private var pointer = HoverHub()

    /// The integration whose panel replaces the app list, if any.
    @State private var openIntegration: String? = PreviewSeed.integration
    @State private var searching = false
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var selected: AppGroup? {
        if let selectedID, let group = model.groups.first(where: { $0.id == selectedID }) { return group }
        return model.groups.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ears(notch.geometry)
            if searching {
                SearchPanel(model: model, web: web, learning: learning, settings: .shared, query: $query,
                            selection: $selection, focus: $fieldFocused, onOpen: { open($0, query: query) },
                            onWeb: { action, profile in
                                web.open(action.url, in: profile)
                                notch.collapse()
                            },
                            onClose: { notch.collapse() })
                    .padding(.top, 8)
            } else if let id = openIntegration, let integration = hub.integration(id) {
                integration.panel(notch: notch).padding(.top, 10)
            } else {
                AppDock(groups: model.groups, icons: model.icons, selectedID: selected?.id,
                        onSelect: { selectedID = $0 }, onOpen: { open($0) }, onSearch: { notch.setSearching(true) })
                    .padding(.top, 6)
                if let group = selected {
                    Detail(model: model, group: group, hover: hover, onOpen: { open($0) })
                        .padding(.top, 10)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .overlay(alignment: .bottom) { Hint(model: model).padding(.bottom, 8) }
        .environment(\.hoverHub, pointer)
        .coordinateSpace(name: "notch")
        .onAppear { notch.pointerHandler = { [pointer] in pointer.pointerMoved($0) } }
        .onReceive(notch.$isExpanded) { expanded in
            // Start each visit from the default: the app you are in, nothing hovered. The reset waits
            // until the content has faded out, because laying the pane out again while the notch is
            // closing drops a frame. Reopening early does the pending reset first.
            resetWork?.cancel()
            let reset = { selectedID = nil; hover.entry = nil; openIntegration = nil }
            if expanded {
                if pendingReset { reset(); pendingReset = false }
            } else {
                pendingReset = true
                let work = DispatchWorkItem { reset(); pendingReset = false }
                resetWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        }
        .onReceive(notch.$isSearching) { isSearching in
            searching = isSearching
            if isSearching {
                query = PreviewSeed.query ?? ""
                selection = 0
                // The panel becomes key a moment after it opens; focus the field once it has.
                DispatchQueue.main.async { fieldFocused = true }
            } else {
                fieldFocused = false
            }
        }
    }

    private func open(_ entry: Entry, query: String = "") {
        if let group = model.groups.first(where: { $0.entries.contains(entry) }) {
            learning.record(entry, appName: group.name, query: query)
        }
        model.perform(entry)
        notch.collapse()
    }

    // MARK: - Header beside the hardware notch

    @ViewBuilder
    private func ears(_ g: NotchGeometry) -> some View {
        if g.hasNotch {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    // Full-screen apps get their own Space but are not Desktops; they are reached
                    // from the app row. Pills only appear when there is more than one Desktop.
                    let desktops = model.snapshot.spaces.filter { $0.kind == .desktop }
                    if desktops.count > 1 {
                        DesktopPills(spaces: desktops) { space in
                            model.switchTo(space)
                            notch.collapse()
                        }
                    }
                    ForEach(hub.visible, id: \.id) { integration in
                        integration.chip(isOpen: openIntegration == integration.id && !searching) {
                            // A panel can't show under the search box: end the search first, and open
                            // the panel even if it was the one selected before searching began.
                            if searching { notch.setSearching(false); openIntegration = integration.id; return }
                            openIntegration = openIntegration == integration.id ? nil : integration.id
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
                Color.clear.frame(width: g.collapsedSize.width)
                HStack(spacing: 10) {
                    SearchButton { notch.setSearching(true) }
                    Text(summary)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
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

/// Lets the snapshot tool start the search view with text already typed.
enum PreviewSeed {
    nonisolated(unsafe) static var query: String?
    nonisolated(unsafe) static var integration: String?
    /// Title of an entry to show in the preview pane as if hovered.
    nonisolated(unsafe) static var hoverTitle: String?
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
    let onSearch: () -> Void

    private let fullSlot: CGFloat = 60       // icon tile plus gap at normal size
    private let smallestSlot: CGFloat = 36   // below this icons stop being recognisable

    var body: some View {
        GeometryReader { proxy in
            // Everything must fit on one row without scrolling: shrink the icons first, and only when even
            // the smallest no longer fits, show as many as will and hand the rest to search.
            let capacity = max(1, Int(proxy.size.width / smallestSlot))
            let overflow = groups.count > capacity
            let shown = overflow ? Array(groups.prefix(capacity - 1)) : groups
            let slots = shown.count + (overflow ? 1 : 0)
            let slot = min(fullSlot, proxy.size.width / CGFloat(max(slots, 1)))
            HStack(spacing: 0) {
                ForEach(shown) { group in
                    DockItem(group: group, icon: icons[group.pid], isSelected: group.id == selectedID, slot: slot,
                             onHover: { onSelect(group.id) },
                             onOpen: { if let entry = group.primary { onOpen(entry) } })
                }
                if overflow {
                    Button(action: onSearch) {
                        Text("+\(groups.count - shown.count)")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: slot, height: slot)
                            .background(RoundedRectangle(cornerRadius: slot * 0.28, style: .continuous).fill(Theme.fillQuiet))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(groups.count - shown.count) more apps")
                    .accessibilityHint("Opens search")
                }
            }
            .frame(width: proxy.size.width)
        }
        .frame(height: 54)
    }
}

private struct DockItem: View {
    let group: AppGroup
    let icon: NSImage?
    let isSelected: Bool
    let slot: CGFloat
    let onHover: () -> Void
    let onOpen: () -> Void

    var body: some View {
        // At full size (slot 60) the icon is 38 points in a 54-point tile; it scales down with the slot.
        let tile = slot * 0.9
        let iconSize = tile * 0.70
        Button(action: onOpen) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Color.clear }
                }
                .frame(width: iconSize, height: iconSize)
                .frame(width: tile, height: tile)

                if group.entries.count > 1 {
                    Text("\(group.entries.count)")
                        .font(.system(size: slot < 46 ? 9 : 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Theme.accent))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: 2, y: 2)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: tile * 0.3, style: .continuous)
                    .fill(isSelected ? Theme.fillSelected : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .frame(width: slot)
        .pointerHover { if $0 { onHover() } }
        .contextMenu {
            Button("Hide \(group.name) from Notch Hub") {
                AppSettings.shared.hiddenApps.insert(group.bundleID ?? group.name)
            }
        }
        .accessibilityLabel(group.name)
        .accessibilityHint("Open \(group.name)")
    }
}

/// Feedback begins on mouse-down, not on release.
struct PressStyle: ButtonStyle {
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
        let columnWidth: CGFloat = wide ? 300 : 290

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
                                             onClose: entry.isClosable ? { model.close(entry) } : nil,
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
                if !wide { PreviewHost(model: model, hover: hover, group: group, width: packed.columns.count == 1 ? 560 : 338) }
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
    let width: CGFloat

    var body: some View {
        let seeded = PreviewSeed.hoverTitle.flatMap { title in group.entries.first { $0.title == title } }
        if let entry = hover.entry ?? seeded ?? group.primary {
            let remembered = model.tabShot(for: entry)
            PreviewPane(entry: entry, icon: model.icons[group.pid],
                        thumbnail: entry.thumbnailWindowID.flatMap { model.thumbnails[$0] },
                        sharp: entry.thumbnailWindowID.flatMap { model.largeThumbnails[$0] },
                        remembered: remembered?.image, rememberedAge: remembered?.age, width: width)
                // Ask for a sharp capture once the pointer settles on a window (not on every row it crosses).
                .task(id: entry.thumbnailWindowID) { model.requestLarge(entry.thumbnailWindowID) }
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
    var isSelected = false
    /// When set, a close button appears on hover or selection.
    var onClose: (() -> Void)? = nil
    let onHover: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    private var showsClose: Bool { onClose != nil && (isHovered || isSelected) }

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
                if entry.isActive && !showsClose {
                    // The tab or window currently in front.
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovered || isSelected ? Theme.fillHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .trailing) {
            if showsClose, let onClose {
                CloseButton(label: entry.title, action: onClose).padding(.trailing, 8)
            }
        }
        .pointerHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
        .accessibilityLabel(entry.title)
        .accessibilityHint("Switch to this \(entry.url.isEmpty ? "window" : "tab")")
        .accessibilityAction(named: "Close") { onClose?() }
    }
}

/// A small ✕ that closes the tab or window on its row.
private struct CloseButton: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(hovering ? Theme.fillSelected : Theme.fillHover))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering = $0 }
        .help("Close")
        .accessibilityLabel("Close \(label)")
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
            Monogram(host: entry.host, size: size)
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
    /// The tile-sized capture, and a sharper one if it has arrived. Either may be missing.
    let thumbnail: NSImage?
    let sharp: NSImage?
    /// A background tab's picture from when it was last in front, with how long ago that was.
    var remembered: NSImage? = nil
    var rememberedAge: String? = nil
    var width: CGFloat = 340

    /// The picture is shown whole, never cropped, at the window's own proportions.
    private var imageHeight: CGFloat {
        let image = sharp ?? thumbnail ?? remembered
        guard let image, image.size.width > 0 else { return width * 0.5 }
        return min(width * image.size.height / image.size.width, width > 400 ? 250 : 205)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Theme.fillQuiet
                if let image = sharp ?? thumbnail ?? remembered {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Leading(entry: entry, icon: icon, size: 52)
                }
            }
            .frame(width: width, height: imageHeight)
            .overlay(alignment: .bottomLeading) {
                if sharp == nil, thumbnail == nil, remembered != nil, let age = rememberedAge {
                    Text("Last seen \(age)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(8)
                }
            }
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
        .frame(width: width)
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

// MARK: - Search

private struct SearchButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold))
                Text("Search").font(.system(size: 11, weight: .medium))
                Text("⌃⌥Space").font(.system(size: 10)).foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(hovering ? Theme.fillHover : Theme.fillQuiet))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering = $0 }
        .accessibilityLabel("Search windows and tabs")
    }
}

/// Type to find anything open. ↑ ↓ choose, Return jumps, Esc closes.
private struct SearchPanel: View {
    @ObservedObject var model: WindowsModel
    @ObservedObject var web: WebBrowser
    @ObservedObject var learning: LearningStore
    @ObservedObject var settings: AppSettings
    @Binding var query: String
    @Binding var selection: Int
    var focus: FocusState<Bool>.Binding
    let onOpen: (Entry) -> Void
    let onWeb: (WebAction, BrowserProfile?) -> Void
    let onClose: () -> Void

    /// The profile highlighted for the next web action (nil until chosen: then the saved or last-used one).
    @State private var profileDirectory: String?
    private let visibleRows = 8

    private enum Row: Identifiable {
        case result(SearchResult)
        case web(WebAction)

        var id: String {
            switch self {
            case .result(let result): return result.id
            case .web: return "web-action"
            }
        }
    }

    private var activeProfile: BrowserProfile? {
        web.profiles.first { $0.directory == profileDirectory } ?? web.defaultProfile(preferred: settings.webProfile)
    }

    var body: some View {
        let action = WebAction.classify(query, engine: settings.searchEngine)
        let all = Search.results(for: query, in: model.groups) { entry, appName in
            learning.boost(entry, appName: appName, query: query)
        }
        let matches = Array(all.prefix(visibleRows - (action == nil ? 0 : 1))).map(Row.result)
        // A typed address goes first (you probably want to go there); plain words go last, after anything
        // you already have open that matches.
        let rows: [Row] = action.map { $0.kind == .address ? [.web($0)] + matches : matches + [.web($0)] } ?? matches
        let current = rows.indices.contains(selection) ? rows[selection] : rows.first

        VStack(alignment: .leading, spacing: 12) {
            field(count: all.count)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 2) {
                    if rows.isEmpty {
                        empty
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            switch row {
                            case .result(let result):
                                EntryRow(entry: result.entry.withSubtitle(subtitle(for: result)),
                                         icon: model.icons[result.appPID], isSelected: index == selection,
                                         onClose: result.entry.isClosable ? { model.close(result.entry) } : nil,
                                         onHover: { selection = index }, onOpen: { onOpen(result.entry) })
                            case .web(let action):
                                WebRow(action: action, browser: web.browserName, profile: activeProfile?.name,
                                       isSelected: index == selection,
                                       onHover: { selection = index }, onOpen: { openWeb(action, activeProfile) })
                            }
                        }
                        if all.count > matches.count {
                            Text("\(all.count - matches.count) more · keep typing to narrow")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                        }
                        if case .result(let selected)? = current, selected.entry.isClosable {
                            Text("↩ open  ·  ⌘W close")
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.top, 4)
                        }
                        if case .web = current, web.profiles.count > 1 {
                            Text("← → choose a profile  ·  ⌘↩ search the web")
                                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 592)

                switch current {
                case .result(let result)?:
                    PreviewPane(entry: result.entry, icon: model.icons[result.appPID],
                                thumbnail: result.entry.thumbnailWindowID.flatMap { model.thumbnails[$0] },
                                sharp: result.entry.thumbnailWindowID.flatMap { model.largeThumbnails[$0] }, width: 338)
                        .task(id: result.entry.thumbnailWindowID) { model.requestLarge(result.entry.thumbnailWindowID) }
                case .web(let action)?:
                    ProfilePicker(action: action, browser: web.browserName, profiles: web.profiles, selected: activeProfile,
                                  onHighlight: { profileDirectory = $0.directory },
                                  onPick: { openWeb(action, $0) })
                case nil:
                    EmptyView()
                }
            }
        }
        .onAppear { web.reload() }
        .onChange(of: query) { selection = 0 }
        .onKeyPress(.downArrow) { selection = min(selection + 1, max(rows.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            // Only on the web row, where the arrows choose a profile; elsewhere they move the text cursor.
            guard case .web? = current, web.profiles.count > 1 else { return .ignored }
            let step = press.key == .rightArrow ? 1 : -1
            let index = web.profiles.firstIndex { $0.id == activeProfile?.id } ?? 0
            profileDirectory = web.profiles[(index + step + web.profiles.count) % web.profiles.count].directory
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            if press.modifiers.contains(.command), let action {
                openWeb(action, activeProfile)       // always search the web, even when something matches
                return .handled
            }
            switch current {
            case .result(let result)?: onOpen(result.entry)
            case .web(let action)?: openWeb(action, activeProfile)
            case nil: break
            }
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("w")], phases: .down) { press in
            // Command-W closes the selected tab or window, as it does everywhere on a Mac. (Command-Delete
            // would be natural too, but the text field claims it to delete the line.)
            guard press.modifiers.contains(.command), case .result(let result)? = current, result.entry.isClosable
            else { return .ignored }
            model.close(result.entry)
            return .handled
        }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func openWeb(_ action: WebAction, _ profile: BrowserProfile?) {
        settings.webProfile = profile?.directory       // remembered for next time
        onWeb(action, profile)
    }

    private func field(count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            TextField("Search windows and tabs, or type an address", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused(focus)
                .accessibilityLabel("Search")
            Text(query.isEmpty ? "Recent" : "\(count) open")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 6).frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.textSecondary.opacity(0.4), lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.fillQuiet))
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(Theme.textSecondary)
            Text("Type to search what's open").font(.system(size: 13, weight: .medium))
            Text("or type an address or any words to open them on the web")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// "Google Chrome · github.com": results from different apps need to say where they live.
    private func subtitle(for result: SearchResult) -> String {
        [result.appName, result.entry.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// "Search Google for “swift”" or "Open github.com/acme", and which profile it will open in.
private struct WebRow: View {
    let action: WebAction
    let browser: String
    let profile: String?
    let isSelected: Bool
    let onHover: () -> Void
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: action.kind == .address ? "globe" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent))
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text([browser, profile].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("↩").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isHovered || isSelected ? Theme.fillHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
        .accessibilityLabel("\(action.title) in \(browser)\(profile.map { ", profile \($0)" } ?? "")")
    }
}

/// The right-hand pane for the web row: where it will open, and a click-to-choose list of profiles.
private struct ProfilePicker: View {
    let action: WebAction
    let browser: String
    let profiles: [BrowserProfile]
    let selected: BrowserProfile?
    let onHighlight: (BrowserProfile) -> Void
    let onPick: (BrowserProfile) -> Void
    private let visible = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New tab in \(browser)").font(.system(size: 14, weight: .semibold))
            Text(action.url.absoluteString)
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .lineLimit(2).truncationMode(.middle)

            if profiles.count > 1 {
                Text("Open as").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.top, 4)
                VStack(spacing: 2) {
                    ForEach(profiles.prefix(visible)) { profile in
                        ProfileRow(profile: profile, isSelected: profile.id == selected?.id,
                                   onHover: { onHighlight(profile) }, onPick: { onPick(profile) })
                    }
                    if profiles.count > visible {
                        Text("\(profiles.count - visible) more · use ← →")
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8).padding(.top, 2)
                    }
                }
            } else {
                Text("Opens a new tab in your \(profiles.isEmpty ? "default browser" : "only profile").")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 338, alignment: .leading)
    }
}

private struct ProfileRow: View {
    let profile: BrowserProfile
    let isSelected: Bool
    let onHover: () -> Void
    let onPick: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 9) {
                Monogram(host: profile.name, size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(profile.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let email = profile.email {
                        Text(email).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered || isSelected ? Theme.fillHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
        .accessibilityLabel("\(profile.name)\(profile.email.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens it in this profile")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .pointerHover { hovering = $0 }
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

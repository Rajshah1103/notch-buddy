import AppKit
import NotchCore
import SwiftUI
import WindowEngine

struct WindowsView: View {
    @ObservedObject var model: WindowsModel
    let notch: NotchState

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(model.snapshot.spaces) { space in
                            SpaceCard(title: "Desktop \(space.index)", symbol: nil,
                                      isCurrent: space.isCurrent, count: space.windows.count) {
                                ForEach(space.windows) { window in
                                    WindowRow(model: model, pid: window.pid, appName: window.appName,
                                              title: window.title) {
                                        model.focus(window, in: space)
                                        notch.collapse()
                                    }
                                }
                            }
                        }
                        if !model.snapshot.minimized.isEmpty {
                            SpaceCard(title: "Minimized", symbol: "dock.rectangle", isCurrent: false,
                                      count: model.snapshot.minimized.count) {
                                ForEach(model.snapshot.minimized) { window in
                                    WindowRow(model: model, pid: window.pid, appName: window.appName,
                                              title: window.title) {
                                        model.focus(window, in: nil)
                                        notch.collapse()
                                    }
                                }
                            }
                        }
                        if !model.snapshot.windowlessApps.isEmpty {
                            SpaceCard(title: "No window", symbol: "app.dashed", isCurrent: false,
                                      count: model.snapshot.windowlessApps.count) {
                                ForEach(model.snapshot.windowlessApps) { app in
                                    WindowRow(model: model, pid: app.pid, appName: app.name, title: "") {
                                        model.open(app)
                                        notch.collapse()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(minWidth: proxy.size.width, alignment: .center)
                }
            }

            PermissionHint(model: model)
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Card

private struct SpaceCard<Content: View>: View {
    let title: String
    let symbol: String?
    let isCurrent: Bool
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isCurrent {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .frame(height: 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) { content }
            }
        }
        .padding(Theme.cardPadding)
        .frame(width: Theme.cardWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isCurrent ? Theme.currentStroke : Theme.cardStroke, lineWidth: 0.5)
        )
    }
}

// MARK: - Row

private struct WindowRow: View {
    @ObservedObject var model: WindowsModel
    let pid: Int32
    let appName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let icon = model.icons[pid] {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        RoundedRectangle(cornerRadius: 5).fill(Theme.cardFill)
                    }
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? appName : title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                    if !title.isEmpty {
                        Text(appName)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Theme.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(title.isEmpty ? appName : "\(appName), \(title)")
        .accessibilityHint("Switch to this window")
    }
}

/// Feedback starts on press, not on release. Hover tint eases in quickly.
private struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(configuration.isPressed || hovering ? Theme.rowHover : .clear)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Permission hint

private struct PermissionHint: View {
    @ObservedObject var model: WindowsModel

    var body: some View {
        if !model.accessibilityGranted {
            hint("Allow Accessibility to jump between windows", action: Permissions.requestAccessibility)
        } else if !model.screenRecordingGranted {
            hint("Allow Screen Recording to show window titles", action: Permissions.requestScreenRecording)
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

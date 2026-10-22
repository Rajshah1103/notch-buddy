import AppKit
import SwiftUI
import WindowEngine

struct WindowsView: View {
    @ObservedObject var model: WindowsModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(model.snapshot.spaces) { space in
                    column(title: "Space \(space.index)", highlighted: space.isCurrent) {
                        ForEach(space.windows) { window in
                            WindowRow(label: window.title.isEmpty ? window.appName : window.title,
                                      pid: window.pid) {
                                model.focus(window, in: space)
                            }
                        }
                    }
                }
                if !model.snapshot.minimized.isEmpty {
                    column(title: "Minimized", highlighted: false) {
                        ForEach(model.snapshot.minimized) { window in
                            WindowRow(label: window.title.isEmpty ? window.appName : window.title,
                                      pid: window.pid) {
                                model.focus(window, in: nil)
                            }
                        }
                    }
                }
                if !model.snapshot.windowlessApps.isEmpty {
                    column(title: "No window", highlighted: false) {
                        ForEach(model.snapshot.windowlessApps) { app in
                            WindowRow(label: app.name, pid: app.pid) { model.open(app) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func column<Content: View>(title: String, highlighted: Bool,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(highlighted ? Color.green : Color.white.opacity(0.45))
                .padding(.bottom, 4)
            content()
        }
        .frame(width: 170, alignment: .topLeading)
    }
}

private struct WindowRow: View {
    let label: String
    let pid: Int32
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hovering ? 0.14 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

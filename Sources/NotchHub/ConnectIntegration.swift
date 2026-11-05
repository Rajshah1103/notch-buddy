import AppKit
import ConnectorKit
import NotchCore
import SwiftUI

/// The "+" in the notch: where anyone connects an app. It lists the connectors on disk with an on switch, adds
/// the bundled examples in one click, and gives the commands that let any tool or AI harness talk to the notch.
@MainActor
final class ConnectIntegration: NotchIntegration {
    static let id = "connect"
    var id: String { Self.id }
    let name = "Connect"
    var isEnabled: Bool { true }
    private let changed: () -> Void

    /// `changed` is called after a connector folder was added, so the app can pick it up without a restart.
    init(changed: @escaping () -> Void) { self.changed = changed }

    func start() {}
    func stop() {}
    func refresh() {}

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView { AnyView(ConnectChip(isOpen: isOpen, action: action)) }
    func panel(notch: NotchState) -> AnyView { AnyView(ConnectPanel(changed: changed)) }
}

private struct ConnectChip: View {
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(isOpen ? Theme.fillSelected : (hovering ? Theme.fillHover : Theme.fillQuiet)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerHover { hovering = $0 }
        .help("Connect an app")
        .accessibilityLabel("Connect an app")
        .accessibilityHint("Shows how to add connectors and send events from other tools")
    }
}

// MARK: - Panel

private enum Examples {
    /// The example connectors shipped inside the app (see scripts/bundle.sh).
    static var directory: URL? { Bundle.main.resourceURL?.appendingPathComponent("ConnectorExamples", isDirectory: true) }

    static func available() -> [ConnectorStore.Found] {
        directory.map { ConnectorStore.load(from: $0) } ?? []
    }

    /// Copies one example next to the user's own connectors. Never overwrites a folder that is already there.
    @discardableResult
    static func install(_ example: ConnectorStore.Found) -> Bool {
        let target = ConnectorStore.directory.appendingPathComponent(example.folder.lastPathComponent, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else { return false }
        do {
            try FileManager.default.createDirectory(at: ConnectorStore.directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: example.folder, to: target)
            return true
        } catch { return false }
    }
}

private struct ConnectPanel: View {
    let changed: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var installed: [ConnectorStore.Found] = []
    @State private var examples: [ConnectorStore.Found] = []
    @State private var copied: String?

    private var addable: [ConnectorStore.Found] {
        let have = Set(installed.map(\.id)).union(installed.map { $0.folder.lastPathComponent })
        return examples.filter { !have.contains($0.id) && !have.contains($0.folder.lastPathComponent) }
    }

    /// The command that reaches this app: the short name when the Homebrew link exists, else the full path.
    private var tool: String {
        let links = ["/opt/homebrew/bin/notchhub", "/usr/local/bin/notchhub"]
        if links.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return "notchhub" }
        return "\"\(Bundle.main.executablePath ?? "NotchHub")\""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            connectors.frame(maxWidth: .infinity, alignment: .topLeading)
            anyTool.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .onAppear(perform: reload)
    }

    private func reload() {
        installed = ConnectorStore.load()
        examples = Examples.available()
    }

    // MARK: Connectors

    private var connectors: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connectors").font(.system(size: 15, weight: .semibold))
            Text("A connector is a small script that puts a service in the notch. It runs only after you turn it on.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(installed) { item in
                        ConnectorToggleRow(settings: settings, found: item)
                    }
                    ForEach(addable) { example in
                        AddRow(example: example) {
                            if Examples.install(example) { changed(); reload() }
                        }
                    }
                    if installed.isEmpty && addable.isEmpty {
                        Text("Nothing here yet. Put a folder with a connector.json in the connectors folder, then check for new ones.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 14) {
                Button("Open connectors folder") {
                    try? FileManager.default.createDirectory(at: ConnectorStore.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(ConnectorStore.directory)
                }
                Button("Check for new") { changed(); reload() }
                Button("Settings") { AppActions.openSettings() }
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
    }

    // MARK: Any tool

    private var anyTool: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From any tool or AI harness").font(.system(size: 15, weight: .semibold))
            Text("Anything that can run a command can talk to the notch. Copy one, paste it where your tool runs commands.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)

            CommandRow(title: "Show a bubble", tool: tool, command: "emit --source ci --headline \"Deploy done\"", copied: $copied)
            CommandRow(title: "Report an AI session working", tool: tool, command: "agent --harness codex --session $$ --state working", copied: $copied)
            CommandRow(title: "Ask for approval", tool: tool, command: "agent --harness codex --session $$ --state needs-approval", copied: $copied)

            Button("Read the guide") {
                if let url = URL(string: "https://github.com/Rajshah1103/notch-buddy/blob/main/docs/extending.md") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link).font(.system(size: 12))
        }
    }
}

private struct ConnectorToggleRow: View {
    @ObservedObject var settings: AppSettings
    let found: ConnectorStore.Found
    @State private var hovering = false

    private var manifest: Manifest { found.manifest }
    private var on: Binding<Bool> {
        Binding(get: { settings.enabledConnectors.contains(manifest.id) },
                set: { value in if value { settings.enabledConnectors.insert(manifest.id) } else { settings.enabledConnectors.remove(manifest.id) } })
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: manifest.symbol ?? "puzzlepiece.extension.fill").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(manifest.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(manifest.about ?? "Every \(Int(manifest.seconds)) seconds").font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: on).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .padding(.horizontal, 10).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Theme.fillHover : .clear))
        .pointerHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(manifest.name), \(on.wrappedValue ? "on" : "off")")
    }
}

private struct AddRow: View {
    let example: ConnectorStore.Found
    let add: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: example.manifest.symbol ?? "puzzlepiece.extension").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(example.manifest.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(example.manifest.about ?? "Example connector").font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: add) {
                Text("Add").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 24).background(Capsule().fill(Theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(example.manifest.name)")
        }
        .padding(.horizontal, 10).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Theme.fillHover : .clear))
        .pointerHover { hovering = $0 }
    }
}

private struct CommandRow: View {
    let title: String
    let tool: String            // what gets copied in front of `command`: a short name or the full path
    let command: String         // the arguments, which are what you read
    @Binding var copied: String?

    private var full: String { "\(tool) \(command)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Text("notchhub \(command)")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(copied == full ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(full, forType: .string)
                    copied = full
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == full { copied = nil } }
                }
                .buttonStyle(.link).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.fillQuiet))
        }
    }
}

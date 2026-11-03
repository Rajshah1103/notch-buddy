import ConnectorKit
import Foundation
import NotchCore
import SwiftUI

/// Connectors found on disk: `~/Library/Application Support/NotchHub/connectors/<name>/connector.json`.
enum ConnectorStore {
    struct Found: Identifiable {
        let manifest: Manifest
        let folder: URL
        var id: String { manifest.id }
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchHub/connectors", isDirectory: true)
    }

    /// Every folder with a readable manifest, sorted by name. A broken or duplicate one is skipped, never fatal.
    static func load(from directory: URL = directory) -> [Found] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var seen: Set<String> = []
        return folders.compactMap { folder -> Found? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("connector.json")),
                  let manifest = try? Manifest.parse(data), seen.insert(manifest.id).inserted else { return nil }
            return Found(manifest: manifest, folder: folder)
        }.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }
}

/// Runs one connector on its interval and keeps what it last reported.
@MainActor
final class ConnectorModel: ObservableObject {
    let found: ConnectorStore.Found
    @Published private(set) var items: [Item] = []
    @Published private(set) var error: String?
    @Published private(set) var updated: Date?

    var manifest: Manifest { found.manifest }
    var failing: Int { items.filter { $0.status == .failing }.count }
    var attention: Int { items.filter { $0.status == .pending || $0.status == .running }.count }

    private var timer: Timer?
    private var running = false
    private var known: [String: Item.Status]?
    private let post: (Message.Incoming) -> Void

    init(found: ConnectorStore.Found, post: @escaping (Message.Incoming) -> Void) {
        self.found = found
        self.post = post
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: manifest.seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        known = nil; items = []; error = nil; updated = nil
    }

    func refresh() {
        guard !running else { return }
        running = true
        let (manifest, folder) = (manifest, found.folder)
        Task {
            let result: Result<[Item], Error> = await Task.detached {
                do {
                    let secret = manifest.secret == nil ? nil : ConnectorSecret.read(manifest.id)
                    return .success(try await Runner.run(manifest, in: folder, secret: secret))
                } catch { return .failure(error) }
            }.value
            running = false
            guard timer != nil else { return }          // turned off while it ran
            switch result {
            case .success(let list):
                Changes.moments(connector: manifest, previous: known, now: list).forEach(post)
                known = Changes.statuses(list)
                items = list; error = nil; updated = Date()
            case .failure(let failure):
                error = Self.describe(failure)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? Runner.Failure {
        case .notFound?: "The script was not found or is not executable."
        case .timedOut?: "The script took longer than \(Int(Runner.timeout)) seconds."
        case .badOutput?: "The script did not print the expected JSON."
        case .failed(let code)?: "The script exited with code \(code)."
        case nil: "The script could not be run."
        }
    }
}

@MainActor
final class ConnectorIntegration: NotchIntegration {
    let model: ConnectorModel
    private let settings: AppSettings
    var id: String { model.manifest.id }
    var name: String { model.manifest.name }

    init(model: ConnectorModel, settings: AppSettings? = nil) {
        self.model = model
        self.settings = settings ?? .shared
    }

    var isEnabled: Bool { settings.enabledConnectors.contains(id) }
    func start() { model.start() }
    func stop() { model.stop() }
    func refresh() { if Date().timeIntervalSince(model.updated ?? .distantPast) > model.manifest.seconds { model.refresh() } }

    func chip(isOpen: Bool, action: @escaping () -> Void) -> AnyView { AnyView(ConnectorChip(model: model, isOpen: isOpen, action: action)) }
    func panel(notch: NotchState) -> AnyView { AnyView(ConnectorPanel(model: model, dismiss: { notch.collapse() })) }
}

private func connectorTint(_ manifest: Manifest) -> Color { manifest.tint.flatMap { Color(hex: $0) } ?? Theme.accent }

struct ConnectorChip: View {
    @ObservedObject var model: ConnectorModel
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: model.manifest.symbol ?? "puzzlepiece.extension.fill").font(.system(size: 10, weight: .bold))
                if isOpen { Text(model.manifest.name).font(.system(size: 11, weight: .medium)) }
                if model.attention > 0 { Text("\(model.attention)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary) }
                if model.failing > 0 { Circle().fill(.red).frame(width: 6, height: 6) }
                else if model.error != nil { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange) }
            }
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(isOpen ? Theme.fillSelected : (hovering ? Theme.fillHover : Theme.fillQuiet)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ConnectorPanel: View {
    @ObservedObject var model: ConnectorModel
    let dismiss: () -> Void

    var body: some View {
        if let error = model.error, model.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
                Text("\(model.manifest.name) could not update").font(.system(size: 14, weight: .semibold))
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Button("Open Settings") { AppActions.openSettings() }.controlSize(.small)
            }
            .frame(maxWidth: .infinity).padding(.top, 70)
        } else if model.updated == nil {
            Text("Loading \(model.manifest.name)…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 90)
        } else if model.items.isEmpty {
            Text("Nothing to show").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity).padding(.top, 90)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.items.prefix(7)) { item in ConnectorRow(item: item, manifest: model.manifest, dismiss: dismiss) }
                if model.items.count > 7 {
                    Text("\(model.items.count - 7) more").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary).padding(.horizontal, 10).frame(height: 28)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct ConnectorRow: View {
    let item: Item
    let manifest: Manifest
    let dismiss: () -> Void
    @State private var hovering = false

    private var link: URL? { item.url.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil } }

    var body: some View {
        Button {
            if let link { LinkOpener.open(link, for: manifest.id) }
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let subtitle = item.subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering && link != nil ? Theme.fillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var icon: String {
        switch item.status {
        case .ok: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        case .running: "arrow.triangle.2.circlepath.circle.fill"
        case .pending: "circle.dotted"
        }
    }
    private var color: Color {
        switch item.status {
        case .ok: .green
        case .failing: .red
        case .running: .orange
        case .pending: connectorTint(manifest)
        }
    }
}

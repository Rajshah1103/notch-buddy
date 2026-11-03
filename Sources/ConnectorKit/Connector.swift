import Foundation

/// `connector.json`: describes one connector, a folder holding this file and the script it runs.
public struct Manifest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// SF Symbol for the chip.
    public var symbol: String?
    /// `#RRGGBB`.
    public var tint: String?
    /// Program and arguments. A first word starting with `./` is relative to the connector's folder.
    public var run: [String]
    /// Seconds between runs; never less than 30.
    public var interval: Double?
    /// Name of an environment variable the script reads its secret from. The value lives in the Keychain.
    public var secret: String?
    public var about: String?

    public var seconds: Double { max(interval ?? 120, 30) }

    public enum Invalid: Error, Equatable { case id, name, run }

    /// Reads and checks a manifest. The id becomes a folder-like key and a Keychain name, so it is kept plain.
    public static func parse(_ data: Data) throws -> Manifest {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard !manifest.id.isEmpty, manifest.id.count <= 40,
              manifest.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw Invalid.id }
        guard !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Invalid.name }
        guard let program = manifest.run.first, !program.isEmpty else { throw Invalid.run }
        if let secret = manifest.secret, !secret.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) { throw Invalid.id }
        return manifest
    }
}

/// One row a connector reports.
public struct Item: Equatable, Identifiable, Sendable {
    public enum Status: String, Sendable { case ok, failing, running, pending }
    public var id: String
    public var title: String
    public var subtitle: String?
    public var status: Status
    public var url: String?

    public static let maxItems = 50

    /// Reads a script's output: `{"items":[{"title":..., "subtitle":..., "status":..., "url":..., "id":...}]}`.
    /// Rows without a title are skipped; an unknown status counts as `ok`.
    public static func parse(_ data: Data) -> [Item]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = object["items"] as? [[String: Any]] else { return nil }
        return rows.prefix(maxItems).compactMap { row in
            guard let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let id = (row["id"] as? String) ?? title
            return Item(id: String(id.prefix(120)), title: String(title.prefix(120)),
                        subtitle: (row["subtitle"] as? String).map { String($0.prefix(160)) },
                        status: (row["status"] as? String).flatMap(Status.init(rawValue:)) ?? .ok,
                        url: row["url"] as? String)
        }
    }
}

/// What changed between two runs, as bubble requests. The first run says nothing, so turning a connector on
/// does not announce everything that already existed.
public enum Changes {
    public static func moments(connector: Manifest, previous: [String: Item.Status]?, now: [Item]) -> [Message.Incoming] {
        guard let previous else { return [] }
        var result: [Message.Incoming] = []
        for item in now where previous[item.id] != item.status {
            func make(_ headline: String, mood: String) -> Message.Incoming {
                Message.Incoming(source: connector.id, headline: headline, detail: item.subtitle ?? connector.name, mood: mood,
                                 symbol: connector.symbol, url: item.url, tint: connector.tint, ttl: nil, priority: nil,
                                 group: nil, id: "\(connector.id):\(item.id):\(item.status.rawValue)")
            }
            switch (previous[item.id], item.status) {
            case (_, .failing): result.append(make("\(item.title) failed", mood: "sad"))
            case (.some(.failing), .ok): result.append(make("\(item.title) recovered", mood: "proud"))
            case (nil, .pending): result.append(make(item.title, mood: "alert"))
            default: break
            }
        }
        return result
    }

    public static func statuses(_ items: [Item]) -> [String: Item.Status] {
        Dictionary(items.map { ($0.id, $0.status) }, uniquingKeysWith: { _, last in last })
    }
}

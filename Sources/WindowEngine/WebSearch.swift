import Foundation

// MARK: - What was typed

public enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google, duckDuckGo, bing
    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        }
    }

    public func url(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google: components = URLComponents(string: "https://www.google.com/search")!
        case .duckDuckGo: components = URLComponents(string: "https://duckduckgo.com/")!
        case .bing: components = URLComponents(string: "https://www.bing.com/search")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

/// What opening the typed text in a browser would do.
public struct WebAction: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case address, search }
    public let kind: Kind
    public let url: URL
    /// "Open github.com/acme" or "Search Google for “swift”".
    public let title: String

    /// Typed addresses ("github.com/acme", "localhost:3000") open directly; anything else is a web search.
    public static func classify(_ text: String, engine: SearchEngine) -> WebAction? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = address(text) { return WebAction(kind: .address, url: url, title: "Open \(display(url))") }
        guard let url = engine.url(for: text) else { return nil }
        return WebAction(kind: .search, url: url, title: "Search \(engine.name) for “\(text)”")
    }

    // Common top-level domains. Deliberately short: two-letter country codes such as .rs, .py and .sh
    // are also file extensions ("main.rs"), and mistaking a file name for a website is worse than
    // searching for a website.
    private static let domainSuffixes: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "co", "ai", "me", "edu", "gov", "info", "biz", "xyz", "tech",
        "cloud", "site", "online", "store", "blog", "news", "tv", "so", "to", "us", "uk", "eu", "in", "de", "fr",
        "jp", "cn", "au", "ca", "ru", "br", "it", "es", "nl", "se", "no", "ch", "nz", "za", "kr", "sg",
    ]

    static func address(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }

        // An explicit scheme: trust it.
        if let range = text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) {
            let scheme = text[..<range.upperBound].lowercased()
            guard scheme.hasPrefix("http") || scheme.hasPrefix("file"), let url = URL(string: text), url.host != nil || scheme.hasPrefix("file")
            else { return nil }
            return url
        }

        let host = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let hostOnly = host.split(separator: ":").first.map(String.init) ?? host
        let lower = hostOnly.lowercased()

        if lower == "localhost" || lower.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil {
            return URL(string: "http://\(text)")
        }
        let labels = lower.split(separator: ".")
        guard labels.count >= 2, labels.allSatisfy({ $0.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"#, options: .regularExpression) != nil }),
              domainSuffixes.contains(String(labels.last!))
        else { return nil }
        return URL(string: "https://\(text)")
    }

    private static func display(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://www.", "http://www.", "https://", "http://"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)); break
        }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}

// MARK: - Browser profiles

public struct BrowserProfile: Identifiable, Hashable, Sendable {
    public var id: String { directory }
    /// The profile's folder name: "Default", "Profile 1"…
    public let directory: String
    public let name: String
    public let email: String?

    public init(directory: String, name: String, email: String?) {
        self.directory = directory
        self.name = name
        self.email = email
    }
}

/// Chromium browsers keep their profiles in a `Local State` file: a name and (when signed in) an
/// email for each, the order the browser shows them in, and which was used last.
public enum BrowserProfiles {
    public struct List: Equatable, Sendable {
        public var profiles: [BrowserProfile]
        public var lastUsed: String?
        public static let empty = List(profiles: [], lastUsed: nil)
    }

    public static func parse(_ data: Data) -> List {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]]
        else { return .empty }

        let order = profile["profiles_order"] as? [String] ?? []
        let directories = cache.keys.sorted { a, b in
            switch (order.firstIndex(of: a), order.firstIndex(of: b)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.localizedStandardCompare(b) == .orderedAscending     // "Profile 2" before "Profile 10"
            }
        }
        let profiles = directories.map { directory -> BrowserProfile in
            let info = cache[directory] ?? [:]
            let email = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory
            return BrowserProfile(directory: directory, name: name, email: email)
        }
        return List(profiles: profiles, lastUsed: profile["last_used"] as? String)
    }

    /// Where each supported browser keeps its data, relative to Application Support.
    public static let supportFolders: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
    ]

    public static func load(bundleID: String) -> List {
        guard let folder = supportFolders[bundleID],
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: base.appendingPathComponent(folder).appendingPathComponent("Local State"))
        else { return .empty }
        return parse(data)
    }
}

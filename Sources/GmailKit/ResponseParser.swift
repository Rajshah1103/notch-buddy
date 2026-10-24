import Foundation

/// Turns Gmail API answers into the app's types. Pure, so it is easy to test.
public enum ResponseParser {
    public static func unreadCount(fromLabel data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["messagesUnread"] as? Int
    }

    public static func ids(fromList data: Data) -> [String] {
        let list = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["messages"] as? [[String: Any]]
        return list?.compactMap { $0["id"] as? String } ?? []
    }

    public static func email(fromProfile data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["emailAddress"] as? String
    }

    public static func message(from data: Data) -> GmailMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else { return nil }
        let headers = ((object["payload"] as? [String: Any])?["headers"] as? [[String: Any]]) ?? []
        func header(_ name: String) -> String? {
            headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String
        }
        let millis = (object["internalDate"] as? String).flatMap(Double.init)
        let subject = header("Subject")?.trimmingCharacters(in: .whitespaces) ?? ""
        return GmailMessage(id: id, from: sender(header("From") ?? ""),
                            subject: subject.isEmpty ? "(no subject)" : subject,
                            date: millis.map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    /// `"Ada Lovelace" <ada@example.com>` → `Ada Lovelace`; a bare address stays as it is.
    public static func sender(_ header: String) -> String {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "<"), trimmed.hasSuffix(">") else { return trimmed }
        let name = trimmed[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        return name.isEmpty ? String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]) : name
    }
}

import Foundation

/// Reads the inbox. Only ever reads: the sign-in carries the read-only scope.
public struct GmailClient {
    private let session: URLSession
    private static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    public init(session: URLSession = .shared) { self.session = session }

    public func email(accessToken: String) async throws -> String {
        guard let email = ResponseParser.email(fromProfile: try await get("/profile", accessToken)) else {
            throw GmailError.failed("Gmail did not say whose inbox this is")
        }
        return email
    }

    public func snapshot(email: String, accessToken: String, limit: Int = 20) async throws -> GmailSnapshot {
        async let label = get("/labels/INBOX", accessToken)
        async let page = unreadPage(token: nil, limit: limit, accessToken)
        let unread = ResponseParser.unreadCount(fromLabel: try await label) ?? 0
        let (messages, next) = try await page
        return GmailSnapshot(email: email, unread: unread, messages: messages, nextPage: next)
    }

    /// One page of unread inbox messages, newest first, and where the next page starts (nil at the end).
    public func unreadPage(token: String?, limit: Int = 20, _ accessToken: String) async throws -> (messages: [GmailMessage], next: String?) {
        let paging = token.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }.map { "&pageToken=\($0)" } ?? ""
        let list = try await get("/messages?q=is:unread%20in:inbox&maxResults=\(limit)\(paging)", accessToken)
        let ids = ResponseParser.ids(fromList: list)

        // One request per message, all at once; the order is restored from the list's.
        let fetched = try await withThrowingTaskGroup(of: GmailMessage?.self) { group -> [String: GmailMessage] in
            for id in ids {
                group.addTask {
                    ResponseParser.message(from: try await get("/messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject", accessToken))
                }
            }
            var found: [String: GmailMessage] = [:]
            for try await message in group { if let message { found[message.id] = message } }
            return found
        }
        return (ids.compactMap { fetched[$0] }, ResponseParser.nextPageToken(fromList: list))
    }

    private func get(_ path: String, _ accessToken: String) async throws -> Data {
        var request = URLRequest(url: URL(string: Self.base + path)!, timeoutInterval: 15)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) } catch let error as URLError {
            throw error.code == .cancelled ? error : GmailError.offline
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw GmailError.signedOut
        case 403, 429: throw GmailError.failed("Gmail is limiting requests; it will retry")
        case let code: throw GmailError.failed("Gmail returned \(code)")
        }
    }
}

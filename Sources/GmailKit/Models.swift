import Foundation

public struct GmailMessage: Identifiable, Equatable {
    public let id: String
    /// Sender's display name, or their address when there is no name.
    public let from: String
    public let subject: String
    public let date: Date?

    public init(id: String, from: String, subject: String, date: Date?) {
        self.id = id; self.from = from; self.subject = subject; self.date = date
    }
}

public struct GmailSnapshot: Equatable {
    public let email: String
    /// Unread messages in the inbox.
    public let unread: Int
    /// The newest unread ones, newest first.
    public let messages: [GmailMessage]

    public init(email: String, unread: Int, messages: [GmailMessage]) {
        self.email = email; self.unread = unread; self.messages = messages
    }
}

public enum GmailError: Error, Equatable {
    case offline
    /// The saved sign-in no longer works (revoked, or a testing-mode login that expired).
    case signedOut
    case failed(String)

    public var message: String {
        switch self {
        case .offline: return "Can't reach Gmail"
        case .signedOut: return "Gmail sign-in expired"
        case .failed(let text): return text
        }
    }
}

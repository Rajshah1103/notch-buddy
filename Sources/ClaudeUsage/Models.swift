import Foundation

/// Why a quiet session wants a look.
public enum Attention: Hashable {
    case approval   // its last move was a tool call and nothing has happened since
    case finished   // it ended its turn a short while ago
}

public struct ClaudeSession: Identifiable, Hashable {
    public let id: String
    /// Last path component of the folder the session runs in.
    public let project: String
    public let lastActivity: Date
    public let inputTokens: Int
    public let outputTokens: Int
    /// The chat's name: its /rename, else the title Claude Code generated. Nil when it has none yet.
    public let title: String?
    /// Full working folder, for reopening the chat.
    public let cwd: String?
    public let attention: Attention?

    /// What to call the chat in the UI.
    public var displayName: String { title ?? project }
    public var totalTokens: Int { inputTokens + outputTokens }

    public init(id: String, project: String, lastActivity: Date, inputTokens: Int, outputTokens: Int,
                title: String? = nil, cwd: String? = nil, attention: Attention? = nil) {
        self.attention = attention
        self.title = title
        self.cwd = cwd
        self.id = id
        self.project = project
        self.lastActivity = lastActivity
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct ClaudeSnapshot: Equatable {
    /// Sessions active in the last day, most recent first.
    public var sessions: [ClaudeSession]
    /// Sessions that wrote to their transcript within the working window.
    public var working: [ClaudeSession]
    public var tokensToday: Int
    /// When the current stretch of activity began (nil when nothing is working).
    public var workingSince: Date?

    public init(sessions: [ClaudeSession], working: [ClaudeSession], tokensToday: Int, workingSince: Date?) {
        self.sessions = sessions
        self.working = working
        self.tokensToday = tokensToday
        self.workingSince = workingSince
    }

    public static let idle = ClaudeSnapshot(sessions: [], working: [], tokensToday: 0, workingSince: nil)
    public var isWorking: Bool { !working.isEmpty }
}

public enum TokenFormat {
    /// 950 → "950", 12_400 → "12.4k", 3_200_000 → "3.2M".
    public static func short(_ count: Int) -> String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return String(format: "%.1fk", Double(count) / 1_000).replacingOccurrences(of: ".0k", with: "k")
        default: return String(format: "%.1fM", Double(count) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

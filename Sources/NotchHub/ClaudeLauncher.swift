import AppKit
import ClaudeUsage

/// Reopens a Claude Code chat in a new Ghostty window, in the folder it ran in.
enum ClaudeLauncher {
    static func open(_ session: ClaudeSession) {
        // Quote for the shell: ids are UUIDs, but the folder is whatever the user has on disk.
        let folder = session.cwd.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" } ?? "~"
        let command = "cd \(folder) && claude --resume \(session.id)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-na", "Ghostty", "--args", "-e", "/bin/zsh", "-lic", command]
        do { try process.run() } catch {
            // No Ghostty: put the command on the clipboard so it can be pasted anywhere.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}

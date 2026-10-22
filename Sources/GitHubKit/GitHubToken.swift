import Foundation
import Security

/// Where the GitHub token comes from: one the user pasted (kept in the Keychain), or, as a
/// convenience for people who already use it, the GitHub command line tool's login.
public enum GitHubToken {
    private static let service = "dev.notchhub.github"
    private static let account = "token"

    public static func stored() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func save(_ token: String) {
        clear()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }

    /// `gh auth token`. A GUI app has a minimal PATH, so the usual install locations are tried directly.
    public static func fromCommandLine() -> String? {
        guard let path = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: FileManager.default.isExecutableFile) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["auth", "token"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let token = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    /// The token to use now, and where it came from.
    public static func resolve(allowCommandLine: Bool) -> (token: String, source: Source)? {
        if let token = stored() { return (token, .pasted) }
        if allowCommandLine, let token = fromCommandLine() { return (token, .commandLine) }
        return nil
    }

    public enum Source { case pasted, commandLine }
}

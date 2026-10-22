import Foundation
import Security

/// Where the GitHub token comes from: one the user pasted (kept in the Keychain), or, as a
/// convenience for people who already use it, the GitHub command line tool's login.
public enum GitHubToken {
    private static let service = "dev.notchhub.github"
    private static let account = "token"
    /// Whether a token has been saved. Checked first, so nothing touches the Keychain (and nothing can
    /// make macOS ask for permission) until the user has actually saved one.
    private static let savedFlag = "githubTokenSaved"

    public static func stored() -> String? {
        guard UserDefaults.standard.bool(forKey: savedFlag) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            // If macOS would ask the user for permission (an item written by a different build), fail
            // instead. A prompt blocks the calling thread until someone answers it.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func save(_ token: String) {
        clear()
        UserDefaults.standard.set(true, forKey: savedFlag)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecValueData as String: Data(token.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public static func clear() {
        UserDefaults.standard.set(false, forKey: savedFlag)
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

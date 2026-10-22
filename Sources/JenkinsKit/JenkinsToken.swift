import Foundation
import Security

/// The Jenkins API token lives in the Keychain; the address and username are ordinary preferences.
public enum JenkinsToken {
    private static let service = "dev.notchhub.jenkins"
    private static let account = "api-token"
    /// Whether a token has been saved. Checked first, so nothing touches the Keychain (and nothing can
    /// make macOS ask for permission) until the user has actually saved one.
    private static let savedFlag = "jenkinsTokenSaved"

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
        SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                    kSecAttrAccount as String: account, kSecValueData as String: Data(token.utf8)] as CFDictionary, nil)
    }

    public static func clear() {
        UserDefaults.standard.set(false, forKey: savedFlag)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

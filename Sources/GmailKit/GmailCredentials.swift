import Foundation
import Security

/// Everything needed to talk to Gmail, kept in the Keychain as one item: the Google Cloud OAuth client
/// the user created, and the long-lived sign-in it produced. Nothing is read until one has been saved,
/// so nothing can make macOS ask for permission before the user has set Gmail up.
public struct GmailCredentials: Codable, Equatable {
    public var clientID: String
    /// Google calls this a secret, but for desktop apps it is not one; the token endpoint still wants it.
    public var clientSecret: String
    public var refreshToken: String?
    public var email: String?

    public init(clientID: String, clientSecret: String, refreshToken: String? = nil, email: String? = nil) {
        self.clientID = clientID; self.clientSecret = clientSecret
        self.refreshToken = refreshToken; self.email = email
    }

    private static let service = "dev.notchhub.gmail"
    private static let account = "credentials"
    private static let savedFlag = "gmailCredentialsSaved"

    public static func load() -> GmailCredentials? {
        guard UserDefaults.standard.bool(forKey: savedFlag) else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,   // never block on a prompt
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(GmailCredentials.self, from: data)
    }

    public func save() {
        Self.clear()
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(true, forKey: Self.savedFlag)
        SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
                    kSecAttrAccount as String: Self.account, kSecValueData as String: data] as CFDictionary, nil)
    }

    public static func clear() {
        UserDefaults.standard.set(false, forKey: savedFlag)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: account] as CFDictionary)
    }
}

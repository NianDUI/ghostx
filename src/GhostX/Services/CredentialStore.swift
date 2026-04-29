import Foundation
import Security

/// macOS Keychain-based credential storage
final class CredentialStore {
    static let shared = CredentialStore()

    private init() {}

    func savePassword(host: String, username: String, password: String) throws {
        let item: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete existing first
        SecItemDelete(item as CFDictionary)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    func savePrivateKey(host: String, username: String, keyData: Data) throws {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GhostX-SSHKey-\(host)",
            kSecAttrAccount as String: username,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(item as CFDictionary)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }

    func load(host: String, username: String) -> Credential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let pass = String(data: data, encoding: .utf8) {
            return Credential(host: host, username: username, secret: .password(pass))
        }

        // Try key
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GhostX-SSHKey-\(host)",
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var keyResult: AnyObject?
        let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &keyResult)
        if keyStatus == errSecSuccess, let keyData = keyResult as? Data {
            return Credential(host: host, username: username, secret: .privateKey(keyData))
        }

        return nil
    }

    func delete(host: String, username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum CredentialError: Error {
    case keychainError(OSStatus)
}

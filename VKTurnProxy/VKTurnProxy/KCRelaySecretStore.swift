import Foundation
import Security

/// Stores the MAX session token outside UserDefaults and outside VPN
/// providerConfiguration. The token is only needed by the main app to obtain
/// short-lived TURN credentials; PacketTunnel receives only those short-lived
/// credentials through seeded_turn.
enum KCRelaySecretStore {
    private static let service = "com.vkturnproxy.kc-relay"
    private static let maxTokenAccount = "max-token"

    static func loadMaxToken() -> String {
        var query = baseQuery(account: maxTokenAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    @discardableResult
    static func saveMaxToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return deleteMaxToken() }

        let query = baseQuery(account: maxTokenAccount)
        let data = Data(trimmed.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteMaxToken() -> Bool {
        let status = SecItemDelete(baseQuery(account: maxTokenAccount) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// One-time migration for builds that briefly stored the token in defaults.
    static func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: "kcMaxToken"), !legacy.isEmpty else { return }
        if loadMaxToken().isEmpty, saveMaxToken(legacy) {
            defaults.removeObject(forKey: "kcMaxToken")
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

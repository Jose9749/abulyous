import Foundation
import Security

/// API-nøglen hører hjemme i nøgleringen, ikke i UserDefaults.
enum Keychain {

    private static let service = "dk.privat.dansksvar"

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }

        var attributes = query
        attributes[kSecValueData as String] = data
        // Nøglen skal kunne læses, mens telefonen er låst — appen lytter jo videre dér.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }

        return value
    }
}

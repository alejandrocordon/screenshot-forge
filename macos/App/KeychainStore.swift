import Foundation
import Security

/// Minimal Keychain wrapper for secrets (the App Store Connect `.p8` private
/// key). Non-secret ids (issuer, key id) live in `@AppStorage`.
final class KeychainStore {
    static let shared = KeychainStore()
    private let service = "com.alejandrocordon.screenshotforge"

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    @discardableResult
    func set(_ value: String, for key: String) -> Bool {
        SecItemDelete(baseQuery(key) as CFDictionary)
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    func exists(_ key: String) -> Bool { get(key) != nil }
}

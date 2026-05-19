import Foundation
import Security

final class KeychainStore {
    private let service = "com.voxforge.app"
    private let legacyService = "com.typemore.app"

    func string(for key: String) -> String {
        if let value = string(for: key, service: service) {
            return value
        }

        if let legacyValue = string(for: key, service: legacyService) {
            setString(legacyValue, for: key)
            return legacyValue
        }

        return ""
    }

    private func string(for key: String, service: String) -> String? {
        var query = baseQuery(for: key, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(for: key, service: service)
        let attributes = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func baseQuery(for key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

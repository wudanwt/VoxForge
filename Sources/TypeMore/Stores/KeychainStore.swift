import Foundation
import Security

final class KeychainStore {
    private let service = "com.voxforge.app"
    private let legacyService = "com.typemore.app"

    private var secretsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("VoxForge/Secrets", isDirectory: true)
    }

    func string(for key: String) -> String {
        // 1. Try file-based storage first (new approach).
        if let value = readFromFile(for: key), !value.isEmpty {
            return value
        }

        // 2. Migrate from current keychain service.
        if let value = readFromKeychain(for: key, service: service), !value.isEmpty {
            writeToFile(value, for: key)
            deleteFromKeychain(for: key, service: service)
            return value
        }

        // 3. Migrate from legacy keychain service.
        if let value = readFromKeychain(for: key, service: legacyService), !value.isEmpty {
            writeToFile(value, for: key)
            deleteFromKeychain(for: key, service: legacyService)
            return value
        }

        return ""
    }

    func setString(_ value: String, for key: String) {
        writeToFile(value, for: key)
        // Clean up any existing keychain entries so they don't
        // trigger password prompts on future launches.
        deleteFromKeychain(for: key, service: service)
        deleteFromKeychain(for: key, service: legacyService)
    }

    // MARK: - File-based storage

    private func fileURL(for key: String) -> URL {
        let sanitized = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return secretsDirectory.appendingPathComponent(sanitized)
    }

    private func readFromFile(for key: String) -> String? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func writeToFile(_ value: String, for key: String) {
        let dir = secretsDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Set directory permissions to owner-only (0700).
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: dir.path
            )
        } catch {
            return
        }
        let url = fileURL(for: key)
        do {
            try Data(value.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            // Set file permissions to owner-read/write only (0600).
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            // Fallback: try without completeFileProtection (macOS < 14).
            try? Data(value.utf8).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }

    // MARK: - Keychain (read-only, for migration)

    private func readFromKeychain(for key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(for key: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

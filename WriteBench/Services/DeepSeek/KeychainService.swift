import Foundation
import Security

enum KeychainService {
    private static let service = "com.chen.WriteBench.deepseek"
    private static let account = "api-key"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw GradingError.missingKey }
        let attributes: [String: Any] = [kSecValueData as String: Data(clean.utf8)]
        var updateQuery = query
        updateQuery[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(clean.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    static func load() throws -> String {
        var item = query
        item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { throw GradingError.missingKey }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }
    static func exists() -> Bool {
        var item = query; item[kSecReturnData as String] = false
        return SecItemCopyMatching(item as CFDictionary, nil) == errSecSuccess
    }
    static func remove() throws {
        var item = query
        item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unable to access secure storage")" }
}

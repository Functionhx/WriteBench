import Foundation
import Security

/// A pasted key works immediately, without requiring access to an older Keychain item.
/// Persistence is a separate, explicit user choice; the key is never stored in preferences.
@MainActor enum DeepSeekCredentials {
    private static var sessionKey: String?
    static var hasSessionKey: Bool { sessionKey != nil }
    static func use(_ value: String, remember: Bool) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GradingError.missingKey }
        sessionKey = key
        if remember { try KeychainService.save(key) }
    }
    static func load() throws -> String {
        if let sessionKey { return sessionKey }
        do { return try KeychainService.load() }
        catch let error as KeychainError where [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(error.status) {
            // An old development signature must not cause a system password prompt.
            throw GradingError.missingKey
        }
    }
    static func clearSession() { sessionKey = nil }
}

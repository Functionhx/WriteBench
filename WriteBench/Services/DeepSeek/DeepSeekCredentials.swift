import Foundation

/// Submission reads memory only. Secure storage is an explicit, asynchronous opt-in.
@MainActor enum DeepSeekCredentials {
    private static var sessionKey: String?
    private static let rememberPreference = "rememberDeepSeekKeyV2"
    static var hasSessionKey: Bool { sessionKey != nil }
    static func use(_ value: String, remember: Bool) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GradingError.missingKey }
        sessionKey = key
        // The caller performs optional persistence off the UI thread.
        if !remember { UserDefaults.standard.set(false, forKey: rememberPreference) }
    }
    static func remember(_ value: String) async throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try await Task.detached { try KeychainService.save(key) }.value
        UserDefaults.standard.set(true, forKey: rememberPreference)
    }
    static func restoreRememberedKey() async {
        guard sessionKey == nil, UserDefaults.standard.bool(forKey: rememberPreference) else { return }
        // Never migrate or touch legacy development-signature Keychain items.
        let restored = try? await Task.detached { try KeychainService.load() }.value
        if sessionKey == nil { sessionKey = restored }
    }
    static func load() throws -> String {
        guard let sessionKey else { throw GradingError.missingKey }
        return sessionKey
    }
    static func clearSession() { sessionKey = nil }
    static func forget() async throws {
        sessionKey = nil
        let remembered = UserDefaults.standard.bool(forKey: rememberPreference)
        UserDefaults.standard.set(false, forKey: rememberPreference)
        if remembered { try await Task.detached { try KeychainService.remove() }.value }
    }
}

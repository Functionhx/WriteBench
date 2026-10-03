import Foundation

/// Keep credentials out of drafts, backups, preferences, and logs.
@MainActor enum DeepSeekCredentials {
    private static var sessionKey: String?
    private static let rememberPreference = "rememberDeepSeekKeyV2"
    private(set) static var restoreError: String?
    static var hasSessionKey: Bool { sessionKey != nil }
    static func use(_ value: String, remember: Bool, defaults: UserDefaults = .standard) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GradingError.missingKey }
        sessionKey = key
        restoreError = nil
        // The caller performs optional persistence off the UI thread.
        if !remember { defaults.set(false, forKey: rememberPreference) }
    }
    static func remember(_ value: String) async throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try await Task.detached { try LocalCredentialStore.save(key) }.value
        UserDefaults.standard.set(true, forKey: rememberPreference)
        restoreError = nil
    }
    static func restoreRememberedKey() async {
        guard sessionKey == nil else { return }
        restoreError = nil
        do {
            let restored = try await Task.detached { try LocalCredentialStore.load() }.value
            if sessionKey == nil { sessionKey = restored }
        } catch {
            restoreError = "无法读取本机保存的 API Key：\(error.localizedDescription)"
        }
        // Import the previous opt-in Keychain key once, without prompting for a password.
        if sessionKey == nil, UserDefaults.standard.bool(forKey: rememberPreference) {
            do {
                let restored = try await Task.detached { try KeychainService.load() }.value
                if sessionKey == nil { sessionKey = restored }
                try await remember(restored)
                restoreError = nil
            } catch { restoreError = "无法读取以前的 Keychain Key：\(error.localizedDescription)" }
        }
        if sessionKey == nil, !UserDefaults.standard.bool(forKey: "legacyDeepSeekKeyMigrationComplete") {
            do {
                let legacy = try await Task.detached { try KeychainService.loadLegacy() }.value
                try await remember(legacy)
                if sessionKey == nil { sessionKey = legacy }
                UserDefaults.standard.set(true, forKey: "legacyDeepSeekKeyMigrationComplete")
                restoreError = nil
            } catch GradingError.missingKey { }
            catch { restoreError = "旧版 API Key 自动恢复失败：\(error.localizedDescription)" }
        }

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
        UserDefaults.standard.set(true, forKey: "legacyDeepSeekKeyMigrationComplete")
        try await Task.detached { try LocalCredentialStore.remove() }.value
        if remembered { try? await Task.detached { try KeychainService.remove() }.value }
        restoreError = nil
    }
}

/// Development builds have changing ad-hoc signatures. A private local file survives rebuilds.
/// This is a plain-text credential, restricted to the current macOS user (directory 0700, file 0600).
enum LocalCredentialStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WriteBench/Credentials", isDirectory: true)
    }
    static func save(_ key: String, directory: URL = directory) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw GradingError.missingKey }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let file = directory.appendingPathComponent("deepseek.key")
        try Data(clean.utf8).write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func load(directory: URL = directory) throws -> String? {
        let file = directory.appendingPathComponent("deepseek.key")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let key = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GradingError.missingKey }
        return key
    }
    static func remove(directory: URL = directory) throws {
        let file = directory.appendingPathComponent("deepseek.key")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

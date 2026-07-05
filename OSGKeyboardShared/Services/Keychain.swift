// Keychain.swift
// OSGKeyboard · Shared
//
// Single-purpose Keychain helper for the user's LLM API key.
//
// Why this exists
// ---------------
// Both the host app and the keyboard extension need to read the same API
// key (the host writes it in Settings; the extension uses it to
// authenticate LLM requests). Storing it in App Group `UserDefaults` is
// plaintext on disk and shows up in any unencrypted backup. The Keychain
// gives us at-rest encryption and proper lifecycle.
//
// Cross-process sharing
// ---------------------
// App and extension have different bundle IDs, so their default Keychain
// access groups differ and they cannot see each other's items out of the
// box. We add `com.apple.security.keychain-access-groups` to both
// targets' entitlements with the entry `com.osgkeyboard.shared`; this
// becomes each process's *first* (and therefore default) access group, so
// we never need to specify `kSecAttrAccessGroup` in queries — the system
// resolves it for us.
//
// Accessibility class
// -------------------
// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:
//   - Available after the user unlocks the device at least once after
//     boot (so background jobs work even with a locked phone).
//   - "ThisDeviceOnly" — does not migrate to a restored device and is
//     NOT included in iCloud Keychain. API keys should not sync.

import Foundation
import Security

public enum Keychain: @unchecked Sendable {

    public enum KeychainError: Error, Sendable, Equatable {
        case unexpectedStatus(OSStatus)
    }

    private static let service = "com.osgkeyboard.apikey"
    private static let legacyAccount = "current"
    private static let defaultProviderId = "openai"

    private static func account(for providerId: String) -> String {
        let trimmed = providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? defaultProviderId : trimmed.lowercased()
        return "provider.\(normalized)"
    }

    // MARK: - Read

    /// Read the stored API key. Returns `nil` when nothing is stored,
    /// or when the underlying call returns a non-success status we can't
    /// usefully surface (e.g. transient `errSecInteractionNotAllowed`).
    public static func apiKey(for providerId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: providerId),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                return nil
            }
            return str
        case errSecItemNotFound:
            return nil
        default:
            #if DEBUG
            print("⚠️ [OSGKeyboard] Keychain read returned OSStatus \(status); treating as no key.")
            #endif
            return nil
        }
    }

    /// Backward-compatible shorthand for the default cloud provider.
    public static func apiKey() -> String? {
        apiKey(for: defaultProviderId)
    }

    /// Legacy account used by older builds before provider-scoped keys.
    /// New code should avoid this and use `apiKey(for:)`.
    public static func legacyAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    // MARK: - Write

    /// Store (or update) the API key. An empty string deletes the entry,
    /// so clearing the field in the UI removes the key from the Keychain
    /// rather than leaving an empty-string placeholder.
    public static func setAPIKey(_ key: String, for providerId: String) throws {
        if key.isEmpty {
            try deleteAPIKey(for: providerId)
            return
        }
        let data = Data(key.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: providerId),
        ]
        // Try update first — covers the common path where the key already
        // exists (every settings edit after the first).
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // No existing item — add one with our accessibility class.
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Backward-compatible shorthand for the default cloud provider.
    public static func setAPIKey(_ key: String) throws {
        try setAPIKey(key, for: defaultProviderId)
    }

    // MARK: - Delete

    public static func deleteAPIKey(for providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: providerId),
        ]
        let status = SecItemDelete(query as CFDictionary)
        // `errSecItemNotFound` is success-from-the-user's-perspective — the
        // desired end state is "no key", which is what we already have.
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Backward-compatible shorthand for the default cloud provider.
    public static func deleteAPIKey() throws {
        try deleteAPIKey(for: defaultProviderId)
    }

    public static func deleteLegacyAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// Keychain.swift
// OSGKeyboard · Shared
//
// Keychain helper for LLM API keys and onboarding markers.
//
// API keys:
// - Local (device-only) items use `AfterFirstUnlockThisDeviceOnly`.
// - When settings iCloud sync is enabled, keys are stored as synchronizable
//   generic passwords (`kSecAttrSynchronizable = true`) and replicate through
//   the user's iCloud Keychain — never through KVS JSON.

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

    private static func baseQuery(providerId: String, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: providerId),
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    // MARK: - Read

    public static func apiKey(for providerId: String, preferICloudSync: Bool = false) -> String? {
        if preferICloudSync, let synced = readKey(providerId: providerId, synchronizable: true) {
            return synced
        }
        if let local = readKey(providerId: providerId, synchronizable: false) {
            return local
        }
        if preferICloudSync {
            return readKey(providerId: providerId, synchronizable: true)
        }
        return nil
    }

    public static func apiKey() -> String? {
        apiKey(for: defaultProviderId)
    }

    private static func readKey(providerId: String, synchronizable: Bool) -> String? {
        var query = baseQuery(providerId: providerId, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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

    public static func legacyAPIKey() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    // MARK: - Write

    public static func setAPIKey(_ key: String, for providerId: String, useICloudSync: Bool = false) throws {
        if key.isEmpty {
            try deleteAPIKey(for: providerId, useICloudSync: useICloudSync)
            return
        }
        if useICloudSync {
            try writeKey(key, providerId: providerId, synchronizable: true)
            try? deleteKey(providerId: providerId, synchronizable: false)
        } else {
            try writeKey(key, providerId: providerId, synchronizable: false)
        }
    }

    public static func setAPIKey(_ key: String) throws {
        try setAPIKey(key, for: defaultProviderId, useICloudSync: false)
    }

    private static func writeKey(_ key: String, providerId: String, synchronizable: Bool) throws {
        let data = Data(key.utf8)
        var baseQuery = baseQuery(providerId: providerId, synchronizable: synchronizable)
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            baseQuery[kSecValueData as String] = data
            baseQuery[kSecAttrAccessible as String] = synchronizable
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(baseQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    // MARK: - Delete

    public static func deleteAPIKey(for providerId: String, useICloudSync: Bool = false) throws {
        try deleteKey(providerId: providerId, synchronizable: false)
        if useICloudSync {
            try deleteKey(providerId: providerId, synchronizable: true)
        }
    }

    public static func deleteAPIKey(for providerId: String) throws {
        try deleteAPIKey(for: providerId, useICloudSync: false)
    }

    public static func deleteAPIKey() throws {
        try deleteAPIKey(for: defaultProviderId)
    }

    private static func deleteKey(providerId: String, synchronizable: Bool) throws {
        let query = baseQuery(providerId: providerId, synchronizable: synchronizable)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func deleteLegacyAPIKey() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Copy non-empty local keys into synchronizable Keychain items.
    public static func migrateLocalKeysToICloud() {
        for provider in LLMProvider.presets {
            guard let local = readKey(providerId: provider.id, synchronizable: false), !local.isEmpty else {
                continue
            }
            try? writeKey(local, providerId: provider.id, synchronizable: true)
            try? deleteKey(providerId: provider.id, synchronizable: false)
        }
    }

    // MARK: - Onboarding completion (reboot-durable flag)

    private static let onboardingService = "com.osgkeyboard.onboarding"
    private static let onboardingAccount = "hasCompletedOnboarding"

    public static func hasCompletedOnboarding() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: onboardingService,
            kSecAttrAccount as String: onboardingAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            OSGLog.config.info("[onboarding] Keychain read: status=\(status, privacy: .public) → false")
            return false
        }
        let completed = str == "1"
        OSGLog.config.info(
            "[onboarding] Keychain read: status=ok value=\(str, privacy: .public) → \(completed, privacy: .public)"
        )
        return completed
    }

    public static func setOnboardingCompleted(_ completed: Bool) {
        guard hasCompletedOnboarding() != completed else {
            OSGLog.config.info("[onboarding] Keychain write skipped (already \(completed, privacy: .public))")
            return
        }

        var baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: onboardingService,
            kSecAttrAccount as String: onboardingAccount,
        ]
        #if os(macOS)
        baseQuery[kSecUseDataProtectionKeychain as String] = true
        #endif

        guard completed else {
            let delStatus = SecItemDelete(baseQuery as CFDictionary)
            OSGLog.config.info("[onboarding] Keychain delete: status=\(delStatus, privacy: .public)")
            return
        }

        let data = Data("1".utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            OSGLog.config.info("[onboarding] Keychain add: status=\(addStatus, privacy: .public)")
        } else {
            OSGLog.config.info("[onboarding] Keychain update: status=\(updateStatus, privacy: .public)")
        }
    }
}

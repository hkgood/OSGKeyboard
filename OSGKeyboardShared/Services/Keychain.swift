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

    private static func normalizedProviderId(_ providerId: String) -> String {
        let trimmed = providerId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultProviderId : trimmed.lowercased()
    }

    /// LLM polish credentials (`provider.<id>`).
    private static func account(for providerId: String) -> String {
        "provider.\(normalizedProviderId(providerId))"
    }

    /// Cloud ASR credentials (`asr.<id>`), independent from polish keys.
    private static func asrAccount(for providerId: String) -> String {
        "asr.\(normalizedProviderId(providerId))"
    }

    // NOTE on kSecAttrAccessGroup: we deliberately rely on the DEFAULT
    // access group (the first entry in each target's keychain-access-groups,
    // which project.yml pins to `$(AppIdentifierPrefix)com.osgkeyboard.shared`
    // for every target). Setting the attribute explicitly would require the
    // team-prefixed string at runtime, which is not portably available
    // without injecting TeamID through the build system. If a SECOND access
    // group is ever added to any target, revisit this — reordered groups
    // would silently change which store these queries hit.
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

    // MARK: - ASR keys

    public static func asrApiKey(for providerId: String, preferICloudSync: Bool = false) -> String? {
        if preferICloudSync, let synced = readASRKey(providerId: providerId, synchronizable: true) {
            return synced
        }
        if let local = readASRKey(providerId: providerId, synchronizable: false) {
            return local
        }
        if preferICloudSync {
            return readASRKey(providerId: providerId, synchronizable: true)
        }
        return nil
    }

    public static func asrApiKeyOutcome(
        for providerId: String,
        preferICloudSync: Bool = false
    ) -> ReadOutcome {
        let first = readASRKeyOutcome(providerId: providerId, synchronizable: preferICloudSync)
        if case .found = first { return first }
        let second = readASRKeyOutcome(providerId: providerId, synchronizable: !preferICloudSync)
        if case .found = second { return second }
        if case .unavailable = first { return first }
        if case .unavailable = second { return second }
        return .notFound
    }

    public static func setASRAPIKey(_ key: String, for providerId: String, useICloudSync: Bool = false) throws {
        if key.isEmpty {
            try deleteASRAPIKey(for: providerId, useICloudSync: useICloudSync)
            return
        }
        if useICloudSync {
            try writeASRKey(key, providerId: providerId, synchronizable: true)
            try? deleteASRKey(providerId: providerId, synchronizable: false)
        } else {
            try writeASRKey(key, providerId: providerId, synchronizable: false)
        }
    }

    public static func deleteASRAPIKey(for providerId: String, useICloudSync: Bool = false) throws {
        try deleteASRKey(providerId: providerId, synchronizable: false)
        if useICloudSync {
            try deleteASRKey(providerId: providerId, synchronizable: true)
        }
    }

    private static func readASRKey(providerId: String, synchronizable: Bool) -> String? {
        if case .found(let value) = readASRKeyOutcome(providerId: providerId, synchronizable: synchronizable) {
            return value
        }
        return nil
    }

    private static func readASRKeyOutcome(providerId: String, synchronizable: Bool) -> ReadOutcome {
        var query = baseASRQuery(providerId: providerId, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                return .notFound
            }
            return .found(str)
        case errSecItemNotFound:
            // Pre-split installs stored one key under `provider.<id>` for both stages.
            return readKeyOutcome(providerId: providerId, synchronizable: synchronizable)
        default:
            #if DEBUG
            print("⚠️ [OSGKeyboard] ASR Keychain read returned OSStatus \(status); reporting unavailable.")
            #endif
            return .unavailable(status)
        }
    }

    private static func baseASRQuery(providerId: String, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: asrAccount(for: providerId),
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private static func writeASRKey(_ key: String, providerId: String, synchronizable: Bool) throws {
        let data = Data(key.utf8)
        var baseQuery = baseASRQuery(providerId: providerId, synchronizable: synchronizable)
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

    private static func deleteASRKey(providerId: String, synchronizable: Bool) throws {
        let query = baseASRQuery(providerId: providerId, synchronizable: synchronizable)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - LLM keys

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

    /// Distinguishes "no key stored" from "keychain temporarily unreadable".
    public enum ReadOutcome: Equatable {
        case found(String)
        case notFound
        /// The keychain could not be read (e.g. `errSecInteractionNotAllowed`
        /// while the device is locked before first unlock). NOT the same as
        /// "no key configured" — telling the user to re-enter their key in
        /// this state would be wrong; the read succeeds once unlocked.
        case unavailable(OSStatus)
    }

    /// Like `apiKey(for:)`, but reports WHY a key was not returned so
    /// callers can distinguish a missing key (user action needed) from a
    /// transiently locked keychain (retry later).
    public static func apiKeyOutcome(
        for providerId: String,
        preferICloudSync: Bool = false
    ) -> ReadOutcome {
        let first = readKeyOutcome(providerId: providerId, synchronizable: preferICloudSync)
        if case .found = first { return first }
        let second = readKeyOutcome(providerId: providerId, synchronizable: !preferICloudSync)
        if case .found = second { return second }
        // Neither store had it: surface "unavailable" when either read was
        // blocked, since the key may well exist behind the lock.
        if case .unavailable = first { return first }
        if case .unavailable = second { return second }
        return .notFound
    }

    private static func readKey(providerId: String, synchronizable: Bool) -> String? {
        if case .found(let value) = readKeyOutcome(providerId: providerId, synchronizable: synchronizable) {
            return value
        }
        return nil
    }

    private static func readKeyOutcome(providerId: String, synchronizable: Bool) -> ReadOutcome {
        var query = baseQuery(providerId: providerId, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                return .notFound
            }
            return .found(str)
        case errSecItemNotFound:
            return .notFound
        default:
            #if DEBUG
            print("⚠️ [OSGKeyboard] Keychain read returned OSStatus \(status); reporting unavailable.")
            #endif
            return .unavailable(status)
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
        for provider in LLMProvider.asrSelectablePresets {
            guard let local = readASRKey(providerId: provider.id, synchronizable: false), !local.isEmpty else {
                continue
            }
            try? writeASRKey(local, providerId: provider.id, synchronizable: true)
            try? deleteASRKey(providerId: provider.id, synchronizable: false)
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

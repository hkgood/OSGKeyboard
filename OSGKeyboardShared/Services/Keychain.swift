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

    public enum CredentialMigrationError: Error, Sendable, Equatable {
        case unavailable
        case conflict
        case verificationFailed
    }

    typealias CredentialRead = () throws -> String?
    typealias CredentialWrite = (String) throws -> Void

    private static let service = "com.osgkeyboard.apikey"
    private static let legacyAccount = "current"
    /// Must match `AppGroupConfiguration.defaultPolishProviderId` so bare
    /// `apiKey()` / `setAPIKey(_:)` hit the same account the host/ext use.
    private static let defaultProviderId = AppGroupConfiguration.defaultPolishProviderId

    // MARK: - XCTest unsigned-host fallback
    //
    // `CODE_SIGNING_ALLOWED=NO` (historical test runner) omits entitlements, so
    // SecItem returns `errSecMissingEntitlement` (-34018). That aborts Keychain
    // tests and turns "missing key" into `keychainLocked`. While XCTest is
    // loaded, fall back to a process-local map so the hermetic suite stays
    // deterministic; production / signed hosts never take this path.

    private static let memoryLock = NSLock()
    /// Protected by `memoryLock`; marked unsafe for Swift 6 global mutability rules.
    nonisolated(unsafe) private static var memoryStore: [String: String] = [:]

    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    private static func memorySlot(account: String, synchronizable: Bool) -> String {
        "\(synchronizable ? "s" : "l")|\(service)|\(account)"
    }

    private static func memoryRead(account: String, synchronizable: Bool) -> String? {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        return memoryStore[memorySlot(account: account, synchronizable: synchronizable)]
    }

    private static func memoryWrite(_ value: String, account: String, synchronizable: Bool) {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        memoryStore[memorySlot(account: account, synchronizable: synchronizable)] = value
    }

    private static func memoryDelete(account: String, synchronizable: Bool) {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        memoryStore.removeValue(forKey: memorySlot(account: account, synchronizable: synchronizable))
    }

    /// Clears the XCTest in-memory Keychain map. Call from test `setUp` so
    /// provider-scoped leftovers (sync + local) cannot leak across cases.
    public static func resetTestMemoryStore() {
        guard isRunningUnderXCTest else { return }
        memoryLock.lock()
        defer { memoryLock.unlock() }
        memoryStore.removeAll()
    }

    private static func shouldUseMemoryFallback(for status: OSStatus) -> Bool {
        #if DEBUG
        isRunningUnderXCTest && status == errSecMissingEntitlement
        #else
        false
        #endif
    }

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
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
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
            try writeMirroredCredential(
                key,
                readLocal: {
                    try migrationValue(
                        from: readASRKeyOutcome(
                            providerId: providerId,
                            synchronizable: false,
                            fallbackToLegacyProviderAccount: false
                        )
                    )
                },
                readSynchronizable: {
                    try migrationValue(
                        from: readASRKeyOutcome(
                            providerId: providerId,
                            synchronizable: true,
                            fallbackToLegacyProviderAccount: false
                        )
                    )
                },
                writeLocal: { try writeASRKey($0, providerId: providerId, synchronizable: false) },
                writeSynchronizable: {
                    try writeASRKey($0, providerId: providerId, synchronizable: true)
                },
                deleteLocal: { try deleteASRKey(providerId: providerId, synchronizable: false) },
                deleteSynchronizable: {
                    try deleteASRKey(providerId: providerId, synchronizable: true)
                }
            )
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

    private static func readASRKeyOutcome(
        providerId: String,
        synchronizable: Bool,
        fallbackToLegacyProviderAccount: Bool = true
    ) -> ReadOutcome {
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
            return fallbackToLegacyProviderAccount
                ? readKeyOutcome(providerId: providerId, synchronizable: synchronizable)
                : .notFound
        default:
            if shouldUseMemoryFallback(for: status) {
                if let value = memoryRead(account: asrAccount(for: providerId), synchronizable: synchronizable) {
                    return .found(value)
                }
                // Pre-split installs: fall through to polish-key account.
                return fallbackToLegacyProviderAccount
                    ? readKeyOutcome(providerId: providerId, synchronizable: synchronizable)
                    : .notFound
            }
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
            kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
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
            if addStatus == errSecSuccess { return }
            if shouldUseMemoryFallback(for: addStatus) {
                memoryWrite(key, account: asrAccount(for: providerId), synchronizable: synchronizable)
                return
            }
            throw KeychainError.unexpectedStatus(addStatus)
        default:
            if shouldUseMemoryFallback(for: updateStatus) {
                memoryWrite(key, account: asrAccount(for: providerId), synchronizable: synchronizable)
                return
            }
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    private static func deleteASRKey(providerId: String, synchronizable: Bool) throws {
        let query = baseASRQuery(providerId: providerId, synchronizable: synchronizable)
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        if shouldUseMemoryFallback(for: status) {
            memoryDelete(account: asrAccount(for: providerId), synchronizable: synchronizable)
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    // MARK: - LLM keys

    /// Reads synchronizable then local when iCloud is preferred (retrying sync
    /// after local miss); otherwise reads local only. This optional API folds
    /// locked/unavailable into nil—use `apiKeyOutcome` when that distinction matters.
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
            if shouldUseMemoryFallback(for: status) {
                if let value = memoryRead(account: account(for: providerId), synchronizable: synchronizable) {
                    return .found(value)
                }
                return .notFound
            }
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
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        if shouldUseMemoryFallback(for: status) {
            return memoryRead(account: legacyAccount, synchronizable: false)
        }
        return nil
    }

    // MARK: - Write

    /// An empty value deletes the selected storage. A synchronized write
    /// removes its local counterpart; a local write leaves any synchronized
    /// counterpart intact until an explicit sync migration or deletion.
    public static func setAPIKey(_ key: String, for providerId: String, useICloudSync: Bool = false) throws {
        if key.isEmpty {
            try deleteAPIKey(for: providerId, useICloudSync: useICloudSync)
            return
        }
        if useICloudSync {
            try writeMirroredCredential(
                key,
                readLocal: {
                    try migrationValue(
                        from: readKeyOutcome(providerId: providerId, synchronizable: false)
                    )
                },
                readSynchronizable: {
                    try migrationValue(
                        from: readKeyOutcome(providerId: providerId, synchronizable: true)
                    )
                },
                writeLocal: { try writeKey($0, providerId: providerId, synchronizable: false) },
                writeSynchronizable: {
                    try writeKey($0, providerId: providerId, synchronizable: true)
                },
                deleteLocal: { try deleteKey(providerId: providerId, synchronizable: false) },
                deleteSynchronizable: {
                    try deleteKey(providerId: providerId, synchronizable: true)
                }
            )
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
            if addStatus == errSecSuccess { return }
            if shouldUseMemoryFallback(for: addStatus) {
                memoryWrite(key, account: account(for: providerId), synchronizable: synchronizable)
                return
            }
            throw KeychainError.unexpectedStatus(addStatus)
        default:
            if shouldUseMemoryFallback(for: updateStatus) {
                memoryWrite(key, account: account(for: providerId), synchronizable: synchronizable)
                return
            }
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
        if status == errSecSuccess || status == errSecItemNotFound { return }
        if shouldUseMemoryFallback(for: status) {
            memoryDelete(account: account(for: providerId), synchronizable: synchronizable)
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    public static func deleteLegacyAPIKey() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: legacyAccount
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        if shouldUseMemoryFallback(for: status) {
            memoryDelete(account: legacyAccount, synchronizable: false)
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    // MARK: - Credential migration

    /// Writes the same explicit user value to device-only and synchronizable
    /// stores. Any failure restores both previous values before returning.
    static func writeMirroredCredential(
        _ value: String,
        readLocal: CredentialRead,
        readSynchronizable: CredentialRead,
        writeLocal: CredentialWrite,
        writeSynchronizable: CredentialWrite,
        deleteLocal: () throws -> Void,
        deleteSynchronizable: () throws -> Void
    ) throws {
        let previousLocal = try migrationOperation(readLocal)
        let previousSynchronizable = try migrationOperation(readSynchronizable)
        do {
            try migrationOperation { try writeLocal(value) }
            guard try migrationOperation(readLocal) == value else {
                throw CredentialMigrationError.verificationFailed
            }
            try migrationOperation { try writeSynchronizable(value) }
            guard try migrationOperation(readSynchronizable) == value else {
                throw CredentialMigrationError.verificationFailed
            }
        } catch {
            let originalError = (error as? CredentialMigrationError) ?? .unavailable
            var restoreFailed = false
            do {
                try restoreCredential(
                    previousLocal,
                    write: writeLocal,
                    delete: deleteLocal
                )
            } catch {
                restoreFailed = true
            }
            do {
                try restoreCredential(
                    previousSynchronizable,
                    write: writeSynchronizable,
                    delete: deleteSynchronizable
                )
            } catch {
                restoreFailed = true
            }
            if restoreFailed {
                throw CredentialMigrationError.unavailable
            }
            throw originalError
        }
    }

    /// Pure copy/verify/delete transaction. Tests inject each operation so
    /// failure paths never need to manipulate or expose real credentials.
    @discardableResult
    static func copyCredentialTransaction(
        source: CredentialRead,
        destination: CredentialRead,
        writeDestination: CredentialWrite,
        readbackDestination: CredentialRead,
        deleteSource: () throws -> Void
    ) throws -> String? {
        let sourceValue = try migrationOperation(source)
        guard let sourceValue, !sourceValue.isEmpty else { return nil }

        if let destinationValue = try migrationOperation(destination),
           destinationValue != sourceValue {
            throw CredentialMigrationError.conflict
        }

        try migrationOperation {
            try writeDestination(sourceValue)
        }
        let readback = try migrationOperation(readbackDestination)
        guard readback == sourceValue else {
            throw CredentialMigrationError.verificationFailed
        }
        try migrationOperation(deleteSource)
        return sourceValue
    }

    /// Copy non-empty local LLM and ASR keys into synchronizable items.
    /// Device-only shadow copies are retained for a safe sync disable.
    public static func migrateLocalKeysToICloud() throws {
        try migrateAllCredentials(
            sourceSynchronizable: false,
            destinationSynchronizable: true,
            deleteSourcesAfterVerification: false
        )
    }

    /// Copy synchronizable LLM and ASR keys back to device-only items before
    /// settings sync is disabled.
    public static func migrateICloudKeysToLocal() throws {
        try migrateAllCredentials(
            sourceSynchronizable: true,
            destinationSynchronizable: false,
            deleteSourcesAfterVerification: true
        )
    }

    /// Stores a legacy plaintext value in the selected provider account and
    /// verifies it. The caller remains responsible for deleting its source.
    static func copyAPIKeyToSelectedStorage(
        _ key: String,
        providerId: String,
        useICloudSync: Bool
    ) throws {
        _ = try copyCredentialTransaction(
            source: { key },
            destination: {
                try migrationValue(
                    from: readKeyOutcome(providerId: providerId, synchronizable: useICloudSync)
                )
            },
            writeDestination: { value in
                try setAPIKey(value, for: providerId, useICloudSync: useICloudSync)
            },
            readbackDestination: {
                try migrationValue(
                    from: readKeyOutcome(providerId: providerId, synchronizable: useICloudSync)
                )
            },
            deleteSource: {}
        )
    }

    /// Safely migrates the legacy `current` account into the selected provider
    /// account. A failed write or unavailable Keychain leaves the source intact.
    static func migrateLegacyAPIKey(
        to providerId: String,
        useICloudSync: Bool
    ) throws {
        _ = try copyCredentialTransaction(
            source: { legacyAPIKey() },
            destination: {
                try migrationValue(
                    from: readKeyOutcome(providerId: providerId, synchronizable: useICloudSync)
                )
            },
            writeDestination: { value in
                try setAPIKey(value, for: providerId, useICloudSync: useICloudSync)
            },
            readbackDestination: {
                try migrationValue(
                    from: readKeyOutcome(providerId: providerId, synchronizable: useICloudSync)
                )
            },
            deleteSource: {
                try deleteLegacyAPIKey()
            }
        )
    }

    /// Copies the retired qwen ASR credential into bailian without deleting
    /// either qwen account, which may still be needed by LLM or rollback paths.
    static func copyQwenASRKeyToBailian(useICloudSync: Bool) throws {
        _ = try copyCredentialTransaction(
            source: {
                if let dedicated = try preferredMigrationValue(
                    providerId: "qwen",
                    synchronizable: useICloudSync,
                    asr: true
                ) {
                    return dedicated
                }
                return try preferredMigrationValue(
                    providerId: "qwen",
                    synchronizable: useICloudSync,
                    asr: false
                )
            },
            destination: {
                try migrationValue(
                    from: readASRKeyOutcome(
                        providerId: "bailian",
                        synchronizable: useICloudSync,
                        fallbackToLegacyProviderAccount: false
                    )
                )
            },
            writeDestination: { value in
                try setASRAPIKey(value, for: "bailian", useICloudSync: useICloudSync)
            },
            readbackDestination: {
                try migrationValue(
                    from: readASRKeyOutcome(
                        providerId: "bailian",
                        synchronizable: useICloudSync,
                        fallbackToLegacyProviderAccount: false
                    )
                )
            },
            deleteSource: {}
        )
    }

    private static func migrateAllCredentials(
        sourceSynchronizable: Bool,
        destinationSynchronizable: Bool,
        deleteSourcesAfterVerification: Bool
    ) throws {
        var verifiedSources: [(providerId: String, asr: Bool)] = []
        for providerId in Set(LLMProvider.presets.map(\.id)).sorted() {
            if try copyCredential(
                providerId: providerId,
                sourceSynchronizable: sourceSynchronizable,
                destinationSynchronizable: destinationSynchronizable,
                asr: false
            ) {
                verifiedSources.append((providerId, false))
            }
        }
        let asrProviderIds = Set(
            (LLMProvider.presets + LLMProvider.asrSelectablePresets).map(\.id)
        )
        for providerId in asrProviderIds.sorted() {
            if try copyCredential(
                providerId: providerId,
                sourceSynchronizable: sourceSynchronizable,
                destinationSynchronizable: destinationSynchronizable,
                asr: true
            ) {
                verifiedSources.append((providerId, true))
            }
        }
        guard deleteSourcesAfterVerification else { return }
        var cleanupFailed = false
        for source in verifiedSources {
            do {
                if source.asr {
                    try deleteASRKey(
                        providerId: source.providerId,
                        synchronizable: sourceSynchronizable
                    )
                } else {
                    try deleteKey(
                        providerId: source.providerId,
                        synchronizable: sourceSynchronizable
                    )
                }
            } catch {
                cleanupFailed = true
                // Every destination has already been verified, so a retained
                // source is a harmless shadow that a later migration can retry.
                OSGLog.config.warning(
                    "credential source cleanup deferred provider=\(source.providerId, privacy: .public)"
                )
            }
        }
        if cleanupFailed {
            throw CredentialMigrationError.unavailable
        }
    }

    private static func copyCredential(
        providerId: String,
        sourceSynchronizable: Bool,
        destinationSynchronizable: Bool,
        asr: Bool
    ) throws -> Bool {
        let copied = try copyCredentialTransaction(
            source: {
                try migrationValue(
                    from: asr
                        ? readASRKeyOutcome(
                            providerId: providerId,
                            synchronizable: sourceSynchronizable,
                            fallbackToLegacyProviderAccount: false
                        )
                        : readKeyOutcome(providerId: providerId, synchronizable: sourceSynchronizable)
                )
            },
            destination: {
                try migrationValue(
                    from: asr
                        ? readASRKeyOutcome(
                            providerId: providerId,
                            synchronizable: destinationSynchronizable,
                            fallbackToLegacyProviderAccount: false
                        )
                        : readKeyOutcome(providerId: providerId, synchronizable: destinationSynchronizable)
                )
            },
            writeDestination: { value in
                if asr {
                    try writeASRKey(
                        value,
                        providerId: providerId,
                        synchronizable: destinationSynchronizable
                    )
                } else {
                    try writeKey(
                        value,
                        providerId: providerId,
                        synchronizable: destinationSynchronizable
                    )
                }
            },
            readbackDestination: {
                try migrationValue(
                    from: asr
                        ? readASRKeyOutcome(
                            providerId: providerId,
                            synchronizable: destinationSynchronizable,
                            fallbackToLegacyProviderAccount: false
                        )
                        : readKeyOutcome(providerId: providerId, synchronizable: destinationSynchronizable)
                )
            },
            deleteSource: {}
        )
        return copied != nil
    }

    private static func preferredMigrationValue(
        providerId: String,
        synchronizable: Bool,
        asr: Bool
    ) throws -> String? {
        let preferred = try migrationValue(
            from: asr
                ? readASRKeyOutcome(
                    providerId: providerId,
                    synchronizable: synchronizable,
                    fallbackToLegacyProviderAccount: false
                )
                : readKeyOutcome(providerId: providerId, synchronizable: synchronizable)
        )
        if let preferred, !preferred.isEmpty { return preferred }
        return try migrationValue(
            from: asr
                ? readASRKeyOutcome(
                    providerId: providerId,
                    synchronizable: !synchronizable,
                    fallbackToLegacyProviderAccount: false
                )
                : readKeyOutcome(providerId: providerId, synchronizable: !synchronizable)
        )
    }

    private static func migrationValue(from outcome: ReadOutcome) throws -> String? {
        switch outcome {
        case .found(let value):
            return value
        case .notFound:
            return nil
        case .unavailable:
            throw CredentialMigrationError.unavailable
        }
    }

    private static func migrationOperation<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch let error as CredentialMigrationError {
            throw error
        } catch {
            throw CredentialMigrationError.unavailable
        }
    }

    private static func restoreCredential(
        _ previousValue: String?,
        write: CredentialWrite,
        delete: () throws -> Void
    ) throws {
        if let previousValue {
            try write(previousValue)
        } else {
            try delete()
        }
    }

    // MARK: - Onboarding completion (reboot-durable flag)

    private static let onboardingService = "com.osgkeyboard.onboarding"
    private static let onboardingAccount = "hasCompletedOnboarding"
    /// Survives reboots but is wiped with the app container (unlike Keychain).
    private static let installIdentityKey = "osgkeyboard.installIdentity"

    /// Call once at config init. Returns `true` when this is a brand-new app
    /// container (first launch or reinstall after delete). Clears a stale
    /// Keychain onboarding flag so deleted installs show the welcome flow again.
    @discardableResult
    public static func beginInstallIdentityIfNeeded() -> Bool {
        let standard = UserDefaults.standard
        if standard.string(forKey: installIdentityKey) != nil {
            return false
        }
        standard.set(UUID().uuidString, forKey: installIdentityKey)
        if hasCompletedOnboarding() {
            setOnboardingCompleted(false)
            OSGLog.config.info("[onboarding] fresh install: cleared stale Keychain onboarding flag")
        } else {
            OSGLog.config.info("[onboarding] fresh install: install identity created")
        }
        return true
    }

    public static func hasCompletedOnboarding() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: onboardingService,
            kSecAttrAccount as String: onboardingAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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
            kSecAttrAccount as String: onboardingAccount
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

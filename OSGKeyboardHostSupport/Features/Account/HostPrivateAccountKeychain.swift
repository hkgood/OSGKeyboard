// HostPrivateAccountKeychain.swift
// OSGKeyboard · HostSupport
//
// Main-app-only storage for OSG account sessions and App Attest key state.

import Foundation
import OSLog
import Security

public struct HostPrivateAccountKeychainDescriptor: Equatable, Sendable {
    public static let defaultService = "com.osgkeyboard.ios.account"
    public static let hostBundleIdentifier = "com.osgkeyboard.ios"
    /// The macOS menu-bar app has no extension to share with, so it owns its
    /// own private group. Listed here so the guard below still rejects the
    /// App-Group-reachable `com.osgkeyboard.shared` group on both platforms.
    public static let macHostBundleIdentifier = "com.osgkeyboard.mac"

    public let service: String
    public let accessGroup: String

    public init(
        service: String = Self.defaultService,
        accessGroup: String
    ) throws {
        let normalizedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccessGroup = accessGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHostPrivate = [Self.hostBundleIdentifier, Self.macHostBundleIdentifier]
            .contains { normalizedAccessGroup.hasSuffix(".\($0)") }
        guard !normalizedService.isEmpty,
              isHostPrivate,
              !normalizedAccessGroup.hasSuffix(".com.osgkeyboard.shared") else {
            throw AccountAPIError.secureStorage
        }
        self.service = normalizedService
        self.accessGroup = normalizedAccessGroup
    }

    /// The prefix is the signed App Identifier Prefix, including or excluding
    /// its trailing period. It must come from host-app build configuration.
    public static func hostApplication(appIdentifierPrefix: String) throws -> Self {
        let prefix = appIdentifierPrefix.hasSuffix(".")
            ? appIdentifierPrefix
            : "\(appIdentifierPrefix)."
        return try Self(accessGroup: "\(prefix)\(hostBundleIdentifier)")
    }
}

public actor HostPrivateAccountKeychain:
    AccountSessionVault,
    AppleUserIdentifierStoring,
    AppAttestKeyStateStoring,
    OOBEInstallationIDStoring {
    private static let logger = Logger(
        subsystem: HostPrivateAccountKeychainDescriptor.hostBundleIdentifier,
        category: "account"
    )

    private enum Account {
        static let session = "account.session"
        static let refreshTransaction = "account.refresh-transaction"
        static let appleUserIdentifier = "account.apple-user-identifier"
        static let appAttestKeyState = "integrity.app-attest-key-state"
        static let oobeInstallationID = "oobe.installation-id"
    }

    let descriptor: HostPrivateAccountKeychainDescriptor
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(descriptor: HostPrivateAccountKeychainDescriptor) {
        self.descriptor = descriptor
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func loadSession() async throws -> AccountTokenSession? {
        do {
            let session = try read(AccountTokenSession.self, account: Account.session)
            Self.logger.info(
                "session keychain restore status=\(session == nil ? "not-found" : "found", privacy: .public)"
            )
            return session
        } catch {
            Self.logger.error("session keychain restore status=unavailable")
            throw error
        }
    }

    public func saveSession(_ session: AccountTokenSession) async throws {
        try write(session, account: Account.session)
    }

    public func clearSession() async throws {
        try delete(account: Account.session)
    }

    public func beginRefreshTransaction(
        refreshTokenDigest: String
    ) async throws -> AccountRefreshTransaction {
        if let existing = try read(
            AccountRefreshTransaction.self,
            account: Account.refreshTransaction
        ), existing.refreshTokenDigest == refreshTokenDigest {
            return existing
        }
        let transaction = AccountRefreshTransaction(
            refreshTokenDigest: refreshTokenDigest,
            operationId: UUID()
        )
        try write(transaction, account: Account.refreshTransaction)
        return transaction
    }

    public func clearRefreshTransaction() async throws {
        try delete(account: Account.refreshTransaction)
    }

    public func loadAppleUserIdentifier() async throws -> String? {
        try read(String.self, account: Account.appleUserIdentifier)
    }

    public func saveAppleUserIdentifier(_ userIdentifier: String) async throws {
        try write(userIdentifier, account: Account.appleUserIdentifier)
    }

    public func clearAppleUserIdentifier() async throws {
        try delete(account: Account.appleUserIdentifier)
    }

    public func loadAppAttestKeyState() async throws -> AppAttestKeyState? {
        try read(AppAttestKeyState.self, account: Account.appAttestKeyState)
    }

    public func saveAppAttestKeyState(_ state: AppAttestKeyState) async throws {
        try write(state, account: Account.appAttestKeyState)
    }

    public func clearAppAttestKeyState() async throws {
        try delete(account: Account.appAttestKeyState)
    }

    public func oobeInstallationID() async throws -> UUID {
        if let existing = try read(UUID.self, account: Account.oobeInstallationID) {
            return existing
        }
        let created = UUID()
        try write(created, account: Account.oobeInstallationID)
        return created
    }

    private func read<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw AccountAPIError.secureStorage
            }
            do {
                return try decoder.decode(type, from: data)
            } catch {
                throw AccountAPIError.secureStorage
            }
        case errSecItemNotFound:
            return nil
        default:
            Self.logger.error(
                "keychain read failed account=\(account, privacy: .public) status=\(status, privacy: .public)"
            )
            throw AccountAPIError.secureStorage
        }
    }

    private func write<Value: Encodable>(_ value: Value, account: String) throws {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw AccountAPIError.secureStorage
        }

        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AccountAPIError.secureStorage
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw AccountAPIError.secureStorage
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccountAPIError.secureStorage
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: descriptor.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: descriptor.accessGroup,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        #if os(macOS)
        // macOS defaults to the legacy file-based keychain, which ignores
        // `kSecAttrAccessGroup` and rejects `kSecAttrAccessible`. Opt into the
        // data-protection keychain so entitlement-scoped access groups and the
        // AfterFirstUnlockThisDeviceOnly protection behave as they do on iOS.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

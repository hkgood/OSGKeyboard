// HostPrivateAccountKeychain.swift
// OSGKeyboard · HostSupport
//
// Main-app-only storage for OSG account sessions and App Attest key state.

import Foundation
import Security

public struct HostPrivateAccountKeychainDescriptor: Equatable, Sendable {
    public static let defaultService = "com.osgkeyboard.ios.account"
    public static let hostBundleIdentifier = "com.osgkeyboard.ios"

    public let service: String
    public let accessGroup: String

    public init(
        service: String = Self.defaultService,
        accessGroup: String
    ) throws {
        let normalizedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccessGroup = accessGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedService.isEmpty,
              normalizedAccessGroup.hasSuffix(".\(Self.hostBundleIdentifier)"),
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

public actor HostPrivateAccountKeychain: AccountSessionVault, AppAttestKeyStateStoring {
    private enum Account {
        static let session = "account.session"
        static let appAttestKeyState = "integrity.app-attest-key-state"
    }

    let descriptor: HostPrivateAccountKeychainDescriptor
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(descriptor: HostPrivateAccountKeychainDescriptor) {
        self.descriptor = descriptor
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func loadSession() async throws -> AccountSession? {
        try read(AccountSession.self, account: Account.session)
    }

    public func saveSession(_ session: AccountSession) async throws {
        try write(session, account: Account.session)
    }

    public func clearSession() async throws {
        try delete(account: Account.session)
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
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: descriptor.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: descriptor.accessGroup,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
    }
}

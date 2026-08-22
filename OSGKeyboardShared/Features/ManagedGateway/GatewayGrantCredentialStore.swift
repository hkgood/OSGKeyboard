// GatewayGrantCredentialStore.swift
// OSGKeyboard · Shared
//
// Shared Keychain storage dedicated to scope-limited gateway grants. Account
// session credentials intentionally never enter this service or access group item.

import Foundation
import Security

public protocol GatewayGrantCredentialStore: Sendable {
    func load() async throws -> ManagedGatewayGrantCredentials?
    func save(_ credentials: ManagedGatewayGrantCredentials) async throws
    func delete() async throws
}

public struct GatewayGrantKeychainStore: GatewayGrantCredentialStore, @unchecked Sendable {
    public enum Slot: String, Sendable {
        case account = "scope-limited.active"
        case oobe = "scope-limited.oobe"
    }

    public enum StoreError: Error, Equatable, Sendable {
        case unexpectedStatus(OSStatus)
        case invalidStoredValue
    }

    private static let service = "com.osgkeyboard.gateway-grant"
    private let slot: Slot

    public init(slot: Slot = .account) {
        self.slot = slot
    }

    public func load() async throws -> ManagedGatewayGrantCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = try? Self.decoder.decode(
                      ManagedGatewayGrantCredentials.self,
                      from: data
                  ) else {
                throw StoreError.invalidStoredValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.unexpectedStatus(status)
        }
    }

    public func save(_ credentials: ManagedGatewayGrantCredentials) async throws {
        let data = try Self.encoder.encode(credentials)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            // The extension can refresh after reboot without making account
            // credentials readable; this item contains only the limited grant.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.unexpectedStatus(addStatus)
            }
        default:
            throw StoreError.unexpectedStatus(updateStatus)
        }
    }

    public func delete() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: slot.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Dedicated extension-readable slot for anonymous onboarding grants. It can
/// never overwrite or load the signed-in account's normal managed grant.
public struct OOBEGatewayGrantKeychainStore: GatewayGrantCredentialStore, Sendable {
    private let storage = GatewayGrantKeychainStore(slot: .oobe)

    public init() {}

    public func load() async throws -> ManagedGatewayGrantCredentials? {
        try await storage.load()
    }

    public func save(_ credentials: ManagedGatewayGrantCredentials) async throws {
        try await storage.save(credentials)
    }

    public func delete() async throws {
        try await storage.delete()
    }
}

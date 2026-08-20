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
    public enum StoreError: Error, Equatable, Sendable {
        case unexpectedStatus(OSStatus)
        case invalidStoredValue
    }

    private static let service = "com.osgkeyboard.gateway-grant"
    private static let account = "scope-limited.active"

    public init() {}

    public func load() async throws -> ManagedGatewayGrantCredentials? {
        var query = Self.baseQuery
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
            Self.baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = Self.baseQuery
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
        let status = SecItemDelete(Self.baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }

    private static var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

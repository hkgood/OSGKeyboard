// ManagedGatewayAccountAccessPolicy.swift
// OSGKeyboard · Shared
//
// Device-local account-session gate for account-funded managed requests.
// The marker is intentionally non-secret and is never part of iCloud settings.

import Foundation

public protocol ManagedGatewayAccountAccessAuthorizing: Sendable {
    func allowsAccountManagedAccess() -> Bool
}

/// Production policy shared by the host and keyboard extension. A cached grant
/// alone is insufficient: the host must also have confirmed an account session.
public struct AppGroupManagedGatewayAccountAccessPolicy:
    ManagedGatewayAccountAccessAuthorizing,
    @unchecked Sendable {
    private let defaults: UserDefaults?

    public init(defaults: UserDefaults? = AppGroup.defaultsIfAvailable) {
        self.defaults = defaults
    }

    public func allowsAccountManagedAccess() -> Bool {
        defaults?.bool(
            forKey: AppGroupConfiguration.Keys.managedGatewayAccountSessionAvailable
        ) == true
    }
}

/// Anonymous OOBE grants have their own bounded practice-session policy and do
/// not represent account-funded access. Tests may also inject this explicitly.
public struct UnrestrictedManagedGatewayAccountAccessPolicy:
    ManagedGatewayAccountAccessAuthorizing {
    public init() {}

    public func allowsAccountManagedAccess() -> Bool {
        true
    }
}

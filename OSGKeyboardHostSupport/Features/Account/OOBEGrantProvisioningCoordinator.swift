// OOBEGrantProvisioningCoordinator.swift
// OSGKeyboard · HostSupport
//
// Provisions anonymous, App-Attest-bound OOBE credentials without creating or
// mutating an AccountSession.

import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

public actor OOBEGrantProvisioningCoordinator {
    private let apiClient: AccountAPIClient
    private let integrity: DeviceIntegrityCoordinator
    private let installationIDs: any OOBEInstallationIDStoring
    private let grants: OOBEGatewayGrantCoordinator

    public init(
        apiClient: AccountAPIClient,
        integrity: DeviceIntegrityCoordinator,
        installationIDs: any OOBEInstallationIDStoring,
        grants: OOBEGatewayGrantCoordinator = OOBEGatewayGrantCoordinator()
    ) {
        self.apiClient = apiClient
        self.integrity = integrity
        self.installationIDs = installationIDs
        self.grants = grants
    }

    @discardableResult
    public func provision() async throws -> ManagedGatewayGrantCredentials {
        let installationID = try await installationIDs.oobeInstallationID()
        let request = try await integrity.makeOOBEGrantRequest(
            installationID: installationID
        )
        let credentials = try await apiClient.requestOOBEGrant(request)
        try await grants.install(credentials)
        return credentials
    }

    public func clear() async {
        try? await grants.clearGrant()
    }
}

// OOBEClientInfrastructure.swift
// OSGKeyboard · Main App
//
// Host-facing entry point for anonymous four-feature onboarding practice.

import Foundation
import OSGKeyboardHostSupport
import OSGKeyboardShared

enum OOBEClientInfrastructureError: Error, Equatable {
    case unavailable
    case invalidSession
}

@MainActor
final class OOBEClientInfrastructure {
    static let shared = OOBEClientInfrastructure()

    private let provisioning: OOBEGrantProvisioningCoordinator?

    init(bundle: Bundle = .main) {
        guard let accessGroup = bundle.object(
            forInfoDictionaryKey: "OSGPrivateKeychainAccessGroup"
        ) as? String,
        let descriptor = try? HostPrivateAccountKeychainDescriptor(
            accessGroup: accessGroup
        ) else {
            provisioning = nil
            return
        }
        let keychain = HostPrivateAccountKeychain(descriptor: descriptor)
        let apiClient = AccountAPIClient(sessionVault: keychain)
        let integrity = DeviceIntegrityCoordinator(
            apiClient: apiClient,
            keyStateStore: keychain
        )
        provisioning = OOBEGrantProvisioningCoordinator(
            apiClient: apiClient,
            integrity: integrity,
            installationIDs: keychain
        )
    }

    @discardableResult
    func beginPractice(
        feature: ManagedGatewayOOBEFeature,
        duration: TimeInterval = 30 * 60,
        sampleMaterial: String? = nil
    ) async throws -> OOBEPracticeSession {
        guard let provisioning,
              let session = KeyboardSetupBridge.beginOOBEPracticeSession(
                  expectedFeature: feature,
                  duration: duration
              ) else {
            throw OOBEClientInfrastructureError.unavailable
        }
        do {
            try seedMaterialIfNeeded(
                sampleMaterial,
                feature: feature,
                sessionID: session.sessionID,
                duration: duration
            )
            try await provisioning.provision()
            return session
        } catch {
            KeyboardSetupBridge.endOOBEPracticeSession()
            await provisioning.clear()
            throw error
        }
    }

    @discardableResult
    func updateExpectedFeature(
        _ feature: ManagedGatewayOOBEFeature,
        sessionID: UUID,
        duration: TimeInterval? = nil,
        sampleMaterial: String? = nil
    ) throws -> OOBEPracticeSession {
        guard let session = KeyboardSetupBridge.updateOOBEExpectedFeature(
            feature,
            sessionID: sessionID,
            duration: duration
        ) else {
            throw OOBEClientInfrastructureError.invalidSession
        }
        try seedMaterialIfNeeded(
            sampleMaterial,
            feature: feature,
            sessionID: sessionID,
            duration: duration ?? session.expiresAt.timeIntervalSinceNow
        )
        return session
    }

    func completion(
        sessionID: UUID,
        feature: ManagedGatewayOOBEFeature
    ) -> OOBEPracticeCompletion? {
        KeyboardSetupBridge.oobePracticeCompletion(
            sessionID: sessionID,
            feature: feature
        )
    }

    func endPractice() async {
        KeyboardSetupBridge.endOOBEPracticeSession()
        await provisioning?.clear()
    }

    private func seedMaterialIfNeeded(
        _ sampleMaterial: String?,
        feature: ManagedGatewayOOBEFeature,
        sessionID: UUID,
        duration: TimeInterval
    ) throws {
        guard feature == .clipboardReply || feature == .clipboardTranslate else {
            return
        }
        // The host may establish the feature before the user explicitly taps
        // “Copy sample”. Material is seeded only in response to that tap.
        guard let sampleMaterial else { return }
        guard KeyboardSetupBridge.seedOOBEClipboardMaterial(
                  sampleMaterial,
                  sessionID: sessionID,
                  duration: min(max(duration, 1), 10 * 60)
              ) != nil else {
            throw OOBEClientInfrastructureError.invalidSession
        }
    }
}

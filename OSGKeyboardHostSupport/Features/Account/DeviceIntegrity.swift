// DeviceIntegrity.swift
// OSGKeyboard · HostSupport
//
// DeviceCheck and App Attest adapters with server-bound canonical payloads.

import CryptoKit
import DeviceCheck
import Foundation

public protocol DeviceCheckTokenProviding: Sendable {
    var isSupported: Bool { get }
    func generateToken() async throws -> Data
}

public protocol AppAttestProviding: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

public final class SystemDeviceCheckProvider: DeviceCheckTokenProviding, @unchecked Sendable {
    private let device: DCDevice

    public var isSupported: Bool {
        device.isSupported
    }

    public init(device: DCDevice = .current) {
        self.device = device
    }

    public func generateToken() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            device.generateToken { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? AccountAPIError.integrityUnavailable)
                }
            }
        }
    }
}

public final class SystemAppAttestProvider: AppAttestProviding, @unchecked Sendable {
    private let service: DCAppAttestService

    public var isSupported: Bool {
        service.isSupported
    }

    public init(service: DCAppAttestService = .shared) {
        self.service = service
    }

    public func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyId, error in
                if let keyId {
                    continuation.resume(returning: keyId)
                } else {
                    continuation.resume(throwing: error ?? AccountAPIError.integrityUnavailable)
                }
            }
        }
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyId, clientDataHash: clientDataHash) { object, error in
                if let object {
                    continuation.resume(returning: object)
                } else {
                    continuation.resume(throwing: error ?? AccountAPIError.integrityUnavailable)
                }
            }
        }
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, error in
                if let assertion {
                    continuation.resume(returning: assertion)
                } else {
                    continuation.resume(throwing: error ?? AccountAPIError.integrityUnavailable)
                }
            }
        }
    }
}

public struct DeviceIntegrityEvidence: Equatable, Sendable {
    public let deviceCheckToken: String?
    public let appAttest: AppAttestAssertion?

    public init(deviceCheckToken: String?, appAttest: AppAttestAssertion?) {
        self.deviceCheckToken = deviceCheckToken
        self.appAttest = appAttest
    }
}

public enum AppAttestCanonicalPayload {
    /// Matches `AppAttestCanonicalPayload.appleSignIn` on the account server.
    /// The final `\n` is part of the signed UTF-8 payload.
    public static func appleSignIn(
        challenge: String,
        credential: AppleSignInCredential,
        rawNonce: String
    ) throws -> Data {
        guard let challengeBytes = Data(base64URLEncoded: challenge) else {
            throw AccountAPIError.invalidResponse
        }
        let canonicalChallenge = challengeBytes.base64URLEncodedString()
        let payload = """
        osg-app-attest-v1
        purpose=apple-sign-in
        challenge=\(canonicalChallenge)
        identity_token_sha256=\(digest(credential.identityToken))
        authorization_code_sha256=\(digest(credential.authorizationCode))
        nonce_sha256=\(digest(rawNonce))

        """
        guard let data = payload.data(using: .utf8) else {
            throw AccountAPIError.invalidResponse
        }
        return data
    }

    static func challengeHash(_ challenge: String) throws -> Data {
        guard let challengeBytes = Data(base64URLEncoded: challenge) else {
            throw AccountAPIError.invalidResponse
        }
        return sha256(challengeBytes)
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func digest(_ value: String) -> String {
        sha256(Data(value.utf8)).base64URLEncodedString()
    }
}

public actor DeviceIntegrityCoordinator {
    private let apiClient: AccountAPIClient
    private let deviceCheck: any DeviceCheckTokenProviding
    private let appAttest: any AppAttestProviding
    private let keyStateStore: any AppAttestKeyStateStoring

    public init(
        apiClient: AccountAPIClient,
        deviceCheck: any DeviceCheckTokenProviding = SystemDeviceCheckProvider(),
        appAttest: any AppAttestProviding = SystemAppAttestProvider(),
        keyStateStore: any AppAttestKeyStateStoring
    ) {
        self.apiClient = apiClient
        self.deviceCheck = deviceCheck
        self.appAttest = appAttest
        self.keyStateStore = keyStateStore
    }

    public func evidenceForAppleSignIn(
        credential: AppleSignInCredential,
        rawNonce: String
    ) async throws -> DeviceIntegrityEvidence {
        async let deviceCheckToken = optionalDeviceCheckToken()
        async let assertion = optionalAppleSignInAssertion(
            credential: credential,
            rawNonce: rawNonce
        )
        let evidence = await DeviceIntegrityEvidence(
            deviceCheckToken: deviceCheckToken,
            appAttest: assertion
        )
        if evidence.deviceCheckToken == nil,
           evidence.appAttest == nil,
           deviceCheck.isSupported || appAttest.isSupported {
            throw AccountAPIError.integrityUnavailable
        }
        return evidence
    }

    public func clearLocalKeyState() async {
        try? await keyStateStore.clearAppAttestKeyState()
    }

    private func optionalDeviceCheckToken() async -> String? {
        try? await makeDeviceCheckToken()
    }

    private func optionalAppleSignInAssertion(
        credential: AppleSignInCredential,
        rawNonce: String
    ) async -> AppAttestAssertion? {
        try? await makeAppleSignInAssertion(
            credential: credential,
            rawNonce: rawNonce
        )
    }

    private func makeDeviceCheckToken() async throws -> String? {
        guard deviceCheck.isSupported else { return nil }
        do {
            return try await deviceCheck.generateToken().base64EncodedString()
        } catch {
            throw AccountAPIError.integrityUnavailable
        }
    }

    private func makeAppleSignInAssertion(
        credential: AppleSignInCredential,
        rawNonce: String,
        allowsKeyRecovery: Bool = true
    ) async throws -> AppAttestAssertion? {
        guard appAttest.isSupported else { return nil }
        let keyId = try await registeredKeyId()
        let challenge = try await apiClient.issueAppAttestChallenge(
            purpose: .assertion,
            keyId: keyId
        )
        let payload = try AppAttestCanonicalPayload.appleSignIn(
            challenge: challenge.challenge,
            credential: credential,
            rawNonce: rawNonce
        )
        let assertion: Data
        do {
            assertion = try await appAttest.generateAssertion(
                keyId,
                clientDataHash: AppAttestCanonicalPayload.sha256(payload)
            )
        } catch where allowsKeyRecovery {
            try? await keyStateStore.clearAppAttestKeyState()
            return try await makeAppleSignInAssertion(
                credential: credential,
                rawNonce: rawNonce,
                allowsKeyRecovery: false
            )
        } catch {
            throw AccountAPIError.integrityUnavailable
        }
        return AppAttestAssertion(
            keyId: keyId,
            challengeId: challenge.challengeId,
            challenge: challenge.challenge,
            assertion: assertion.base64EncodedString()
        )
    }

    private func registeredKeyId(
        allowsKeyRecovery: Bool = true
    ) async throws -> String {
        do {
            return try await registerKeyIfNeeded()
        } catch where allowsKeyRecovery {
            try? await keyStateStore.clearAppAttestKeyState()
            return try await registeredKeyId(allowsKeyRecovery: false)
        }
    }

    private func registerKeyIfNeeded() async throws -> String {
        var state: AppAttestKeyState
        do {
            if let existing = try await keyStateStore.loadAppAttestKeyState() {
                state = existing
            } else {
                let keyId = try await appAttest.generateKey()
                state = AppAttestKeyState(keyId: keyId, isRegistered: false)
                try await keyStateStore.saveAppAttestKeyState(state)
            }
        } catch let error as AccountAPIError {
            throw error
        } catch {
            throw AccountAPIError.integrityUnavailable
        }

        if state.isRegistered {
            return state.keyId
        }

        let challenge = try await apiClient.issueAppAttestChallenge(
            purpose: .attestation,
            keyId: state.keyId
        )
        let attestationObject: Data
        do {
            attestationObject = try await appAttest.attestKey(
                state.keyId,
                clientDataHash: AppAttestCanonicalPayload.challengeHash(challenge.challenge)
            )
        } catch {
            throw AccountAPIError.integrityUnavailable
        }
        try await apiClient.submitAttestation(
            challenge: challenge,
            keyId: state.keyId,
            attestationObject: attestationObject
        )
        state = AppAttestKeyState(keyId: state.keyId, isRegistered: true)
        do {
            try await keyStateStore.saveAppAttestKeyState(state)
        } catch {
            throw AccountAPIError.secureStorage
        }
        return state.keyId
    }
}

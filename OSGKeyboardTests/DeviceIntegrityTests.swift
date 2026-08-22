// DeviceIntegrityTests.swift
// OSGKeyboardTests
//
// Hermetic DeviceCheck and App Attest registration/assertion tests.

import CryptoKit
@testable import OSGKeyboardHostSupport
import XCTest

final class DeviceIntegrityTests: XCTestCase {
    func testAppleSignInEvidenceRegistersKeyAndSignsCanonicalPayload() async throws {
        let attestationChallenge = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let assertionChallenge = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let transport = QueueAccountTransport([
            .init(
                statusCode: 201,
                body: challengeData(
                    id: attestationChallenge,
                    challenge: "AQID"
                )
            ),
            .init(statusCode: 204, body: Data()),
            .init(
                statusCode: 201,
                body: challengeData(
                    id: assertionChallenge,
                    challenge: "BAUG"
                )
            )
        ])
        let store = InMemoryAccountSecurityStore()
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let appAttestState = FakeAppAttestState()
        let coordinator = DeviceIntegrityCoordinator(
            apiClient: client,
            deviceCheck: FakeDeviceCheckProvider(
                isSupported: true,
                token: Data([0x10, 0x20])
            ),
            appAttest: FakeAppAttestProvider(
                isSupported: true,
                state: appAttestState,
                keyId: "key-id",
                attestationObject: Data([0xAA, 0xBB]),
                assertion: Data([0xCC])
            ),
            keyStateStore: store
        )
        let credential = AppleSignInCredential(
            identityToken: "identity-token",
            authorizationCode: "authorization-code"
        )

        let evidence = try await coordinator.evidenceForAppleSignIn(
            credential: credential,
            rawNonce: "raw-nonce"
        )

        XCTAssertEqual(evidence.deviceCheckToken, "ECA=")
        XCTAssertEqual(
            evidence.appAttest,
            AppAttestAssertion(
                keyId: "key-id",
                challengeId: assertionChallenge,
                challenge: "BAUG",
                assertion: "zA=="
            )
        )
        let keyState = await store.keyState
        XCTAssertEqual(keyState, AppAttestKeyState(keyId: "key-id", isRegistered: true))
        let generatedKeyCount = await appAttestState.generatedKeyCount
        XCTAssertEqual(generatedKeyCount, 1)

        let attestationHashes = await appAttestState.attestationHashes
        XCTAssertEqual(attestationHashes, [Data(SHA256.hash(data: Data([1, 2, 3])))])

        let canonicalPayload = """
        osg-app-attest-v1
        purpose=apple-sign-in
        challenge=BAUG
        identity_token_sha256=OcwzHhEgHO3_IBV8hI8o_WTuAx0hgRrERJAbfcPbjvA
        authorization_code_sha256=WVYUJ4163Fe7kuKPogOooY15egdoT9_3XLvyqW6_hXc
        nonce_sha256=LF0QeTgFOiJ18CLBU8mnH2XuB3VLi8pUPul6DDzGaZA

        """
        let assertionHashes = await appAttestState.assertionHashes
        XCTAssertEqual(
            assertionHashes,
            [Data(SHA256.hash(data: Data(canonicalPayload.utf8)))]
        )

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url?.path), [
            "/v1/integrity/challenges",
            "/v1/integrity/attest",
            "/v1/integrity/challenges"
        ])
        let attestationBody = try XCTUnwrap(requests[1].httpBody)
        let attestationJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: attestationBody) as? [String: Any]
        )
        XCTAssertEqual(attestationJSON["attestationObject"] as? String, "qrs=")
    }

    func testDeviceCheckRemainsUsableWhenAppAttestRecoveryFails() async throws {
        let transport = QueueAccountTransport([
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!,
                    challenge: "AQID"
                )
            )
        ])
        let store = InMemoryAccountSecurityStore(
            keyState: AppAttestKeyState(keyId: "stale-key", isRegistered: true)
        )
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let coordinator = DeviceIntegrityCoordinator(
            apiClient: client,
            deviceCheck: FakeDeviceCheckProvider(
                isSupported: true,
                token: Data([0x10, 0x20])
            ),
            appAttest: AlwaysFailingAppAttestProvider(),
            keyStateStore: store
        )

        let evidence = try await coordinator.evidenceForAppleSignIn(
            credential: AppleSignInCredential(
                identityToken: "identity-token",
                authorizationCode: "authorization-code"
            ),
            rawNonce: "raw-nonce"
        )

        XCTAssertEqual(evidence.deviceCheckToken, "ECA=")
        XCTAssertNil(evidence.appAttest)
    }

    func testInvalidAppAttestKeyIsReplacedAndRegisteredOnce() async throws {
        let transport = QueueAccountTransport([
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!,
                    challenge: "AQID"
                )
            ),
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
                    challenge: "BAUG"
                )
            ),
            .init(statusCode: 204, body: Data()),
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
                    challenge: "BwgJ"
                )
            )
        ])
        let store = InMemoryAccountSecurityStore(
            keyState: AppAttestKeyState(keyId: "stale-key", isRegistered: true)
        )
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let appAttestState = RecoveringAppAttestState()
        let coordinator = DeviceIntegrityCoordinator(
            apiClient: client,
            deviceCheck: FakeDeviceCheckProvider(isSupported: false, token: Data()),
            appAttest: RecoveringAppAttestProvider(state: appAttestState),
            keyStateStore: store
        )

        let evidence = try await coordinator.evidenceForAppleSignIn(
            credential: AppleSignInCredential(
                identityToken: "identity-token",
                authorizationCode: "authorization-code"
            ),
            rawNonce: "raw-nonce"
        )

        XCTAssertEqual(evidence.appAttest?.keyId, "fresh-key")
        let keyState = await store.keyState
        XCTAssertEqual(keyState, AppAttestKeyState(keyId: "fresh-key", isRegistered: true))
        let clearCount = await appAttestState.failedAssertionCount
        XCTAssertEqual(clearCount, 1)
    }

    func testUnregisteredKeyFromAnotherEnvironmentIsReplaced() async throws {
        let transport = QueueAccountTransport([
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
                    challenge: "AQID"
                )
            ),
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "14141414-1414-1414-1414-141414141414")!,
                    challenge: "BAUG"
                )
            ),
            .init(statusCode: 204, body: Data()),
            .init(
                statusCode: 201,
                body: challengeData(
                    id: UUID(uuidString: "15151515-1515-1515-1515-151515151515")!,
                    challenge: "BwgJ"
                )
            )
        ])
        let store = InMemoryAccountSecurityStore(
            keyState: AppAttestKeyState(keyId: "stale-key", isRegistered: false)
        )
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let appAttestState = RecoveringAppAttestState()
        let coordinator = DeviceIntegrityCoordinator(
            apiClient: client,
            deviceCheck: FakeDeviceCheckProvider(isSupported: false, token: Data()),
            appAttest: RecoveringAppAttestProvider(state: appAttestState),
            keyStateStore: store
        )

        let evidence = try await coordinator.evidenceForAppleSignIn(
            credential: AppleSignInCredential(
                identityToken: "identity-token",
                authorizationCode: "authorization-code"
            ),
            rawNonce: "raw-nonce"
        )

        XCTAssertEqual(evidence.appAttest?.keyId, "fresh-key")
        let keyState = await store.keyState
        let failedAttestationCount = await appAttestState.failedAttestationCount
        XCTAssertEqual(keyState, AppAttestKeyState(keyId: "fresh-key", isRegistered: true))
        XCTAssertEqual(failedAttestationCount, 1)
    }

    func testChallengeAssertionSendsBase64URLClientDataHash() async throws {
        let challenge = AppAttestChallenge(
            challengeId: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            challenge: "AQID",
            expiresAtEpochSeconds: 4_000_000_000
        )
        let transport = QueueAccountTransport([
            .init(statusCode: 200, body: Data(#"{"counter":7}"#.utf8))
        ])
        let store = InMemoryAccountSecurityStore()
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let hash = Data(SHA256.hash(data: Data([1, 2, 3])))

        let counter = try await client.submitAssertion(
            challenge: challenge,
            keyId: "key-id",
            assertion: Data([0x01, 0x02]),
            clientDataHash: hash
        )

        XCTAssertEqual(counter, 7)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.single)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(
            json["clientDataHash"] as? String,
            hash.base64URLEncodedString()
        )
        XCTAssertEqual(json["assertion"] as? String, "AQI=")
    }

    func testOOBEGrantRequestReusesRegisteredKeyAndSignsCanonicalPayload() async throws {
        let installationID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let challengeID = UUID(
            uuidString: "16161616-1616-1616-1616-161616161616"
        )!
        let transport = QueueAccountTransport([
            .init(
                statusCode: 201,
                body: challengeData(id: challengeID, challenge: "AQID")
            )
        ])
        let store = InMemoryAccountSecurityStore(
            keyState: AppAttestKeyState(keyId: "key-id", isRegistered: true)
        )
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let appAttestState = FakeAppAttestState()
        let coordinator = DeviceIntegrityCoordinator(
            apiClient: client,
            deviceCheck: FakeDeviceCheckProvider(isSupported: false, token: Data()),
            appAttest: FakeAppAttestProvider(
                isSupported: true,
                state: appAttestState,
                keyId: "unused",
                attestationObject: Data(),
                assertion: Data([0xAA])
            ),
            keyStateStore: store
        )

        let request = try await coordinator.makeOOBEGrantRequest(
            installationID: installationID
        )

        XCTAssertEqual(
            request,
            OOBEGrantRequest(
                installationId: installationID,
                keyId: "key-id",
                challengeId: challengeID,
                challenge: "AQID",
                assertion: "qg=="
            )
        )
        let payload = """
        osg-app-attest-v1
        purpose=oobe-gateway-grant
        challenge=AQID
        key_id=key-id
        installation_id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
        scopes=ai,polish
        features=ask_ai,clipboard_reply,clipboard_translate,voice_input
        grant_ttl_seconds=1800
        access_ttl_seconds=300

        """
        let hashes = await appAttestState.assertionHashes
        XCTAssertEqual(hashes, [Data(SHA256.hash(data: Data(payload.utf8)))])
    }
}

private enum TestIntegrityFailure: Error {
    case unavailable
}

private struct AlwaysFailingAppAttestProvider: AppAttestProviding {
    let isSupported = true

    func generateKey() async throws -> String {
        throw TestIntegrityFailure.unavailable
    }

    func attestKey(
        _ keyId: String,
        clientDataHash: Data
    ) async throws -> Data {
        throw TestIntegrityFailure.unavailable
    }

    func generateAssertion(
        _ keyId: String,
        clientDataHash: Data
    ) async throws -> Data {
        throw TestIntegrityFailure.unavailable
    }
}

private actor RecoveringAppAttestState {
    private(set) var failedAssertionCount = 0
    private(set) var failedAttestationCount = 0

    func recordFailedAssertion() {
        failedAssertionCount += 1
    }

    func recordFailedAttestation() {
        failedAttestationCount += 1
    }
}

private struct RecoveringAppAttestProvider: AppAttestProviding {
    let isSupported = true
    let state: RecoveringAppAttestState

    func generateKey() async throws -> String {
        "fresh-key"
    }

    func attestKey(
        _ keyId: String,
        clientDataHash: Data
    ) async throws -> Data {
        if keyId == "stale-key" {
            await state.recordFailedAttestation()
            throw TestIntegrityFailure.unavailable
        }
        return Data([0xaa, 0xbb])
    }

    func generateAssertion(
        _ keyId: String,
        clientDataHash: Data
    ) async throws -> Data {
        if keyId == "stale-key" {
            await state.recordFailedAssertion()
            throw TestIntegrityFailure.unavailable
        }
        return Data([0x01, 0x02])
    }
}

private func challengeData(id: UUID, challenge: String) -> Data {
    Data(
        """
        {"challengeId":"\(id.uuidString.lowercased())","challenge":"\(challenge)","expiresAtEpochSeconds":4000000000}
        """.utf8
    )
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}

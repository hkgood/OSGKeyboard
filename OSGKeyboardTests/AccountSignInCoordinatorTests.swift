// AccountSignInCoordinatorTests.swift
// OSGKeyboardTests
//
// End-to-end orchestration with injected Apple and integrity fakes.

@testable import OSGKeyboardHostSupport
import XCTest

final class AccountSignInCoordinatorTests: XCTestCase {
    @MainActor
    func testSignInPassesHashedNonceToAppleAndRawNonceToServer() async throws {
        let expectedSession = makeAccountSession()
        let challengeId = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let transport = QueueAccountTransport([
            .init(
                statusCode: 201,
                body: Data(
                    """
                    {"challengeId":"\(challengeId.uuidString)","challenge":"AQID","expiresAtEpochSeconds":4000000000}
                    """.utf8
                )
            ),
            .init(statusCode: 200, body: try sessionEnvelopeData(expectedSession))
        ])
        let store = InMemoryAccountSecurityStore(
            keyState: AppAttestKeyState(keyId: "registered-key", isRegistered: true)
        )
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store
        )
        let appAttestState = FakeAppAttestState()
        let integrity = DeviceIntegrityCoordinator(
            apiClient: client,
            deviceCheck: FakeDeviceCheckProvider(
                isSupported: true,
                token: Data([0x01])
            ),
            appAttest: FakeAppAttestProvider(
                isSupported: true,
                state: appAttestState,
                keyId: "registered-key",
                attestationObject: Data(),
                assertion: Data([0x02])
            ),
            keyStateStore: store
        )
        let apple = FakeAppleAuthorizationProvider(
            credential: AppleSignInCredential(
                identityToken: "identity-token",
                authorizationCode: "authorization-code"
            )
        )
        let nonce = AppleSignInNonce(
            rawValue: "raw-nonce",
            sha256Hex: "0123456789abcdef"
        )
        let coordinator = AccountSignInCoordinator(
            apiClient: client,
            appleAuthorization: apple,
            nonceGenerator: FixedNonceGenerator(nonce: nonce),
            integrity: integrity
        )

        let session = try await coordinator.signIn()

        XCTAssertEqual(session, expectedSession)
        XCTAssertEqual(apple.receivedNonceHash, nonce.sha256Hex)
        let requests = await transport.requests
        let signInRequest = try XCTUnwrap(
            requests.first { $0.url?.path == "/v1/auth/apple" }
        )
        let body = try XCTUnwrap(signInRequest.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["nonce"] as? String, nonce.rawValue)
        XCTAssertEqual(json["deviceCheckToken"] as? String, "AQ==")
        let appAttest = try XCTUnwrap(json["appAttest"] as? [String: Any])
        XCTAssertEqual(appAttest["keyId"] as? String, "registered-key")
        XCTAssertEqual(appAttest["assertion"] as? String, "Ag==")
    }
}

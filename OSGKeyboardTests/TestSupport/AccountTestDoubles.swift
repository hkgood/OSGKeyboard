// AccountTestDoubles.swift
// OSGKeyboardTests · TestSupport
//
// Hermetic account, Keychain, and Apple-service doubles.

import Foundation
@testable import OSGKeyboardHostSupport

actor InMemoryAccountSecurityStore: AccountSessionVault, AppAttestKeyStateStoring {
    private(set) var session: AccountSession?
    private(set) var keyState: AppAttestKeyState?
    private(set) var clearSessionCount = 0

    init(session: AccountSession? = nil, keyState: AppAttestKeyState? = nil) {
        self.session = session
        self.keyState = keyState
    }

    func loadSession() async throws -> AccountSession? {
        session
    }

    func saveSession(_ session: AccountSession) async throws {
        self.session = session
    }

    func clearSession() async throws {
        session = nil
        clearSessionCount += 1
    }

    func loadAppAttestKeyState() async throws -> AppAttestKeyState? {
        keyState
    }

    func saveAppAttestKeyState(_ state: AppAttestKeyState) async throws {
        keyState = state
    }

    func clearAppAttestKeyState() async throws {
        keyState = nil
    }
}

actor QueueAccountTransport: AccountHTTPTransport {
    struct Stub: Sendable {
        let statusCode: Int
        let body: Data
    }

    private var stubs: [Stub]
    private(set) var requests: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !stubs.isEmpty else {
            throw AccountAPIError.transport
        }
        let stub = stubs.removeFirst()
        return (stub.body, makeHTTPResponse(request: request, statusCode: stub.statusCode))
    }
}

actor RefreshMergingTransport: AccountHTTPTransport {
    private let replacementSession: AccountSession
    private let refreshError: QueueAccountTransport.Stub?
    private(set) var requests: [URLRequest] = []
    private(set) var refreshCount = 0

    init(
        replacementSession: AccountSession,
        refreshError: QueueAccountTransport.Stub? = nil
    ) {
        self.replacementSession = replacementSession
        self.refreshError = refreshError
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path
        if path == "/v1/auth/refresh" {
            refreshCount += 1
            try await Task.sleep(for: .milliseconds(100))
            if let refreshError {
                return (
                    refreshError.body,
                    makeHTTPResponse(request: request, statusCode: refreshError.statusCode)
                )
            }
            return (
                try sessionEnvelopeData(replacementSession),
                makeHTTPResponse(request: request, statusCode: 200)
            )
        }

        if path == "/v1/account" {
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            if authorization == "Bearer \(replacementSession.accessToken)" {
                let body = Data(
                    """
                    {"data":{"id":"\(replacementSession.accountId.uuidString.lowercased())","createdAtEpochSeconds":1}}
                    """.utf8
                )
                return (body, makeHTTPResponse(request: request, statusCode: 200))
            }
            return (
                apiErrorData(code: "unauthorized", message: "expired"),
                makeHTTPResponse(request: request, statusCode: 401)
            )
        }

        throw AccountAPIError.transport
    }
}

struct FixedRandomBytesGenerator: SecureRandomBytesGenerating {
    let value: Data

    func bytes(count: Int) throws -> Data {
        value
    }
}

struct FixedNonceGenerator: AppleSignInNonceGenerating {
    let nonce: AppleSignInNonce

    func makeNonce() throws -> AppleSignInNonce {
        nonce
    }
}

@MainActor
final class FakeAppleAuthorizationProvider: AppleAuthorizationProviding, @unchecked Sendable {
    let credential: AppleSignInCredential
    private(set) var receivedNonceHash: String?

    init(credential: AppleSignInCredential) {
        self.credential = credential
    }

    func authorize(nonceSHA256: String) async throws -> AppleSignInCredential {
        receivedNonceHash = nonceSHA256
        return credential
    }
}

struct FakeDeviceCheckProvider: DeviceCheckTokenProviding {
    let isSupported: Bool
    let token: Data

    func generateToken() async throws -> Data {
        token
    }
}

actor FakeAppAttestState {
    private(set) var generatedKeyCount = 0
    private(set) var attestationHashes: [Data] = []
    private(set) var assertionHashes: [Data] = []

    func recordGeneratedKey() {
        generatedKeyCount += 1
    }

    func recordAttestationHash(_ hash: Data) {
        attestationHashes.append(hash)
    }

    func recordAssertionHash(_ hash: Data) {
        assertionHashes.append(hash)
    }
}

struct FakeAppAttestProvider: AppAttestProviding {
    let isSupported: Bool
    let state: FakeAppAttestState
    let keyId: String
    let attestationObject: Data
    let assertion: Data

    func generateKey() async throws -> String {
        await state.recordGeneratedKey()
        return keyId
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        await state.recordAttestationHash(clientDataHash)
        return attestationObject
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        await state.recordAssertionHash(clientDataHash)
        return assertion
    }
}

func makeHTTPResponse(request: URLRequest, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

func sessionEnvelopeData(_ session: AccountSession) throws -> Data {
    try JSONEncoder().encode(APIDataEnvelope(data: session))
}

func apiErrorData(code: String, message: String) -> Data {
    Data(#"{"error":{"code":"\#(code)","message":"\#(message)"}}"#.utf8)
}

func makeAccountSession(
    accessToken: String = "access-old",
    refreshToken: String = "refresh-old",
    accessExpiry: Int64 = 4_000_000_000,
    refreshExpiry: Int64 = 4_100_000_000
) -> AccountSession {
    AccountSession(
        accountId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        tokenType: "Bearer",
        accessToken: accessToken,
        accessTokenExpiresAtEpochSeconds: accessExpiry,
        refreshToken: refreshToken,
        refreshTokenExpiresAtEpochSeconds: refreshExpiry
    )
}

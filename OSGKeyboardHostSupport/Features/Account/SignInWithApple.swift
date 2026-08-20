// SignInWithApple.swift
// OSGKeyboard · HostSupport
//
// Raw-nonce generation and an injectable AuthenticationServices adapter.

import AuthenticationServices
import CryptoKit
import Foundation
import Security

public protocol SecureRandomBytesGenerating: Sendable {
    func bytes(count: Int) throws -> Data
}

public struct SystemSecureRandomBytesGenerator: SecureRandomBytesGenerating {
    public init() {}

    public func bytes(count: Int) throws -> Data {
        guard count > 0 else {
            throw AccountAPIError.appleAuthorization
        }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AccountAPIError.appleAuthorization
        }
        return data
    }
}

public protocol AppleSignInNonceGenerating: Sendable {
    func makeNonce() throws -> AppleSignInNonce
}

public struct AppleSignInNonceGenerator: AppleSignInNonceGenerating {
    private let random: any SecureRandomBytesGenerating

    public init(random: any SecureRandomBytesGenerating = SystemSecureRandomBytesGenerator()) {
        self.random = random
    }

    public func makeNonce() throws -> AppleSignInNonce {
        let rawNonce = try random.bytes(count: 32).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(rawNonce.utf8))
        let lowercaseHex = digest.map { String(format: "%02x", $0) }.joined()
        return AppleSignInNonce(rawValue: rawNonce, sha256Hex: lowercaseHex)
    }
}

@MainActor
public protocol AppleAuthorizationProviding: Sendable {
    func authorize(nonceSHA256: String) async throws -> AppleSignInCredential
}

@MainActor
public final class AppleAuthorizationControllerProvider:
    NSObject,
    AppleAuthorizationProviding,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding,
    @unchecked Sendable {

    public typealias PresentationAnchorProvider = @MainActor @Sendable () -> ASPresentationAnchor

    private let presentationAnchorProvider: PresentationAnchorProvider
    private var continuation: CheckedContinuation<AppleSignInCredential, Error>?

    public init(presentationAnchorProvider: @escaping PresentationAnchorProvider) {
        self.presentationAnchorProvider = presentationAnchorProvider
    }

    public func authorize(nonceSHA256: String) async throws -> AppleSignInCredential {
        guard continuation == nil, !nonceSHA256.isEmpty else {
            throw AccountAPIError.appleAuthorization
        }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = nonceSHA256

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let authorizationCodeData = credential.authorizationCode,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8),
              !identityToken.isEmpty,
              !authorizationCode.isEmpty else {
            complete(with: .failure(AccountAPIError.appleAuthorization))
            return
        }
        complete(
            with: .success(
                AppleSignInCredential(
                    identityToken: identityToken,
                    authorizationCode: authorizationCode
                )
            )
        )
    }

    public func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        complete(with: .failure(AccountAPIError.appleAuthorization))
    }

    public func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        presentationAnchorProvider()
    }

    private func complete(with result: Result<AppleSignInCredential, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

public actor AccountSignInCoordinator {
    private let apiClient: AccountAPIClient
    private let appleAuthorization: any AppleAuthorizationProviding
    private let nonceGenerator: any AppleSignInNonceGenerating
    private let integrity: DeviceIntegrityCoordinator

    public init(
        apiClient: AccountAPIClient,
        appleAuthorization: any AppleAuthorizationProviding,
        nonceGenerator: any AppleSignInNonceGenerating = AppleSignInNonceGenerator(),
        integrity: DeviceIntegrityCoordinator
    ) {
        self.apiClient = apiClient
        self.appleAuthorization = appleAuthorization
        self.nonceGenerator = nonceGenerator
        self.integrity = integrity
    }

    @discardableResult
    public func signIn() async throws -> AccountSession {
        let nonce = try nonceGenerator.makeNonce()
        let credential = try await appleAuthorization.authorize(nonceSHA256: nonce.sha256Hex)
        let evidence = try await integrity.evidenceForAppleSignIn(
            credential: credential,
            rawNonce: nonce.rawValue
        )
        return try await apiClient.signInWithApple(
            AppleSignInRequest(
                identityToken: credential.identityToken,
                authorizationCode: credential.authorizationCode,
                nonce: nonce.rawValue,
                deviceCheckToken: evidence.deviceCheckToken,
                appAttest: evidence.appAttest
            )
        )
    }

    public func deleteAccount() async throws {
        let nonce = try nonceGenerator.makeNonce()
        let credential = try await appleAuthorization.authorize(nonceSHA256: nonce.sha256Hex)
        try await apiClient.deleteAccount(
            with: DeleteAccountRequest(
                identityToken: credential.identityToken,
                authorizationCode: credential.authorizationCode,
                nonce: nonce.rawValue
            )
        )
    }
}

// AccountAppleAuthorizationButton.swift
// OSGKeyboard · Main App
//
// Sign in with Apple presentation and nonce handling shared by sign-in and
// deletion reauthentication. Tokens are passed directly to the auth boundary.

import AuthenticationServices
import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

enum AccountAppleAuthorizationPurpose {
    case signIn
    case deleteAccount
}

struct AccountAppleAuthorizationButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AccountSessionCoordinator

    let purpose: AccountAppleAuthorizationPurpose
    var onSignedIn: () -> Void = {}
    var onDeleted: () -> Void = {}

    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(
            purpose == .signIn ? .signIn : .continue,
            onRequest: prepareRequest,
            onCompletion: completeAuthorization
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .accessibilityLabel(
            purpose == .signIn
                ? Text("account.signIn.apple")
                : Text("account.delete.reauthenticate")
        )
        .accessibilityHint(
            purpose == .signIn
                ? Text("account.signIn.hint")
                : Text("account.delete.reauthenticateHint")
        )
    }

    private func prepareRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let nonce = AccountAppleNonce.make() else {
            rawNonce = nil
            request.nonce = nil
            return
        }
        rawNonce = nonce.rawValue
        request.requestedScopes = purpose == .signIn ? [.fullName] : []
        request.nonce = nonce.sha256Hex
    }

    private func completeAuthorization(_ result: Result<ASAuthorization, Error>) {
        guard let rawNonce else {
            OSGDiag.log(
                "appleAuthorization failed stage=nonce-unavailable",
                category: "account"
            )
            coordinator.recordAppleAuthorizationFailure()
            return
        }
        self.rawNonce = nil

        switch result {
        case let .success(authorization):
            guard let payload = AccountAppleAuthorizationPayload.make(
                from: authorization,
                rawNonce: rawNonce
            ) else {
                OSGDiag.log(
                    "appleAuthorization failed stage=credential-payload",
                    category: "account"
                )
                coordinator.recordAppleAuthorizationFailure()
                return
            }
            Task {
                switch purpose {
                case .signIn:
                    await coordinator.signIn(with: payload)
                    if coordinator.isSignedIn {
                        ProviderConfig.shared.reloadFromPersistedStorage()
                        onSignedIn()
                    }
                case .deleteAccount:
                    await coordinator.deleteAccount(with: payload)
                    if !coordinator.isSignedIn {
                        onDeleted()
                    }
                }
            }
        case let .failure(error):
            let diagnostic = error as NSError
            OSGDiag.log(
                "appleAuthorization failed stage=system "
                    + "domain=\(diagnostic.domain) code=\(diagnostic.code)",
                category: "account"
            )
            if (error as? ASAuthorizationError)?.code != .canceled {
                coordinator.recordAppleAuthorizationFailure()
            }
        }
    }
}

private enum AccountAppleAuthorizationPayload {
    static func make(
        from authorization: ASAuthorization,
        rawNonce: String
    ) -> AppleAuthorizationPayload? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let authorizationCodeData = credential.authorizationCode,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8),
              !identityToken.isEmpty,
              !authorizationCode.isEmpty
        else {
            return nil
        }

        return AppleAuthorizationPayload(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: rawNonce,
            displayName: displayName(from: credential.fullName)
        )
    }

    private static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let value = PersonNameComponentsFormatter.localizedString(
            from: components,
            style: .default,
            options: []
        )
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum AccountAppleNonce {
    static func make() -> AppleSignInNonce? {
        // Do not fall back to a merely unique identifier if the system RNG is
        // unavailable. The completion path rejects authorization without a
        // cryptographically random raw nonce.
        return try? AppleSignInNonceGenerator().makeNonce()
    }
}

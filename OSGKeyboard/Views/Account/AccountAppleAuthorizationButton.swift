// AccountAppleAuthorizationButton.swift
// OSGKeyboard · Main App
//
// Sign in with Apple presentation and nonce handling shared by sign-in and
// deletion reauthentication. Tokens are passed directly to the auth boundary.

import AuthenticationServices
import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

struct AccountAppleAuthorizationButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AccountSessionCoordinator

    let purpose: AccountAppleAuthorizationPurpose
    var onSignedIn: () -> Void = {}
    var onDeleted: () -> Void = {}

    @State private var rawNonce: String?

    var body: some View {
        Group {
            if purpose == .signIn, coordinator.operation == .signingIn {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .tint(authorizationButtonForeground)
                    Text("account.signIn.loading")
                        .font(TypeStyle.bodyEmph)
                }
                .foregroundStyle(authorizationButtonForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(authorizationButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account.signIn.loading")
            } else {
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
                .accessibilityIdentifier(
                    purpose == .signIn
                        ? "account.signIn.apple"
                        : "account.delete.reauthenticate"
                )
            }
        }
    }

    private var authorizationButtonBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var authorizationButtonForeground: Color {
        colorScheme == .dark ? .black : .white
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

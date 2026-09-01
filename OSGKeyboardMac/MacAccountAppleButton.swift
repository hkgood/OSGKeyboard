// MacAccountAppleButton.swift
// OSGKeyboard · Mac
//
// Sign in with Apple for the menu-bar app. Sign-in and delete-account
// reauthentication share one button, exactly like the iOS account center.
// Nonce generation and credential validation come from the cross-platform
// `AccountAppleNonce` / `AccountAppleAuthorizationPayload` factories, so the
// security-relevant path is identical on both platforms — only the labels,
// which resolve from Shared.strings here instead of the iOS app bundle, differ.
//
// This works in a non-sandboxed Developer ID build: Sign in with Apple needs
// only the `com.apple.developer.applesignin` entitlement, never the Mac App
// Store. The Mac App ID must be grouped under the iOS primary App ID or the
// same person authenticates as a different Apple `sub` here than on iPhone.

import AuthenticationServices
import SwiftUI

struct MacAccountAppleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AccountSessionCoordinator

    let purpose: AccountAppleAuthorizationPurpose
    let language: AppUILanguage
    var onSignedIn: () -> Void = {}
    var onDeleted: () -> Void = {}

    @State private var rawNonce: String?

    var body: some View {
        Group {
            if purpose == .signIn, coordinator.operation == .signingIn {
                loadingButton
            } else {
                SignInWithAppleButton(
                    purpose == .signIn ? .signIn : .continue,
                    onRequest: prepareRequest,
                    onCompletion: completeAuthorization
                )
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                // 系统按钮的文字/图标随按钮高度缩放，40pt 时文字明显偏小。
                .frame(height: MacMetrics.appleButtonHeight)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .accessibilityIdentifier(
                    purpose == .signIn
                        ? "mac.account.signIn.apple"
                        : "mac.account.delete.reauthenticate"
                )
            }
        }
        // Fixed, not `maxWidth`: inside a settings row the label column is also
        // flexible, and two flexible siblings split the row evenly — which
        // shrank the button and squeezed the copy next to it.
        .frame(width: 260)
    }

    private var loadingButton: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(foreground)
            Text(MacL10n.string("mac.account.signIn.loading", language: language))
                .font(TypeStyle.bodyEmph)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: MacMetrics.appleButtonHeight)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mac.account.signIn.loading")
    }

    private var background: Color { colorScheme == .dark ? .white : .black }
    private var foreground: Color { colorScheme == .dark ? .black : .white }

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
            coordinator.recordAppleAuthorizationFailure(detail: "nonce-unavailable")
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
                coordinator.recordAppleAuthorizationFailure(detail: "credential-payload")
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
                coordinator.recordAppleAuthorizationFailure(
                    detail: "as-\(diagnostic.domain)-\(diagnostic.code)"
                )
            }
        }
    }
}

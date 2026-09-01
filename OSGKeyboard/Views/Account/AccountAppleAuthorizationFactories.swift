// AccountAppleAuthorizationFactories.swift
// OSGKeyboard · Main App / Mac
//
// Nonce generation and ASAuthorization → payload mapping, shared by the iOS
// account center and the macOS account page. Extracted from
// `AccountAppleAuthorizationButton.swift` (iOS-only view) so both platforms
// run the identical credential validation instead of a second copy.

import AuthenticationServices
import Foundation
#if canImport(OSGKeyboardHostSupport)
import OSGKeyboardHostSupport
#endif

/// Whether an Apple authorization pass is establishing a session or
/// re-authenticating for account deletion.
enum AccountAppleAuthorizationPurpose {
    case signIn
    case deleteAccount
}

enum AccountAppleAuthorizationPayload {
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
              !authorizationCode.isEmpty,
              !credential.user.isEmpty
        else {
            return nil
        }

        return AppleAuthorizationPayload(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: rawNonce,
            displayName: displayName(from: credential.fullName),
            userIdentifier: credential.user
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

enum AccountAppleNonce {
    static func make() -> AppleSignInNonce? {
        // Do not fall back to a merely unique identifier if the system RNG is
        // unavailable. The completion path rejects authorization without a
        // cryptographically random raw nonce.
        return try? AppleSignInNonceGenerator().makeNonce()
    }
}

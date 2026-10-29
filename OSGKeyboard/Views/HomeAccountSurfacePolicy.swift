// HomeAccountSurfacePolicy.swift
// OSGKeyboard · Main App
//
// Decides the single account / setup surface Home shows above the usage
// metrics: a problem card or the quiet account summary, never both, so Home
// carries at most one account-related card on iPhone, iPhone Duo (folded or
// unfolded), and iPad.

import CoreGraphics
import OSGKeyboardShared

/// Which AI service the current configuration can actually serve right now.
enum HomeServiceReadiness: Equatable {
    /// OSG credits through the managed gateway.
    case credits
    /// The user's own API keys for recognition and polish.
    case ownKey
    /// Dictation works (on-device, or BYOK cloud ASR) but AI polish has no key.
    case dictationOnly
    /// Nothing can transcribe yet: cloud ASR without a key, or credits while signed out.
    case unavailable

    var canDictate: Bool { self != .unavailable }

    var isFullyConfigured: Bool { self == .credits || self == .ownKey }
}

/// Account session reduced to what Home needs.
enum HomeAccountPhase: Equatable {
    case restoring
    case signedOut
    case signedIn
}

/// Credit snapshot reduced to what Home needs.
enum HomeCreditsState: Equatable {
    /// Not loaded yet. Treated as healthy so Home never flashes an error card.
    case loading
    /// No snapshot could be loaded at all (a stale snapshot stays `.balance`).
    case failed
    case balance(Int64)
}

enum HomeAccountSurface: Equatable {
    case permissions
    case invitation(code: String)
    case signInSetup
    case chooseService
    case creditsUnavailable
    case creditsDepleted
    case signInPromo
    case accountSummary
}

enum HomeAccountSurfacePolicy {
    static func readiness(
        credentialSource: CredentialSource,
        account: HomeAccountPhase,
        isASRConfigured: Bool,
        isPolishConfigured: Bool
    ) -> HomeServiceReadiness {
        switch credentialSource {
        case .managed:
            // Restoring keeps credits: a valid session is usually seconds away.
            return account == .signedOut ? .unavailable : .credits
        case .byok:
            guard isASRConfigured else { return .unavailable }
            return isPolishConfigured ? .ownKey : .dictationOnly
        }
    }

    /// First matching rule wins. `nil` means no account surface at all.
    static func surface(
        needsPermissionSetup: Bool,
        account: HomeAccountPhase,
        pendingReferralCode: String?,
        isInvitationDeferred: Bool,
        credentialSource: CredentialSource,
        readiness: HomeServiceReadiness,
        credits: HomeCreditsState
    ) -> HomeAccountSurface? {
        if needsPermissionSetup {
            return .permissions
        }
        switch account {
        case .restoring:
            // Avoid showing a sign-in card that a restored session replaces.
            return nil
        case .signedOut:
            if let pendingReferralCode, !isInvitationDeferred {
                return .invitation(code: pendingReferralCode)
            }
            return readiness.isFullyConfigured ? .signInPromo : .signInSetup
        case .signedIn:
            guard credentialSource == .managed else {
                return readiness.isFullyConfigured ? .accountSummary : .chooseService
            }
            switch credits {
            case .failed:
                return .creditsUnavailable
            case .balance(let remaining) where remaining <= 0:
                return .creditsDepleted
            case .loading, .balance:
                return .accountSummary
            }
        }
    }
}

enum HomeLayoutPolicy {
    /// An unfolded iPhone Duo can report a compact size class while offering
    /// iPad-mini-like width, so Home also switches on its own measured width.
    static let wideMinimumWidth: CGFloat = 600

    static func usesWideLayout(isRegularWidth: Bool, containerWidth: CGFloat) -> Bool {
        isRegularWidth || containerWidth >= wideMinimumWidth
    }
}

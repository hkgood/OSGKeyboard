// HomeAccountSurfacePolicyTests.swift
// OSGKeyboardTests

@testable import OSGKeyboard
import OSGKeyboardShared
import XCTest

final class HomeAccountSurfacePolicyTests: XCTestCase {

    // MARK: - Readiness

    func testCreditsNeedAnAccountButSurviveRestore() {
        XCTAssertEqual(readiness(.managed, account: .signedIn), .credits)
        XCTAssertEqual(readiness(.managed, account: .restoring), .credits)
        XCTAssertEqual(readiness(.managed, account: .signedOut), .unavailable)
    }

    func testOwnKeyReadinessFollowsConfiguredKeys() {
        XCTAssertEqual(readiness(.byok, asr: true, polish: true), .ownKey)
        XCTAssertEqual(readiness(.byok, asr: true, polish: false), .dictationOnly)
        XCTAssertEqual(readiness(.byok, asr: false, polish: true), .unavailable)
    }

    // MARK: - Surface rules, in priority order

    func testMissingPermissionsOutrankEverything() {
        XCTAssertEqual(
            surface(needsPermissionSetup: true, account: .signedOut, pendingReferralCode: "K7M2Q9XA"),
            .permissions
        )
    }

    func testRestoringShowsNoAccountSurface() {
        XCTAssertNil(surface(account: .restoring, readiness: .dictationOnly))
    }

    func testSavedInvitationLeadsUntilDeferred() {
        XCTAssertEqual(
            surface(account: .signedOut, pendingReferralCode: "K7M2Q9XA"),
            .invitation(code: "K7M2Q9XA")
        )
        XCTAssertEqual(
            surface(
                account: .signedOut,
                pendingReferralCode: "K7M2Q9XA",
                isInvitationDeferred: true,
                readiness: .dictationOnly
            ),
            .signInSetup
        )
    }

    func testSignedOutWithoutWorkingServiceAsksToSignIn() {
        XCTAssertEqual(surface(account: .signedOut, readiness: .dictationOnly), .signInSetup)
        XCTAssertEqual(surface(account: .signedOut, readiness: .unavailable), .signInSetup)
        XCTAssertEqual(
            surface(account: .signedOut, credentialSource: .managed, readiness: .unavailable),
            .signInSetup
        )
    }

    func testSignedOutWithWorkingKeysOnlyGetsQuietPromo() {
        XCTAssertEqual(surface(account: .signedOut, readiness: .ownKey), .signInPromo)
    }

    func testCreditsConnectionFailureBecomesProblemCard() {
        XCTAssertEqual(
            surface(account: .signedIn, credentialSource: .managed, readiness: .credits, credits: .failed),
            .creditsUnavailable
        )
    }

    func testDepletedCreditsBecomeProblemCard() {
        XCTAssertEqual(
            surface(account: .signedIn, credentialSource: .managed, readiness: .credits, credits: .balance(0)),
            .creditsDepleted
        )
        XCTAssertEqual(
            surface(account: .signedIn, credentialSource: .managed, readiness: .credits, credits: .balance(-5)),
            .creditsDepleted
        )
    }

    func testHealthyOrLoadingCreditsStayQuiet() {
        XCTAssertEqual(
            surface(account: .signedIn, credentialSource: .managed, readiness: .credits, credits: .balance(1_500)),
            .accountSummary
        )
        XCTAssertEqual(
            surface(account: .signedIn, credentialSource: .managed, readiness: .credits, credits: .loading),
            .accountSummary
        )
    }

    func testSignedInWithoutKeysChoosesService() {
        XCTAssertEqual(surface(account: .signedIn, readiness: .dictationOnly), .chooseService)
        XCTAssertEqual(surface(account: .signedIn, readiness: .unavailable), .chooseService)
    }

    func testSignedInWithOwnKeysIgnoresCreditErrors() {
        XCTAssertEqual(surface(account: .signedIn, readiness: .ownKey, credits: .failed), .accountSummary)
        XCTAssertEqual(surface(account: .signedIn, readiness: .ownKey, credits: .balance(0)), .accountSummary)
    }

    func testSignedInIgnoresStalePendingInvitation() {
        XCTAssertEqual(
            surface(account: .signedIn, pendingReferralCode: "K7M2Q9XA", readiness: .ownKey),
            .accountSummary
        )
    }

    // MARK: - Layout

    func testUnfoldedDuoUsesWideLayoutEvenWithCompactSizeClass() {
        XCTAssertTrue(HomeLayoutPolicy.usesWideLayout(isRegularWidth: false, containerWidth: 669))
        XCTAssertFalse(HomeLayoutPolicy.usesWideLayout(isRegularWidth: false, containerWidth: 466))
        XCTAssertFalse(HomeLayoutPolicy.usesWideLayout(isRegularWidth: false, containerWidth: 402))
    }

    func testRegularSizeClassKeepsWideLayoutInsideSplitView() {
        XCTAssertTrue(HomeLayoutPolicy.usesWideLayout(isRegularWidth: true, containerWidth: 504))
    }

    func testWideTopClearanceOnlyWhereNoStatusBarSitsAbove() {
        // Landscape Duo inner display: status bar on the side, nothing above.
        XCTAssertEqual(WideLayoutMetrics.topCornerClearance(topSafeAreaInset: 0), Spacing.md)
        // iPad status bar, portrait Duo inner display (measured 82 pt).
        XCTAssertEqual(WideLayoutMetrics.topCornerClearance(topSafeAreaInset: 24), 0)
        XCTAssertEqual(WideLayoutMetrics.topCornerClearance(topSafeAreaInset: 82), 0)
        // A thin inset only gets topped up to the minimum.
        XCTAssertEqual(WideLayoutMetrics.topCornerClearance(topSafeAreaInset: 6), Spacing.md - 6)
    }

    // MARK: - Helpers

    private func readiness(
        _ source: CredentialSource,
        account: HomeAccountPhase = .signedIn,
        asr: Bool = true,
        polish: Bool = true
    ) -> HomeServiceReadiness {
        HomeAccountSurfacePolicy.readiness(
            credentialSource: source,
            account: account,
            isASRConfigured: asr,
            isPolishConfigured: polish
        )
    }

    private func surface(
        needsPermissionSetup: Bool = false,
        account: HomeAccountPhase,
        pendingReferralCode: String? = nil,
        isInvitationDeferred: Bool = false,
        credentialSource: CredentialSource = .byok,
        readiness: HomeServiceReadiness = .ownKey,
        credits: HomeCreditsState = .loading
    ) -> HomeAccountSurface? {
        HomeAccountSurfacePolicy.surface(
            needsPermissionSetup: needsPermissionSetup,
            account: account,
            pendingReferralCode: pendingReferralCode,
            isInvitationDeferred: isInvitationDeferred,
            credentialSource: credentialSource,
            readiness: readiness,
            credits: credits
        )
    }
}

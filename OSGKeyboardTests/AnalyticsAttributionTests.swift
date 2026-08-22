// AnalyticsAttributionTests.swift
// OSGKeyboardTests
//
// FIRST_OPEN attribution accepts only trusted, structured launch signals.

import Foundation
@testable import OSGKeyboard
import OSGKeyboardShared
import XCTest

final class AnalyticsAttributionTests: XCTestCase {
    private let validCode = "Abcdefghij_1234567890-"

    func testOrdinaryColdLaunchIsAppStoreOrganic() {
        XCTAssertEqual(
            AnalyticsFirstOpenAttribution.ordinaryLaunch,
            .appStoreOrganic
        )
    }

    func testTrustedReferralColdLaunchIsReferral() {
        let url = URL(string: "https://osglab.com/i/\(validCode)")!

        XCTAssertEqual(
            AnalyticsFirstOpenAttribution.trustedChannel(for: url),
            .referral
        )
    }

    func testUntrustedQueryCannotCreateSocialAttribution() {
        let untrusted = URL(
            string: "https://osglab.com/campaign?source=SOCIAL_CONTENT"
        )!
        let referralWithFreeText = URL(
            string: "https://osglab.com/i/\(validCode)?source=anything"
        )!

        XCTAssertNil(AnalyticsFirstOpenAttribution.trustedChannel(for: untrusted))
        XCTAssertEqual(
            AnalyticsFirstOpenAttribution.trustedChannel(for: referralWithFreeText),
            .referral
        )
    }
}

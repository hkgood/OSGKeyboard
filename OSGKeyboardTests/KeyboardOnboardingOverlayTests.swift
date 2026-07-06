// KeyboardOnboardingOverlayTests.swift
// OSGKeyboard · Tests
//
// v0.3.0: locks the AppGroupStore onboarding + app-context accessor
// wiring. These are the bytes the in-keyboard overlay reads every
// `viewWillAppear`, so a regression here breaks the first-launch UX
// silently (the overlay gets stuck on the welcome step, or the
// chip shows the wrong context).

import XCTest
@testable import OSGKeyboard
@testable import OSGKeyboardShared

final class KeyboardOnboardingOverlayTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Onboarding flags

    func testOnboardingFlagsDefaultFalseAndZero() {
        XCTAssertFalse(store.hasCompletedOnboarding, "fresh install should not show as onboarded")
        XCTAssertEqual(store.onboardingPage, 0, "fresh install should start at page 0")
    }

    func testOnboardingFlagsRoundTrip() {
        store.onboardingPage = 3
        XCTAssertEqual(store.onboardingPage, 3)
        store.hasCompletedOnboarding = true
        XCTAssertTrue(store.hasCompletedOnboarding)
        // Completing onboarding clears the in-progress page index.
        XCTAssertEqual(store.onboardingPage, 0)
    }

    func testOnboardingFlagsSurviveReconstruct() {
        store.onboardingPage = 4

        // Simulate the keyboard extension being torn down and rebuilt
        // (which is what happens on every `viewDidLoad` cycle).
        var store2 = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store2.onboardingPage, 4)

        store2.hasCompletedOnboarding = true
        let store3 = AppGroupStore(defaults: defaults)
        XCTAssertTrue(store3.hasCompletedOnboarding)
        XCTAssertEqual(store3.onboardingPage, 0)
    }

    // MARK: - App context detection round-trip

    func testDetectedAppContextRoundTrip() throws {
        let now = Date()
        store.setDetectedAppContext(.code, at: now)
        let result = store.detectedAppContext
        XCTAssertEqual(result?.context, .code)
        let observedAt = try XCTUnwrap(result?.observedAt)
        XCTAssertEqual(observedAt.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate,
                       accuracy: 0.001)
    }

    func testDetectedAppContextOverwrite() {
        store.setDetectedAppContext(.code)
        store.setDetectedAppContext(.email)
        XCTAssertEqual(store.detectedAppContext?.context, .email,
                       "second setDetectedAppContext must overwrite the first")
    }

    func testDetectedAppContextEmptyBeforeSet() {
        XCTAssertNil(store.detectedAppContext,
                     "detectedAppContext must be nil before any explicit set")
    }

    // MARK: - All cases enum surface

    func testAllAppContextCasesHaveRawValue() {
        // Locked: every case the LLM prompt knows about must be
        // serializable through App Group UserDefaults. Adding a new
        // case without a stable raw value silently breaks the cache.
        for context in AppContext.allCases {
            XCTAssertFalse(context.rawValue.isEmpty,
                           "AppContext.\(context) must have a non-empty rawValue")
        }
    }

    // MARK: - Polish intensity default

    func testPolishIntensityDefaultIsMedium() {
        XCTAssertEqual(store.polishIntensity, .medium,
                       "default polish intensity should match Typeless baseline")
    }

    func testPolishIntensityRoundTrip() {
        store.setPolishIntensity(.heavy)
        XCTAssertEqual(store.polishIntensity, .heavy)
        store.setPolishIntensity(.light)
        XCTAssertEqual(store.polishIntensity, .light)
    }

    func testPolishIntensityLegacyOffMigratesToMedium() {
        defaults.set(PolishIntensity.legacyOffRawValue, forKey: "config.polishIntensity")
        XCTAssertEqual(store.polishIntensity, .medium)
    }
}
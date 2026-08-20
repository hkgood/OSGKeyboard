// AppGroupOnboardingStoreTests.swift
// OSGKeyboard · Tests
//
// Locks AppGroupStore onboarding flags (host-app OnboardingView),
// detected app-context accessors, and polish intensity defaults.

@testable import OSGKeyboard
@testable import OSGKeyboardShared
import XCTest

final class AppGroupOnboardingStoreTests: XCTestCase {

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

    // MARK: - Onboarding flags (host app)

    func testOnboardingFlagsDefaultFalseAndZero() {
        XCTAssertFalse(store.hasCompletedOnboarding, "fresh install should not show as onboarded")
        XCTAssertEqual(store.onboardingPage, 0, "fresh install should start at page 0")
        XCTAssertEqual(store.polishIntensity, .light)
    }

    func testPolishIntensityRoundTrip() {
        store.setPolishIntensity(.heavy)

        XCTAssertEqual(AppGroupStore(defaults: defaults).polishIntensity, .heavy)
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

        var store2 = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store2.onboardingPage, 4)

        store2.hasCompletedOnboarding = true
        let store3 = AppGroupStore(defaults: defaults)
        XCTAssertTrue(store3.hasCompletedOnboarding)
        XCTAssertEqual(store3.onboardingPage, 0)
    }

    func testOnboardingPracticeWindowExpires() {
        let now = Date(timeIntervalSince1970: 1_000)
        KeyboardSetupBridge.setOnboardingPracticeActive(
            true,
            duration: 30,
            defaults: defaults,
            now: now
        )

        XCTAssertTrue(
            KeyboardSetupBridge.onboardingPracticeIsActive(
                defaults: defaults,
                now: now.addingTimeInterval(29)
            )
        )
        XCTAssertFalse(
            KeyboardSetupBridge.onboardingPracticeIsActive(
                defaults: defaults,
                now: now.addingTimeInterval(31)
            )
        )
    }

    func testDisablingOnboardingPracticeClearsWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        KeyboardSetupBridge.setOnboardingPracticeActive(
            true,
            defaults: defaults,
            now: now
        )
        KeyboardSetupBridge.setOnboardingPracticeActive(
            false,
            defaults: defaults,
            now: now
        )

        XCTAssertFalse(
            KeyboardSetupBridge.onboardingPracticeIsActive(
                defaults: defaults,
                now: now
            )
        )
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
        for context in AppContext.allCases {
            XCTAssertFalse(context.rawValue.isEmpty,
                           "AppContext.\(context) must have a non-empty rawValue")
        }
    }
}

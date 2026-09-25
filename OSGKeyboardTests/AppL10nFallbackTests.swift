// AppL10nFallbackTests.swift
// OSGKeyboard · Tests
//
// `AppGroupErrorView` is the screen the app shows when the App Group container
// is missing — its whole job is to turn a provisioning mistake into a readable
// message instead of a crash loop. It is built entirely from localized strings,
// so the moment `AppL10n` started resolving the UI language through
// `ProviderConfig` (which itself requires the App Group and traps without one)
// that screen crashed on launch, every launch, for exactly the users it exists
// to help.
//
// These tests run in an unsigned host where `AppGroup.isAvailable` is false, so
// they exercise the real failure path rather than a simulation of it.

@testable import OSGKeyboard
@testable import OSGKeyboardShared
import XCTest

final class AppL10nFallbackTests: XCTestCase {
    func testLocalizationResolvesWithoutAnAppGroup() throws {
        try XCTSkipIf(
            AppGroup.isAvailable,
            "Needs an unsigned host without an App Group container — the case the fallback exists for."
        )

        // Trapping here is the regression: this must return text, not crash.
        let title = AppL10n.string("appGroup.error.title")

        XCTAssertFalse(title.isEmpty)
        XCTAssertNotEqual(
            title,
            "appGroup.error.title",
            "the key came back unresolved, so the error screen would show a raw key"
        )
    }

    func testEveryStringOnTheAppGroupErrorScreenResolves() throws {
        try XCTSkipIf(AppGroup.isAvailable, "Needs an unsigned host without an App Group container.")

        for key in [
            "appGroup.error.title",
            "appGroup.error.body",
            "appGroup.error.step1",
            "appGroup.error.step2",
            "appGroup.error.step3"
        ] {
            let value = AppL10n.string(key)
            XCTAssertFalse(value.isEmpty, "\(key) resolved to an empty string")
            XCTAssertNotEqual(value, key, "\(key) is missing from Localizable.strings")
        }
    }

    func testExplicitLanguageStillWinsWithoutAnAppGroup() throws {
        try XCTSkipIf(AppGroup.isAvailable, "Needs an unsigned host without an App Group container.")

        // The fallback must only supply a *default*; a caller that knows the
        // language must still be honoured.
        let english = AppL10n.string("appGroup.error.title", language: .english)
        let chinese = AppL10n.string("appGroup.error.title", language: .chinese)

        XCTAssertFalse(english.isEmpty)
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertNotEqual(english, chinese)
    }
}

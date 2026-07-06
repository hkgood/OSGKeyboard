// AppGroupConfigurationTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class AppGroupConfigurationTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.config.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testLoadDefaultsWhenSuiteIsEmpty() {
        let defaults = makeDefaults()
        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.providerId, "openai")
        XCTAssertEqual(config.modeId, "polish")
        XCTAssertEqual(config.localeId, "auto")
        XCTAssertEqual(config.engineMode, "cloud")
        XCTAssertFalse(config.hasCompletedOnboarding)
        XCTAssertEqual(config.onboardingPage, 0)
        XCTAssertFalse(config.hasAcknowledgedCloudSharing)
        XCTAssertEqual(config.translationTargetLocaleId, TranslationLanguageCatalog.offLocaleId)
        XCTAssertFalse(config.translationEnabled)
        XCTAssertEqual(config.handednessPreference, .left)
        XCTAssertTrue(config.cursorDragNavigationEnabled)
        XCTAssertEqual(config.polishIntensity, .default)
        XCTAssertTrue(config.personalDictionary.entries.isEmpty)
        XCTAssertTrue(config.flowSkipAppSwitch)
        XCTAssertEqual(config.flowInactivityDuration, .twelveHours)
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.providerId = "anthropic"
        config.baseURL = "https://example.com/v1"
        config.model = "claude-test"
        config.modeId = "polish"
        config.localeId = "zh-Hans"
        config.engineMode = "local"
        config.hasCompletedOnboarding = true
        config.onboardingPage = 2
        config.hasAcknowledgedCloudSharing = true
        config.uiLanguage = .chinese
        config.translationTargetLocaleId = "en"
        config.handednessPreference = .right
        config.cursorDragNavigationEnabled = false
        config.polishIntensity = .light
        config.flowSkipAppSwitch = false
        config.flowInactivityDuration = .thirtyMinutes
        config.save(to: defaults)

        let loaded = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(loaded.providerId, "anthropic")
        XCTAssertEqual(loaded.baseURL, "https://example.com/v1")
        XCTAssertEqual(loaded.model, "claude-test")
        XCTAssertEqual(loaded.localeId, "zh-Hans")
        XCTAssertEqual(loaded.engineMode, "local")
        XCTAssertTrue(loaded.hasCompletedOnboarding)
        XCTAssertEqual(loaded.onboardingPage, 2)
        XCTAssertTrue(loaded.hasAcknowledgedCloudSharing)
        XCTAssertEqual(loaded.uiLanguage, .chinese)
        XCTAssertEqual(loaded.translationTargetLocaleId, "en")
        XCTAssertTrue(loaded.translationEnabled)
        XCTAssertEqual(loaded.handednessPreference, .right)
        XCTAssertFalse(loaded.cursorDragNavigationEnabled)
        XCTAssertEqual(loaded.polishIntensity, .light)
        XCTAssertFalse(loaded.flowSkipAppSwitch)
        XCTAssertEqual(loaded.flowInactivityDuration, .thirtyMinutes)
    }

    func testTranslationEnabledDerivedFromTargetLocale() {
        let defaults = makeDefaults()
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertFalse(config.translationEnabled)

        config.translationTargetLocaleId = "ja"
        XCTAssertTrue(config.translationEnabled)

        config.translationTargetLocaleId = TranslationLanguageCatalog.offLocaleId
        XCTAssertFalse(config.translationEnabled)
    }

    func testCloudDeepSeekProviderMigratesToOpenAI() {
        let defaults = makeDefaults()
        defaults.set("deepseek", forKey: AppGroupConfiguration.Keys.providerId)
        defaults.set("cloud", forKey: AppGroupConfiguration.Keys.engineMode)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(config.providerId, "openai")
        XCTAssertEqual(defaults.string(forKey: AppGroupConfiguration.Keys.providerId), "openai")
    }

    func testPolishIntensityLegacyOffMigratesToMedium() {
        let defaults = makeDefaults()
        defaults.set(PolishIntensity.legacyOffRawValue, forKey: AppGroupConfiguration.Keys.polishIntensity)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(config.polishIntensity, .medium)
        XCTAssertEqual(defaults.string(forKey: AppGroupConfiguration.Keys.polishIntensity), PolishIntensity.medium.rawValue)
    }

    func testLoadFromNilUsesAppGroupWhenAvailable() {
        if AppGroup.defaultsIfAvailable != nil {
            XCTAssertNotNil(AppGroupConfiguration.load(from: nil))
        } else {
            XCTAssertNil(AppGroupConfiguration.load(from: nil))
        }
    }
}

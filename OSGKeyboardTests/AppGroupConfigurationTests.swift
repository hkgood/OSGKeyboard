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
        // Privacy-critical: the default engine must keep audio on-device.
        XCTAssertEqual(config.engineMode, "local")
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
        XCTAssertEqual(config.flowInactivityDuration, .thirtyMinutes)
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.providerId = "anthropic"
        config.baseURL = "https://example.com/v1"
        config.model = "claude-test"
        config.asrProviderId = "zhipu"
        config.asrBaseURL = "https://open.bigmodel.cn/api/paas/v4"
        config.asrModel = "glm-asr-2512"
        config.modeId = "polish"
        config.localeId = "zh-Hans"
        // Non-default value so the round-trip proves persistence.
        config.engineMode = "cloud"
        config.hasCompletedOnboarding = true
        config.onboardingPage = 2
        config.hasAcknowledgedCloudSharing = true
        config.uiLanguage = .chinese
        config.translationTargetLocaleId = "en"
        config.handednessPreference = .right
        config.cursorDragNavigationEnabled = false
        config.polishIntensity = .light
        config.flowSkipAppSwitch = false
        // Use a non-default value so the round-trip actually proves persistence.
        config.flowInactivityDuration = .threeHours
        config.save(to: defaults)

        let loaded = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(loaded.providerId, "anthropic")
        XCTAssertEqual(loaded.baseURL, "https://example.com/v1")
        XCTAssertEqual(loaded.model, "claude-test")
        XCTAssertEqual(loaded.asrProviderId, "zhipu")
        XCTAssertEqual(loaded.asrBaseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(loaded.asrModel, "glm-asr-2512")
        XCTAssertEqual(loaded.localeId, "zh-Hans")
        XCTAssertEqual(loaded.engineMode, "cloud")
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
        XCTAssertEqual(loaded.flowInactivityDuration, .threeHours)
    }

    /// Existing installs (onboarding completed, no explicit engineMode key)
    /// ran on the old "cloud"/12h defaults — a silent flip to the new
    /// privacy defaults would change their engine under them AND propagate
    /// through settings sync as a fake fresh edit to their other devices.
    func testDefaultMigrationPreservesExistingInstallBehavior() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.engineMode, "cloud", "pre-picker installs stay on their old default")
        XCTAssertEqual(config.flowInactivityDuration, .twelveHours)
        // The resolution is persisted so it is stable and sync-invisible.
        XCTAssertEqual(defaults.string(forKey: AppGroupConfiguration.Keys.engineMode), "cloud")
        XCTAssertEqual(
            defaults.string(forKey: AppGroupConfiguration.Keys.flowInactivityDuration),
            FlowInactivityDuration.twelveHours.rawValue
        )
    }

    func testDefaultMigrationGivesFreshInstallPrivacyDefaults() {
        let defaults = makeDefaults()

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.engineMode, "local")
        XCTAssertEqual(config.flowInactivityDuration, .thirtyMinutes)
        XCTAssertEqual(defaults.string(forKey: AppGroupConfiguration.Keys.engineMode), "local")
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

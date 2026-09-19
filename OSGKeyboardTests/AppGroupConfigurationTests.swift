// AppGroupConfigurationTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

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

        XCTAssertEqual(config.providerId, "deepseek")
        XCTAssertEqual(config.asrProviderId, "volcengine")
        XCTAssertEqual(config.modeId, "polish")
        XCTAssertEqual(config.localeId, "auto")
        // Privacy-critical: the default engine must keep audio on-device.
        XCTAssertEqual(config.engineMode, "local")
        XCTAssertEqual(config.credentialSource, .byok)
        XCTAssertFalse(config.hasCompletedOnboarding)
        XCTAssertEqual(config.onboardingPage, 0)
        XCTAssertFalse(config.hasAcknowledgedCloudSharing)
        XCTAssertEqual(config.translationTargetLocaleId, TranslationLanguageCatalog.offLocaleId)
        XCTAssertFalse(config.translationEnabled)
        XCTAssertEqual(config.handednessPreference, .left)
        // Legacy field remains decode-compatible after the UI feature was removed.
        XCTAssertFalse(config.cursorDragNavigationEnabled)
        XCTAssertEqual(config.keyboardHapticIntensity, .light)
        XCTAssertEqual(config.polishIntensity, .light)
        XCTAssertEqual(config.aiResponseLength, .medium)
        XCTAssertTrue(config.personalDictionary.entries.isEmpty)
        XCTAssertTrue(config.flowSkipAppSwitch)
        XCTAssertEqual(config.flowInactivityDuration, .fiveMinutes)
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
        config.credentialSource = .managed
        config.hasCompletedOnboarding = true
        config.onboardingPage = 2
        config.hasAcknowledgedCloudSharing = true
        config.uiLanguage = .chinese
        config.translationTargetLocaleId = "en"
        config.handednessPreference = .right
        config.cursorDragNavigationEnabled = false
        config.keyboardHapticIntensity = .strong
        config.polishIntensity = .heavy
        config.aiResponseLength = .short
        config.flowSkipAppSwitch = false
        // Use a non-default value so the round-trip actually proves persistence.
        config.flowInactivityDuration = .threeHours
        // Non-default so the round-trip proves the auto-mode flags persist.
        config.clipboardAutoModeEnabled = true
        config.clipboardAutoTranslateEnabled = true
        config.clipboardAutoEmailReplyEnabled = true
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
        XCTAssertEqual(loaded.credentialSource, .managed)
        XCTAssertTrue(loaded.hasCompletedOnboarding)
        XCTAssertEqual(loaded.onboardingPage, 2)
        XCTAssertTrue(loaded.hasAcknowledgedCloudSharing)
        XCTAssertEqual(loaded.uiLanguage, .chinese)
        XCTAssertEqual(loaded.translationTargetLocaleId, "en")
        XCTAssertTrue(loaded.translationEnabled)
        XCTAssertEqual(loaded.handednessPreference, .right)
        XCTAssertFalse(loaded.cursorDragNavigationEnabled)
        XCTAssertEqual(loaded.keyboardHapticIntensity, .strong)
        XCTAssertEqual(loaded.polishIntensity, .heavy)
        XCTAssertEqual(loaded.aiResponseLength, .short)
        XCTAssertFalse(loaded.flowSkipAppSwitch)
        XCTAssertEqual(loaded.flowInactivityDuration, .threeHours)
        XCTAssertTrue(loaded.clipboardAutoModeEnabled)
        XCTAssertTrue(loaded.clipboardAutoTranslateEnabled)
        XCTAssertTrue(loaded.clipboardAutoEmailReplyEnabled)
    }

    func testAppGroupStorePersistsLocaleChanges() {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)

        store.setLocaleId("en-US")

        XCTAssertEqual(store.localeId, "en-US")
    }

    func testRemovedCursorDragSettingStillDecodesLegacyValue() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppGroupConfiguration.Keys.cursorDragNavigationEnabled)

        let loaded = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertTrue(loaded.cursorDragNavigationEnabled)
    }

    func testFieldLevelSavePreservesNewerUnrelatedProcessChange() {
        let defaults = makeDefaults()
        let baseline = AppGroupConfiguration.load(fromAvailable: defaults)
        var mainAppSnapshot = baseline
        var extensionSnapshot = baseline

        mainAppSnapshot.uiLanguage = .chinese
        mainAppSnapshot.saveChanges(since: baseline, to: defaults)

        extensionSnapshot.engineMode = "cloud"
        extensionSnapshot.saveChanges(since: baseline, to: defaults)

        let loaded = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(loaded.uiLanguage, .chinese)
        XCTAssertEqual(loaded.engineMode, "cloud")
    }

    func testRetiredMediumPolishIntensityMigratesToLight() {
        let defaults = makeDefaults()
        defaults.set("medium", forKey: AppGroupConfiguration.Keys.polishIntensity)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.polishIntensity, .light)
    }

    /// Existing installs retain their legacy engine, but an unset inactivity
    /// duration adopts the current privacy-safe default.
    func testDefaultMigrationUsesPrivacySafeInactivityDuration() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.engineMode, "cloud", "pre-picker installs stay on their old default")
        XCTAssertEqual(config.flowInactivityDuration, .fiveMinutes)
        // The resolution is persisted so it is stable and sync-invisible.
        XCTAssertEqual(defaults.string(forKey: AppGroupConfiguration.Keys.engineMode), "cloud")
        XCTAssertEqual(
            defaults.string(forKey: AppGroupConfiguration.Keys.flowInactivityDuration),
            FlowInactivityDuration.fiveMinutes.rawValue
        )
    }

    func testPreviousDefaultInactivityIsMigratedToFiveMinutesOnce() {
        let defaults = makeDefaults()
        defaults.set(FlowInactivityDuration.thirtyMinutes.rawValue,
                     forKey: AppGroupConfiguration.Keys.flowInactivityDuration)

        let first = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(first.flowInactivityDuration, .fiveMinutes)
        XCTAssertTrue(defaults.bool(
            forKey: AppGroupConfiguration.Keys.flowInactivityMigratedToFiveMinuteDefault
        ))

        // After migration, an explicit 30-minute choice sticks.
        var updated = first
        updated.flowInactivityDuration = .thirtyMinutes
        updated.save(to: defaults)
        let second = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(second.flowInactivityDuration, .thirtyMinutes)
    }

    // MARK: - Personal reply style split

    private func seedCatalog(
        _ defaults: UserDefaults,
        entries: [PolishStylePack],
        activeID: String
    ) {
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        for entry in entries {
            try? config.polishStyleCatalog.upsert(entry)
        }
        config.activePolishStyleId = activeID
        config.save(to: defaults)
        // The split migration may already have run during the load above.
        defaults.removeObject(forKey: AppGroupConfiguration.Keys.personalReplyStyleMigrated)
        defaults.removeObject(forKey: AppGroupConfiguration.Keys.personalReplyStyleId)
        defaults.set(activeID, forKey: AppGroupConfiguration.Keys.activePolishStyleId)
    }

    /// The reported bug: a selected personal style outranked the core filler
    /// cleanup. Migration hands it to replies and gives dictation its default back.
    func testActiveDistilledStyleMovesToRepliesAndVoiceFallsBack() {
        let defaults = makeDefaults()
        let distilled = PolishStylePackTests.distilledPack()
        seedCatalog(defaults, entries: [distilled], activeID: distilled.id)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.activePolishStyleId, PolishStylePackCatalog.defaultID)
        XCTAssertEqual(config.personalReplyStyleId, distilled.id)
    }

    /// These users had generated a personal style but could not use it: the
    /// single selector forced them to choose voice cleanup instead.
    func testUnusedDistilledStyleIsAdoptedForReplies() {
        let defaults = makeDefaults()
        let distilled = PolishStylePackTests.distilledPack()
        seedCatalog(defaults, entries: [distilled], activeID: PolishStylePackCatalog.defaultID)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.activePolishStyleId, PolishStylePackCatalog.defaultID)
        XCTAssertEqual(config.personalReplyStyleId, distilled.id)
    }

    func testHandWrittenStyleStaysOnVoiceAndNeverDrivesReplies() {
        let defaults = makeDefaults()
        let handWritten = PolishStylePack(id: "user.handwritten", name: "手写", prompt: "长句")
        seedCatalog(defaults, entries: [handWritten], activeID: handWritten.id)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.activePolishStyleId, handWritten.id)
        XCTAssertEqual(config.personalReplyStyleId, "")
    }

    func testPersonalReplyStyleMigrationRunsOnce() {
        let defaults = makeDefaults()
        let distilled = PolishStylePackTests.distilledPack()
        seedCatalog(defaults, entries: [distilled], activeID: distilled.id)

        let first = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(first.personalReplyStyleId, distilled.id)
        XCTAssertTrue(
            defaults.bool(forKey: AppGroupConfiguration.Keys.personalReplyStyleMigrated)
        )

        // A later opt-out must not be undone by a second load.
        var updated = first
        updated.personalReplyStyleId = ""
        updated.save(to: defaults)

        XCTAssertEqual(AppGroupConfiguration.load(fromAvailable: defaults).personalReplyStyleId, "")
    }

    func testStoreRejectsDistilledStyleAsVoiceSelection() {
        let defaults = makeDefaults()
        let distilled = PolishStylePackTests.distilledPack()
        seedCatalog(defaults, entries: [distilled], activeID: PolishStylePackCatalog.defaultID)
        let store = AppGroupStore(defaults: defaults)

        store.setActivePolishStyleId(distilled.id)

        XCTAssertEqual(store.activePolishStyleId, PolishStylePackCatalog.defaultID)
    }

    func testStoreRejectsHandWrittenStyleAsReplySelection() {
        let defaults = makeDefaults()
        let handWritten = PolishStylePack(id: "user.handwritten", name: "手写", prompt: "长句")
        seedCatalog(defaults, entries: [handWritten], activeID: PolishStylePackCatalog.defaultID)
        let store = AppGroupStore(defaults: defaults)

        store.setPersonalReplyStyleId(handWritten.id)

        XCTAssertEqual(store.personalReplyStyleId, "")
        XCTAssertNil(store.personalReplyStyle)
    }

    /// The half the instruction tests cannot see: they hand-build a context, so
    /// nothing pinned the path from a stored pack to the prompt the model reads.
    /// This walks the production chain — App Group pack -> `personalReplyStyle`
    /// -> `resolve` -> `instruction(for:)` — and asserts the user's own wording
    /// reaches "Speak as me". A break anywhere in it degrades the skill into
    /// generic polish without failing any other test.
    func testSpeakAsMeInstructionCarriesTheStoredPersonalStyle() throws {
        let defaults = makeDefaults()
        let distilled = PolishStylePackTests.distilledPack()
        seedCatalog(defaults, entries: [distilled], activeID: PolishStylePackCatalog.defaultID)
        let store = AppGroupStore(defaults: defaults)
        store.setPersonalReplyStyleId(distilled.id)

        let context = try XCTUnwrap(
            AIClipboardReplyStyleContext.resolve(personalReplyStyle: store.personalReplyStyle)
        )
        XCTAssertEqual(context.styleID, distilled.id)

        let skill = try XCTUnwrap(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.speakAsMeID)
        )
        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: "zh",
            translationTargetLocaleId: "en",
            replyStyle: context
        )

        XCTAssertTrue(instruction.contains(distilled.prompt))
        XCTAssertTrue(instruction.contains("<user_reply_style id=\"\(distilled.id)\">"))
    }

    /// `supportsReplyStyle` is false for this skill, so a composer that checked
    /// that flag before injecting the style would silently strip it.
    func testSpeakAsMeGetsTheStyleDespiteNotSupportingTheReplyStylePath() throws {
        let skill = try XCTUnwrap(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.speakAsMeID)
        )
        XCTAssertFalse(skill.supportsReplyStyle)

        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: "zh",
            translationTargetLocaleId: "en",
            replyStyle: AIClipboardReplyStyleContext(
                styleID: "user.learned",
                prompt: "句子要短，先说结论"
            )
        )

        XCTAssertTrue(instruction.contains("句子要短，先说结论"))
    }

    func testDeletingPersonalStyleDisablesPersonalizedReplies() {
        let defaults = makeDefaults()
        let distilled = PolishStylePackTests.distilledPack()
        seedCatalog(defaults, entries: [distilled], activeID: PolishStylePackCatalog.defaultID)
        let store = AppGroupStore(defaults: defaults)
        store.setPersonalReplyStyleId(distilled.id)
        XCTAssertNotNil(store.personalReplyStyle)

        store.deletePolishStylePack(id: distilled.id)

        XCTAssertEqual(store.personalReplyStyleId, "")
        XCTAssertNil(store.personalReplyStyle)
    }

    func testDefaultMigrationGivesFreshInstallPrivacyDefaults() {
        let defaults = makeDefaults()

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertEqual(config.engineMode, "local")
        XCTAssertEqual(config.flowInactivityDuration, .fiveMinutes)
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

    func testCloudDeepSeekProviderIsPreserved() {
        let defaults = makeDefaults()
        defaults.set("deepseek", forKey: AppGroupConfiguration.Keys.providerId)
        defaults.set("cloud", forKey: AppGroupConfiguration.Keys.engineMode)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(config.providerId, "deepseek")
        XCTAssertEqual(defaults.string(forKey: AppGroupConfiguration.Keys.providerId), "deepseek")
    }

    func testManagedCredentialsDoNotRequireBYOKKeys() {
        let defaults = makeDefaults()
        defaults.set("cloud", forKey: AppGroupConfiguration.Keys.engineMode)
        defaults.set(CredentialSource.managed.rawValue,
                     forKey: AppGroupConfiguration.Keys.credentialSource)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertFalse(config.isPolishKeyMissing)
        XCTAssertFalse(config.isCloudLLMKeyMissing)
        XCTAssertFalse(config.isCloudASRKeyMissing)
        XCTAssertFalse(config.isCloudAPIKeyMissingForVoiceInput)
    }

    func testLoadFromNilUsesAppGroupWhenAvailable() {
        if AppGroup.defaultsIfAvailable != nil {
            XCTAssertNotNil(AppGroupConfiguration.load(from: nil))
        } else {
            XCTAssertNil(AppGroupConfiguration.load(from: nil))
        }
    }
}

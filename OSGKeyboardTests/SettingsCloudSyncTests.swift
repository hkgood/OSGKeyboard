// SettingsCloudSyncTests.swift
// OSGKeyboardTests
//
// Hermetic tests for iCloud KVS settings sync + preference toggles.

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class SettingsCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!
    private var kvs: FakeUbiquitousKeyValueStore!
    private var settingsSync: SettingsCloudSync!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
        kvs = FakeUbiquitousKeyValueStore()
        settingsSync = SettingsCloudSync(kvs: kvs) { [unowned self] in store }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMergePrefersNewerUpdatedAt() {
        let older = SyncedAppSettings(
            updatedAt: Date(timeIntervalSince1970: 100),
            providerId: "openai",
            baseURL: "https://old.example",
            model: "gpt-old",
            modeId: "polish",
            localeId: "auto",
            engineMode: "cloud",
            hasAcknowledgedCloudSharing: false,
            uiLanguage: .english,
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            handednessPreference: .left,
            cursorDragNavigationEnabled: true,
            polishIntensity: .medium,
            flowSkipAppSwitch: true,
            flowInactivityDuration: .twelveHours
        )
        let newer = SyncedAppSettings(
            updatedAt: Date(timeIntervalSince1970: 200),
            providerId: "openai",
            baseURL: "https://new.example",
            model: "gpt-new",
            modeId: "polish",
            localeId: "zh-Hans",
            engineMode: "local",
            hasAcknowledgedCloudSharing: true,
            uiLanguage: .chinese,
            translationTargetLocaleId: "en",
            handednessPreference: .right,
            cursorDragNavigationEnabled: false,
            polishIntensity: .light,
            flowSkipAppSwitch: false,
            flowInactivityDuration: .threeHours
        )

        let merged = SyncedAppSettings.merge(local: older, remote: newer)
        XCTAssertEqual(merged.model, "gpt-new")
        XCTAssertEqual(merged.localeId, "zh-Hans")
        XCTAssertEqual(merged.engineMode, "local")
    }

    func testEnableSyncUploadsMergedSettingsAndToggle() async throws {
        store.setModeId("polish")
        store.setLocaleId("zh-Hans")

        let remote = SyncedAppSettings(
            updatedAt: Date().addingTimeInterval(3600),
            providerId: "openai",
            baseURL: "https://remote.example",
            model: "remote-model",
            modeId: "polish",
            localeId: "en",
            engineMode: "cloud",
            hasAcknowledgedCloudSharing: true,
            uiLanguage: .english,
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            handednessPreference: .right,
            cursorDragNavigationEnabled: true,
            polishIntensity: .medium,
            flowSkipAppSwitch: true,
            flowInactivityDuration: .twelveHours
        )
        try settingsSync.push(remote)

        try await settingsSync.enableSync()

        XCTAssertTrue(store.settingsICloudSyncEnabled)
        XCTAssertEqual(kvs.object(forKey: ICloudSyncPreferences.settingsEnabledKey) as? Bool, true)
        XCTAssertEqual(settingsSync.loadRemote()?.localeId, "en")
    }

    func testPullAndMergeAppliesRemoteSettingsToAppGroup() async throws {
        store.setSettingsICloudSyncEnabled(true)
        store.setLocaleId("auto")

        let remote = SyncedAppSettings(
            updatedAt: Date(timeIntervalSince1970: 900),
            providerId: "openai",
            baseURL: "https://remote.example",
            model: "remote-model",
            modeId: "polish",
            localeId: "ja",
            engineMode: "cloud",
            hasAcknowledgedCloudSharing: false,
            uiLanguage: .english,
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            handednessPreference: .left,
            cursorDragNavigationEnabled: true,
            polishIntensity: .medium,
            flowSkipAppSwitch: true,
            flowInactivityDuration: .twelveHours
        )
        try settingsSync.push(remote)

        await settingsSync.pullAndMerge(store: store)

        XCTAssertEqual(store.localeId, "ja")
        XCTAssertEqual(store.settingsCloudUpdatedAt?.timeIntervalSince1970, 900, accuracy: 1)
    }

    func testPushLocalIfEnabledSkipsWhenDisabled() async throws {
        store.setSettingsICloudSyncEnabled(false)
        store.setLocaleId("ko")

        try await settingsSync.pushLocalIfEnabled()

        XCTAssertNil(settingsSync.loadRemote())
    }

    func testICloudSyncPreferencesMigrateLegacyToggles() {
        store.setSettingsICloudSyncEnabled(false)
        store.setPersonalDictionaryICloudSyncEnabled(true)

        ICloudSyncPreferences.migrateLegacyTogglesIfNeeded(kvs: kvs, store: store)

        XCTAssertEqual(kvs.object(forKey: ICloudSyncPreferences.settingsEnabledKey) as? Bool, false)
        XCTAssertEqual(kvs.object(forKey: ICloudSyncPreferences.dictionaryEnabledKey) as? Bool, true)
    }

    func testAppGroupConfigurationDefaultsSettingsICloudSyncToOn() {
        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertTrue(config.settingsICloudSyncEnabled)
    }
}

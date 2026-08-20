// SettingsCloudSyncTests.swift
// OSGKeyboardTests
//
// Hermetic tests for iCloud KVS settings sync + preference toggles.

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class SettingsCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!
    private var kvs: FakeUbiquitousKeyValueStore!
    private var settingsSync: SettingsCloudSync!
    private let deviceA = "device-a"
    private let deviceB = "device-b"

    override func setUp() {
        super.setUp()
        Keychain.resetTestMemoryStore()
        suiteName = "group.com.osgkeyboard.shared.tests.settings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(deviceA, forKey: "sync.deviceID.v1")
        store = AppGroupStore(defaults: defaults)
        kvs = FakeUbiquitousKeyValueStore()
        settingsSync = SettingsCloudSync(
            kvs: kvs,
            makeStore: { [unowned self] in store }
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? Keychain.deleteAPIKey(for: "openai", useICloudSync: false)
        try? Keychain.deleteAPIKey(for: "openai", useICloudSync: true)
        try? Keychain.deleteAPIKey(for: "qwen", useICloudSync: false)
        try? Keychain.deleteAPIKey(for: "qwen", useICloudSync: true)
        try? Keychain.deleteASRAPIKey(for: "openai", useICloudSync: true)
        Keychain.resetTestMemoryStore()
        super.tearDown()
    }

    func testPerFieldMergeKeepsIndependentChanges() {
        let stampA = Date(timeIntervalSince1970: 100)
        let stampB = Date(timeIntervalSince1970: 200)
        let local = SyncedAppSettingsV2(
            providerId: SyncedField(value: "openai", updatedAt: stampA, deviceID: deviceA),
            baseURL: SyncedField(value: "https://local.example", updatedAt: stampA, deviceID: deviceA),
            model: SyncedField(value: "gpt-local", updatedAt: stampA, deviceID: deviceA),
            asrProviderId: SyncedField(value: "zhipu", updatedAt: stampA, deviceID: deviceA),
            asrBaseURL: SyncedField(value: "https://asr-local.example", updatedAt: stampA, deviceID: deviceA),
            asrModel: SyncedField(value: "glm-asr-local", updatedAt: stampA, deviceID: deviceA),
            modeId: SyncedField(value: "polish", updatedAt: stampA, deviceID: deviceA),
            localeId: SyncedField(value: "auto", updatedAt: stampA, deviceID: deviceA),
            engineMode: SyncedField(value: "cloud", updatedAt: stampA, deviceID: deviceA),
            hasAcknowledgedCloudSharing: SyncedField(value: false, updatedAt: stampA, deviceID: deviceA),
            uiLanguage: SyncedField(value: .english, updatedAt: stampA, deviceID: deviceA),
            translationTargetLocaleId: SyncedField(
                value: TranslationLanguageCatalog.offLocaleId,
                updatedAt: stampA,
                deviceID: deviceA
            ),
            handednessPreference: SyncedField(value: .left, updatedAt: stampA, deviceID: deviceA),
            cursorDragNavigationEnabled: SyncedField(value: true, updatedAt: stampA, deviceID: deviceA),
            keyboardHapticIntensity: SyncedField(value: .light, updatedAt: stampA, deviceID: deviceA),
            polishIntensity: SyncedField(value: .light, updatedAt: stampA, deviceID: deviceA),
            aiResponseLength: SyncedField(value: .medium, updatedAt: stampA, deviceID: deviceA),
            activePolishStyleId: SyncedField(value: "builtin.light", updatedAt: stampA, deviceID: deviceA),
            llmThinkingEnabled: SyncedField(value: false, updatedAt: stampA, deviceID: deviceA),
            flowSkipAppSwitch: SyncedField(value: true, updatedAt: stampA, deviceID: deviceA),
            flowInactivityDuration: SyncedField(value: .twelveHours, updatedAt: stampA, deviceID: deviceA)
        )
        let remote = SyncedAppSettingsV2(
            providerId: SyncedField(value: "openai", updatedAt: stampA, deviceID: deviceB),
            baseURL: SyncedField(value: "https://remote.example", updatedAt: stampB, deviceID: deviceB),
            model: SyncedField(value: "gpt-remote", updatedAt: stampB, deviceID: deviceB),
            asrProviderId: SyncedField(value: "qwen", updatedAt: stampB, deviceID: deviceB),
            asrBaseURL: SyncedField(value: "https://asr-remote.example", updatedAt: stampB, deviceID: deviceB),
            asrModel: SyncedField(value: "fun-asr-remote", updatedAt: stampB, deviceID: deviceB),
            modeId: SyncedField(value: "polish", updatedAt: stampA, deviceID: deviceB),
            localeId: SyncedField(value: "ja", updatedAt: stampB, deviceID: deviceB),
            engineMode: SyncedField(value: "local", updatedAt: stampB, deviceID: deviceB),
            hasAcknowledgedCloudSharing: SyncedField(value: true, updatedAt: stampB, deviceID: deviceB),
            uiLanguage: SyncedField(value: .chinese, updatedAt: stampB, deviceID: deviceB),
            translationTargetLocaleId: SyncedField(value: "en", updatedAt: stampB, deviceID: deviceB),
            handednessPreference: SyncedField(value: .right, updatedAt: stampB, deviceID: deviceB),
            cursorDragNavigationEnabled: SyncedField(value: false, updatedAt: stampB, deviceID: deviceB),
            keyboardHapticIntensity: SyncedField(value: .strong, updatedAt: stampB, deviceID: deviceB),
            polishIntensity: SyncedField(value: .heavy, updatedAt: stampB, deviceID: deviceB),
            aiResponseLength: SyncedField(value: .detailed, updatedAt: stampB, deviceID: deviceB),
            activePolishStyleId: SyncedField(value: "builtin.formal", updatedAt: stampB, deviceID: deviceB),
            llmThinkingEnabled: SyncedField(value: true, updatedAt: stampB, deviceID: deviceB),
            flowSkipAppSwitch: SyncedField(value: false, updatedAt: stampB, deviceID: deviceB),
            flowInactivityDuration: SyncedField(value: .threeHours, updatedAt: stampB, deviceID: deviceB)
        )

        let merged = SyncedAppSettingsV2.merge(local: local, remote: remote)

        XCTAssertEqual(merged.baseURL.value, "https://remote.example")
        XCTAssertEqual(merged.asrProviderId.value, "qwen")
        XCTAssertEqual(merged.localeId.value, "ja")
        XCTAssertEqual(merged.engineMode.value, "local")
        XCTAssertEqual(merged.polishIntensity.value, .heavy)
        XCTAssertEqual(merged.aiResponseLength.value, .detailed)
    }

    func testLegacyKeepAliveFieldDecodesButIsNotReencoded() throws {
        let payload = SyncedAppSettingsV2.seeded(
            from: AppGroupConfiguration.load(fromAvailable: defaults),
            deviceID: deviceA,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String: Any]
        )
        object["flowKeepAliveMode"] = [
            "value": "liveActivity",
            "updatedAt": 0,
            "deviceID": "legacy-device"
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SyncedAppSettingsV2.self, from: legacyData)
        let reencodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(decoded)) as? [String: Any]
        )

        XCTAssertNil(reencodedObject["flowKeepAliveMode"])
    }

    func testLegacyClipboardFieldsDecodeButAreNotReencoded() throws {
        let payload = SyncedAppSettingsV2.seeded(
            from: AppGroupConfiguration.load(fromAvailable: defaults),
            deviceID: deviceA,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String: Any]
        )
        let legacyField = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoder.encode(
                    SyncedField(value: true, updatedAt: Date(timeIntervalSince1970: 200), deviceID: deviceB)
                )
            ) as? [String: Any]
        )
        object["clipboardHistoryEnabled"] = legacyField
        object["clipboardCandidateBarEnabled"] = legacyField
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try settingsSync.decodeV2(legacyData)
        let reencoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(decoded)) as? [String: Any]
        )

        XCTAssertNil(reencoded["clipboardHistoryEnabled"])
        XCTAssertNil(reencoded["clipboardCandidateBarEnabled"])
    }

    func testRemoteClipboardTrueDoesNotActivateLocalConsent() async throws {
        store.setSettingsICloudSyncEnabled(true)
        store.setClipboardHistoryEnabled(false)
        store.setClipboardCandidateBarEnabled(false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let remote = SyncedAppSettingsV2.seeded(
            from: AppGroupConfiguration.load(fromAvailable: defaults),
            deviceID: deviceB,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(remote)) as? [String: Any]
        )
        let remoteTrue = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoder.encode(
                    SyncedField(value: true, updatedAt: Date(timeIntervalSince1970: 900), deviceID: deviceB)
                )
            ) as? [String: Any]
        )
        object["clipboardHistoryEnabled"] = remoteTrue
        object["clipboardCandidateBarEnabled"] = remoteTrue
        kvs.set(
            try JSONSerialization.data(withJSONObject: object),
            forKey: SettingsCloudSync.kvsKey
        )

        await settingsSync.pullAndMerge(store: store)

        XCTAssertFalse(store.clipboardHistoryEnabled)
        XCTAssertFalse(store.clipboardCandidateBarEnabled)
    }

    func testClipboardTogglesRemainSharedThroughLocalAppGroupDefaults() {
        store.setClipboardHistoryEnabled(true)
        store.setClipboardCandidateBarEnabled(true)

        let extensionSideReader = AppGroupStore(defaults: defaults)

        XCTAssertTrue(extensionSideReader.clipboardHistoryEnabled)
        XCTAssertTrue(extensionSideReader.clipboardCandidateBarEnabled)
    }

    func testLegacyV1PullDoesNotClearKeychain() async throws {
        try Keychain.setAPIKey("sk-local-openai", for: "openai", useICloudSync: false)
        store.setSettingsICloudSyncEnabled(true)

        let legacy = SyncedAppSettings(
            updatedAt: Date().addingTimeInterval(3600),
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
            flowSkipAppSwitch: true,
            flowInactivityDuration: .twelveHours
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)
        kvs.set(data, forKey: SettingsCloudSync.legacyKVSKey)

        await settingsSync.pullAndMerge(store: store)

        XCTAssertEqual(Keychain.apiKey(for: "openai", preferICloudSync: false), "sk-local-openai")
        XCTAssertEqual(store.localeId, "ja")
    }

    func testEnableSyncMigratesKeysToICloudKeychain() async throws {
        try Keychain.setAPIKey("sk-local-openai", for: "openai", useICloudSync: false)

        try await settingsSync.enableSync()

        XCTAssertTrue(store.settingsICloudSyncEnabled)
        XCTAssertTrue(store.personalDictionaryICloudSyncEnabled)
        XCTAssertEqual(Keychain.apiKey(for: "openai", preferICloudSync: true), "sk-local-openai")
    }

    func testDisableSyncMigratesKeyLocallyBeforeTurningFlagsOff() throws {
        try Keychain.setAPIKey("synced-credential", for: "openai", useICloudSync: true)
        store.setSettingsICloudSyncEnabled(true)
        store.setPersonalDictionaryICloudSyncEnabled(true)

        try settingsSync.disableSync()

        XCTAssertFalse(store.settingsICloudSyncEnabled)
        XCTAssertFalse(store.personalDictionaryICloudSyncEnabled)
        XCTAssertNotNil(Keychain.apiKey(for: "openai", preferICloudSync: false))
    }

    func testDisableSyncFailureKeepsFlagsEnabled() {
        store.setSettingsICloudSyncEnabled(true)
        store.setPersonalDictionaryICloudSyncEnabled(true)
        ICloudSyncPreferences.pushSettingsEnabled(true, kvs: kvs)
        ICloudSyncPreferences.pushDictionaryEnabled(true, kvs: kvs)
        let failingSync = SettingsCloudSync(
            kvs: kvs,
            makeStore: { [unowned self] in store },
            migrateLocalKeysToICloud: {},
            migrateICloudKeysToLocal: {
                throw Keychain.CredentialMigrationError.conflict
            }
        )

        XCTAssertThrowsError(try failingSync.disableSync()) { error in
            XCTAssertEqual(
                error as? SettingsCloudSyncError,
                .credentialMigrationFailed(.conflict)
            )
        }
        XCTAssertTrue(store.settingsICloudSyncEnabled)
        XCTAssertTrue(store.personalDictionaryICloudSyncEnabled)
        XCTAssertEqual(
            kvs.object(forKey: ICloudSyncPreferences.settingsEnabledKey) as? Bool,
            true
        )
        XCTAssertEqual(
            kvs.object(forKey: ICloudSyncPreferences.dictionaryEnabledKey) as? Bool,
            true
        )
    }

    func testPullAndMergeAppliesRemoteSettingsToAppGroup() async throws {
        store.setSettingsICloudSyncEnabled(true)
        store.setLocaleId("auto")

        let deviceID = SyncDeviceID.current(defaults: defaults)
        let stamp = Date(timeIntervalSince1970: 900)
        var remote = SyncedAppSettingsV2.seeded(
            from: AppGroupConfiguration.load(fromAvailable: defaults),
            deviceID: deviceB,
            updatedAt: stamp
        )
        remote.localeId = SyncedField(value: "ja", updatedAt: stamp, deviceID: deviceB)
        try settingsSync.push(remote)

        await settingsSync.pullAndMerge(store: store)

        XCTAssertEqual(store.localeId, "ja")
        XCTAssertEqual(store.settingsCloudUpdatedAt?.timeIntervalSince1970 ?? 0, 900, accuracy: 1)
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

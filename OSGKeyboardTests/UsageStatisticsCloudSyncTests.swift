// UsageStatisticsCloudSyncTests.swift
// OSGKeyboardTests
//
// Hermetic tests for cumulative usage statistics iCloud merge.

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class UsageStatisticsCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!
    private var kvs: FakeUbiquitousKeyValueStore!
    private var sync: UsageStatisticsCloudSync!
    private let deviceA = "device-a"
    private let deviceB = "device-b"

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.usage.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(deviceA, forKey: "sync.deviceID.v1")
        store = AppGroupStore(defaults: defaults)
        store.setSettingsICloudSyncEnabled(true)
        kvs = FakeUbiquitousKeyValueStore()
        sync = UsageStatisticsCloudSync(kvs: kvs) { [unowned self] in store }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testGCounterMergeSumsAcrossDevices() {
        let local = SyncedUsageStatisticsV2(devices: [
            deviceA: UsageStatisticsDeviceSlice(
                updatedAt: Date(timeIntervalSince1970: 100),
                dictationDurationSeconds: 30,
                dictationCharacterCount: 120,
                translationCharacterCount: 10
            ),
        ])
        let remote = SyncedUsageStatisticsV2(devices: [
            deviceB: UsageStatisticsDeviceSlice(
                updatedAt: Date(timeIntervalSince1970: 200),
                dictationDurationSeconds: 45,
                dictationCharacterCount: 80,
                translationCharacterCount: 25
            ),
        ])

        let merged = SyncedUsageStatisticsV2.merge(local: local, remote: remote).aggregated

        XCTAssertEqual(merged.dictationDurationSeconds, 75)
        XCTAssertEqual(merged.dictationCharacterCount, 200)
        XCTAssertEqual(merged.translationCharacterCount, 35)
    }

    func testGCounterMergeTakesMaxForSameDevice() {
        let local = SyncedUsageStatisticsV2(devices: [
            deviceA: UsageStatisticsDeviceSlice(
                updatedAt: Date(timeIntervalSince1970: 100),
                dictationDurationSeconds: 30,
                dictationCharacterCount: 120,
                translationCharacterCount: 10
            ),
        ])
        let remote = SyncedUsageStatisticsV2(devices: [
            deviceA: UsageStatisticsDeviceSlice(
                updatedAt: Date(timeIntervalSince1970: 200),
                dictationDurationSeconds: 45,
                dictationCharacterCount: 80,
                translationCharacterCount: 25
            ),
        ])

        let merged = SyncedUsageStatisticsV2.merge(local: local, remote: remote).aggregated

        XCTAssertEqual(merged.dictationDurationSeconds, 45)
        XCTAssertEqual(merged.dictationCharacterCount, 120)
        XCTAssertEqual(merged.translationCharacterCount, 25)
    }

    func testPullAndMergeAppliesRemoteTotals() async throws {
        let remote = SyncedUsageStatisticsV2(devices: [
            deviceB: UsageStatisticsDeviceSlice(
                updatedAt: Date(),
                dictationDurationSeconds: 90,
                dictationCharacterCount: 500,
                translationCharacterCount: 40
            ),
        ])
        try sync.push(remote)

        await sync.pullAndMerge(store: store)

        let loaded = SyncedUsageStatisticsStorage.load(from: defaults).aggregated
        XCTAssertEqual(loaded.dictationDurationSeconds, 90)
        XCTAssertEqual(loaded.dictationCharacterCount, 500)
        XCTAssertEqual(loaded.translationCharacterCount, 40)
    }

    func testPullUnionsIndependentDeviceTotals() async throws {
        SyncedUsageStatisticsStorage.upsertCurrentDeviceSlice(
            UsageStatisticsDeviceSlice(
                updatedAt: Date(),
                dictationDurationSeconds: 10,
                dictationCharacterCount: 300,
                translationCharacterCount: 0
            ),
            defaults: defaults,
            deviceID: deviceA
        )
        let remote = SyncedUsageStatisticsV2(devices: [
            deviceB: UsageStatisticsDeviceSlice(
                updatedAt: Date(),
                dictationDurationSeconds: 20,
                dictationCharacterCount: 150,
                translationCharacterCount: 5
            ),
        ])
        try sync.push(remote)

        await sync.pullAndMerge(store: store)

        let loaded = SyncedUsageStatisticsStorage.load(from: defaults).aggregated
        XCTAssertEqual(loaded.dictationDurationSeconds, 30)
        XCTAssertEqual(loaded.dictationCharacterCount, 450)
        XCTAssertEqual(loaded.translationCharacterCount, 5)
    }
}

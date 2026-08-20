// AnalyticsRepositoryTests.swift
// OSGKeyboardTests
//
// Durable identity, queue policy, retention, and cross-process lease coverage.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class AnalyticsRepositoryTests: XCTestCase {
    func testFirstOpenMarkerAndEventAreCreatedExactlyOnceAcrossRestart() async throws {
        let url = try analyticsTemporaryDatabaseURL()
        let clock = AnalyticsTestWallClock()
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(databaseURL: url),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )

        await repository.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .referral
        )
        await repository.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .socialContent
        )

        let firstSnapshot = await repository.debugSnapshot()
        XCTAssertTrue(firstSnapshot.firstOpenRecorded)
        XCTAssertEqual(firstSnapshot.pendingEvents.map(\.eventType), [.firstOpen])
        let decodedEvents = try await analyticsDecodePendingEvents(repository: repository)
        let event = try XCTUnwrap(decodedEvents.first)
        XCTAssertEqual(event.installationId, analyticsTestUUID(1))
        XCTAssertEqual(event.clientEventId, analyticsTestUUID(2))
        XCTAssertEqual(event.acquisitionChannel, .referral)

        let restarted = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(databaseURL: url),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 100)
        )
        await restarted.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .appStoreOrganic
        )

        let restartedSnapshot = await restarted.debugSnapshot()
        XCTAssertEqual(restartedSnapshot.installationID, analyticsTestUUID(1))
        XCTAssertEqual(restartedSnapshot.pendingEvents.map(\.eventType), [.firstOpen])
    }

    func testSessionWindowTracksThirtyMinutesOfInactivityPerSurface() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )

        await repository.recordSessionIfNeeded(context: analyticsTestContext)
        clock.advance(by: 29 * 60)
        await repository.recordSessionIfNeeded(context: analyticsTestContext)
        clock.advance(by: 29 * 60)
        await repository.recordSessionIfNeeded(context: analyticsTestContext)

        var snapshot = await repository.debugSnapshot()
        XCTAssertEqual(snapshot.pendingEvents.map(\.eventType), [.sessionStarted])

        clock.advance(by: 30 * 60)
        await repository.recordSessionIfNeeded(context: analyticsTestContext)
        snapshot = await repository.debugSnapshot()
        XCTAssertEqual(
            snapshot.pendingEvents.compactMap(\.eventType),
            [.sessionStarted, .sessionStarted]
        )
    }

    func testDisableClearsQueuePersistsAcrossRestartAndReenableRotatesIdentity() async throws {
        let url = try analyticsTemporaryDatabaseURL()
        let clock = AnalyticsTestWallClock()
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(databaseURL: url),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await repository.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .unknown
        )
        let originalID = await repository.debugSnapshot().installationID

        await repository.setEnabled(false)
        var snapshot = await repository.debugSnapshot()
        XCTAssertFalse(snapshot.enabled)
        XCTAssertTrue(snapshot.pendingEvents.isEmpty)

        let restarted = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(databaseURL: url),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 100)
        )
        let remainsDisabled = await restarted.isEnabled()
        XCTAssertFalse(remainsDisabled)
        await restarted.record(
            eventType: .keyboardActivated,
            context: analyticsTestContext
        )
        let disabledSnapshot = await restarted.debugSnapshot()
        XCTAssertTrue(disabledSnapshot.pendingEvents.isEmpty)

        await restarted.setEnabled(true)
        await restarted.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .referral
        )
        await restarted.record(
            eventType: .keyboardActivated,
            context: analyticsTestContext
        )
        snapshot = await restarted.debugSnapshot()
        XCTAssertTrue(snapshot.enabled)
        XCTAssertNotEqual(snapshot.installationID, originalID)
        XCTAssertTrue(snapshot.firstOpenRecorded)
        XCTAssertEqual(snapshot.pendingEvents.map(\.eventType), [.keyboardActivated])
    }

    func testAccountObservationSwitchAndDeletionRotateWithoutRepeatingFirstOpen() async throws {
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: AnalyticsTestWallClock(),
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await repository.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .appStoreOrganic
        )
        let installationBeforeAccount = await repository.debugSnapshot().installationID

        let first = await repository.observeAccount(stableIdentifier: "account-a")
        guard case .firstAccount = first else {
            return XCTFail("Expected firstAccount, got \(first)")
        }
        let installationAfterFirstAccount = await repository.debugSnapshot().installationID
        XCTAssertEqual(installationAfterFirstAccount, installationBeforeAccount)

        let unchanged = await repository.observeAccount(stableIdentifier: "account-a")
        guard case .unchanged = unchanged else {
            return XCTFail("Expected unchanged, got \(unchanged)")
        }

        await repository.record(
            eventType: .keyboardActivated,
            context: analyticsTestContext
        )
        let switched = await repository.observeAccount(stableIdentifier: "account-b")
        guard case .switchedAccount = switched else {
            return XCTFail("Expected switchedAccount, got \(switched)")
        }
        let afterSwitch = await repository.debugSnapshot()
        XCTAssertNotEqual(afterSwitch.installationID, installationBeforeAccount)
        XCTAssertTrue(afterSwitch.pendingEvents.isEmpty)
        XCTAssertTrue(afterSwitch.firstOpenRecorded)

        await repository.record(
            eventType: .purchaseViewed,
            context: analyticsTestContext
        )
        let switchedID = afterSwitch.installationID
        await repository.handleAccountDeletion()
        let afterDeletion = await repository.debugSnapshot()
        XCTAssertNotEqual(afterDeletion.installationID, switchedID)
        XCTAssertTrue(afterDeletion.pendingEvents.isEmpty)
        XCTAssertTrue(afterDeletion.firstOpenRecorded)

        let firstAfterDeletion = await repository.observeAccount(stableIdentifier: "account-b")
        guard case .firstAccount = firstAfterDeletion else {
            return XCTFail("Expected firstAccount after deletion, got \(firstAfterDeletion)")
        }
    }

    func testRetryPreservesCanonicalPayloadAndClientEventID() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await analyticsRecordKeyboardEvents(count: 1, repository: repository)
        let snapshot = await repository.debugSnapshot()
        let rowID = try XCTUnwrap(snapshot.pendingEvents.first?.rowID)
        let storedOriginalPayload = await repository.debugPayloadBytes(rowID: rowID)
        let originalPayload = try XCTUnwrap(storedOriginalPayload)
        let originalEvent = try JSONDecoder().decode(
            AnalyticsEvent.self,
            from: originalPayload
        )
        let upload = AnalyticsUploadConfiguration(
            endpoint: URL(string: "https://analytics.test/events")!
        )
        let leasedFirstBatch = await repository.leaseBatch(
            ownerID: "owner",
            configuration: upload
        )
        let firstLease = try XCTUnwrap(leasedFirstBatch)

        await repository.scheduleRetry(
            events: firstLease.events,
            leaseID: firstLease.leaseID,
            delay: 10
        )
        let storedRetriedPayload = await repository.debugPayloadBytes(rowID: rowID)
        let retriedPayload = try XCTUnwrap(storedRetriedPayload)
        XCTAssertEqual(retriedPayload, originalPayload)
        let retrySnapshot = await repository.debugSnapshot()
        let retryDiagnostic = try XCTUnwrap(retrySnapshot.pendingEvents.first)
        XCTAssertEqual(retryDiagnostic.attemptCount, 1)
        XCTAssertEqual(retryDiagnostic.nextAttemptAt, clock.now().addingTimeInterval(10))

        clock.advance(by: 10)
        let leasedSecondBatch = await repository.leaseBatch(
            ownerID: "owner",
            configuration: upload
        )
        let secondLease = try XCTUnwrap(leasedSecondBatch)
        XCTAssertEqual(secondLease.events.first?.payload, originalPayload)
        let retriedEvent = try JSONDecoder().decode(
            AnalyticsEvent.self,
            from: try XCTUnwrap(secondLease.events.first?.payload)
        )
        XCTAssertEqual(retriedEvent.clientEventId, originalEvent.clientEventId)
    }

    func testConcurrentRepositoriesEnforceGlobalLeaseAndRecoverExpiredEventLease() async throws {
        let url = try analyticsTemporaryDatabaseURL()
        let clock = AnalyticsTestWallClock()
        let firstRepository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(databaseURL: url),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        let secondRepository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(databaseURL: url),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 100)
        )
        await analyticsRecordKeyboardEvents(count: 1, repository: firstRepository)
        let upload = AnalyticsUploadConfiguration(
            endpoint: URL(string: "https://analytics.test/events")!,
            globalLeaseDuration: 60,
            eventLeaseDuration: 60
        )

        async let first = firstRepository.leaseBatch(
            ownerID: "first-owner",
            configuration: upload
        )
        async let second = secondRepository.leaseBatch(
            ownerID: "second-owner",
            configuration: upload
        )
        let simultaneous = await (first, second)
        XCTAssertEqual([simultaneous.0, simultaneous.1].compactMap { $0 }.count, 1)

        clock.advance(by: 61)
        let recovered = await secondRepository.leaseBatch(
            ownerID: "recovery-owner",
            configuration: upload
        )
        XCTAssertEqual(recovered?.events.count, 1)
    }

    func testCrashAfterServerAcceptanceBeforeDeleteReplaysOriginalBytes() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await analyticsRecordKeyboardEvents(count: 1, repository: repository)
        let configuration = AnalyticsUploadConfiguration(
            endpoint: URL(string: "https://analytics.test/events")!,
            globalLeaseDuration: 60,
            eventLeaseDuration: 60
        )
        let crashedLease = await repository.leaseBatch(
            ownerID: "crashed-owner",
            configuration: configuration
        )
        let acceptedButNotDeleted = try XCTUnwrap(crashedLease)

        clock.advance(by: 61)
        let network = AnalyticsQueueNetwork([
            .response(analyticsSuccessResponse(accepted: 0, replayed: 1))
        ])
        let coordinator = AnalyticsUploadCoordinator(
            repository: repository,
            configuration: configuration,
            network: network,
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 500),
            random: AnalyticsTestRandomGenerator()
        )
        await coordinator.uploadAvailableEvents()

        let requests = await network.requests()
        XCTAssertEqual(requests.single?.body, acceptedButNotDeleted.body)
        let completedSnapshot = await repository.debugSnapshot()
        XCTAssertTrue(completedSnapshot.pendingEvents.isEmpty)
    }

    func testBatchHonorsFiftyEventAndDynamicBodyByteLimits() async throws {
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: AnalyticsTestWallClock(),
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await analyticsRecordKeyboardEvents(count: 55, repository: repository)
        let defaultUpload = AnalyticsUploadConfiguration(
            endpoint: URL(string: "https://analytics.test/events")!,
            maximumBatchCount: 100,
            maximumBodyBytes: 100_000
        )
        let countLease = await repository.leaseBatch(
            ownerID: "count",
            configuration: defaultUpload
        )
        let countLimited = try XCTUnwrap(countLease)
        XCTAssertEqual(countLimited.events.count, 50)
        XCTAssertLessThanOrEqual(countLimited.body.count, 60 * 1_024)

        await repository.releaseEvents(
            countLimited.events,
            leaseID: countLimited.leaseID
        )
        await repository.releaseGlobalLease(ownerID: "count")

        let byteUpload = AnalyticsUploadConfiguration(
            endpoint: URL(string: "https://analytics.test/events")!,
            maximumBatchCount: 50,
            maximumBodyBytes: 1_024
        )
        let byteLease = await repository.leaseBatch(
            ownerID: "bytes",
            configuration: byteUpload
        )
        let byteLimited = try XCTUnwrap(byteLease)
        XCTAssertFalse(byteLimited.events.isEmpty)
        XCTAssertLessThan(byteLimited.events.count, 50)
        XCTAssertLessThanOrEqual(byteLimited.body.count, 1_024)
        let snapshot = await repository.debugSnapshot()
        let selectedIDs = Set(byteLimited.events.map(\.rowID))
        let nextDiagnostic = try XCTUnwrap(
            snapshot.pendingEvents.first { !selectedIDs.contains($0.rowID) }
        )
        let storedNextPayload = await repository.debugPayloadBytes(
            rowID: nextDiagnostic.rowID
        )
        let nextPayload = try XCTUnwrap(storedNextPayload)
        XCTAssertGreaterThan(byteLimited.body.count + 1 + nextPayload.count, 1_024)
    }

    func testRetentionExpiresAfterThirtyFourDaysAndToleratesClockRollback() async throws {
        let retention = 34 * 24 * 60 * 60.0
        let clock = AnalyticsTestWallClock()
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL(),
                eventRetention: retention
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await repository.record(
            eventType: .keyboardActivated,
            context: analyticsTestContext
        )

        clock.advance(by: retention)
        await repository.record(
            eventType: .purchaseViewed,
            context: analyticsTestContext
        )
        let boundarySnapshot = await repository.debugSnapshot()
        XCTAssertEqual(boundarySnapshot.pendingEvents.count, 2)

        clock.advance(by: 0.001)
        await repository.record(
            eventType: .purchaseStarted,
            context: analyticsTestContext
        )
        var events = try await analyticsDecodePendingEvents(repository: repository)
        XCTAssertEqual(Set(events.map(\.eventType)), [.purchaseViewed, .purchaseStarted])

        let future = clock.now().addingTimeInterval(24 * 60 * 60)
        clock.set(future)
        await repository.record(
            eventType: .referralShared,
            context: analyticsTestContext
        )
        clock.set(future.addingTimeInterval(-7 * 24 * 60 * 60))
        let upload = AnalyticsUploadConfiguration(
            endpoint: URL(string: "https://analytics.test/events")!
        )
        let batch = await repository.leaseBatch(ownerID: "rollback", configuration: upload)
        events = try batch?.events.map {
            try JSONDecoder().decode(AnalyticsEvent.self, from: $0.payload)
        } ?? []
        XCTAssertTrue(events.contains(where: { $0.eventType == .referralShared }))
    }

    func testCapacityEvictsSessionAndKeyboardBeforeHighValueEvents() async throws {
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL(),
                maximumEventCount: 2
            ),
            clock: AnalyticsTestWallClock(),
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        await repository.prepare(
            using: analyticsTestContext,
            firstOpenAcquisitionChannel: .unknown
        )
        await repository.recordSessionIfNeeded(context: analyticsTestContext)
        await repository.record(
            eventType: .keyboardActivated,
            context: analyticsTestContext
        )
        var eventTypes = await repository.debugSnapshot().pendingEvents.compactMap(\.eventType)
        XCTAssertEqual(Set(eventTypes), [.firstOpen, .keyboardActivated])

        await repository.record(
            eventType: .aiFeatureSucceeded,
            context: analyticsTestContext,
            dimensions: AnalyticsEventDimensions(
                feature: .polish,
                executionMode: .managed,
                durationBucket: .oneToThreeSeconds
            )
        )
        eventTypes = await repository.debugSnapshot().pendingEvents.compactMap(\.eventType)
        XCTAssertEqual(Set(eventTypes), [.firstOpen, .aiFeatureSucceeded])
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}

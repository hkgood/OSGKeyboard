// KeyboardUsageRepositoryTests.swift
// OSGKeyboardTests
//
// Session migration, UTC splitting, immutable IDs and cross-process SQLite safety.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class KeyboardUsageRepositoryTests: XCTestCase {
    func testFourSessionClassesPartitionInputSessionCount() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        let date = clock.now()

        await keyboardUsageRecord(
            .init(chinese: 2, other: 1),
            sessionID: analyticsTestUUID(1),
            occurredAt: date,
            repository: repository
        )
        await keyboardUsageRecord(
            .init(english: 2),
            sessionID: analyticsTestUUID(2),
            occurredAt: date,
            repository: repository
        )
        await keyboardUsageRecord(
            .init(chinese: 1, english: 1),
            sessionID: analyticsTestUUID(3),
            occurredAt: date,
            repository: repository
        )
        await keyboardUsageRecord(
            .init(other: 3),
            sessionID: analyticsTestUUID(4),
            occurredAt: date,
            repository: repository
        )

        let snapshot = await repository.debugSnapshot()
        let daily = try XCTUnwrap(snapshot.daily.first)
        XCTAssertEqual(daily.inputSessionCount, 4)
        XCTAssertEqual(daily.chineseOnlySessionCount, 1)
        XCTAssertEqual(daily.englishOnlySessionCount, 1)
        XCTAssertEqual(daily.mixedLanguageSessionCount, 1)
        XCTAssertEqual(daily.otherOnlySessionCount, 1)
        XCTAssertEqual(
            daily.chineseOnlySessionCount
                + daily.englishOnlySessionCount
                + daily.mixedLanguageSessionCount
                + daily.otherOnlySessionCount,
            daily.inputSessionCount
        )
    }

    func testLanguageChangeMigratesSessionWithoutDoubleCounting() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        let sessionID = analyticsTestUUID(10)

        await keyboardUsageRecord(
            .init(chinese: 2),
            sessionID: sessionID,
            occurredAt: clock.now(),
            repository: repository
        )
        await keyboardUsageRecord(
            .init(english: 3),
            sessionID: sessionID,
            occurredAt: clock.now(),
            repository: repository
        )

        let snapshot = await repository.debugSnapshot()
        let daily = try XCTUnwrap(snapshot.daily.first)
        XCTAssertEqual(daily.chineseCharacterCount, 2)
        XCTAssertEqual(daily.englishCharacterCount, 3)
        XCTAssertEqual(daily.inputSessionCount, 1)
        XCTAssertEqual(daily.chineseOnlySessionCount, 0)
        XCTAssertEqual(daily.englishOnlySessionCount, 0)
        XCTAssertEqual(daily.mixedLanguageSessionCount, 1)
        XCTAssertEqual(daily.otherOnlySessionCount, 0)
    }

    func testSamePresentationSplitsAcrossUTCDaysAndTodayIsNotLeased() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        let sessionID = analyticsTestUUID(20)

        await keyboardUsageRecord(
            .init(chinese: 1),
            sessionID: sessionID,
            occurredAt: keyboardUsageDate(2026, 8, 20, hour: 23),
            repository: repository
        )
        await keyboardUsageRecord(
            .init(english: 1),
            sessionID: sessionID,
            occurredAt: keyboardUsageDate(2026, 8, 21, hour: 0),
            repository: repository
        )

        let snapshot = await repository.debugSnapshot()
        XCTAssertEqual(snapshot.pending.map(\.summaryDate), ["2026-08-20"])
        let today = try XCTUnwrap(snapshot.daily.first)
        XCTAssertEqual(today.summaryDate, "2026-08-21")
        XCTAssertEqual(today.inputSessionCount, 1)
        XCTAssertEqual(today.englishOnlySessionCount, 1)

        let batch = await repository.leaseBatch(
            ownerID: "test",
            configuration: uploadConfiguration()
        )
        let leased = try XCTUnwrap(batch)
        XCTAssertEqual(leased.summaries.count, 1)
        let summary = try JSONDecoder().decode(
            KeyboardUsageSummary.self,
            from: try XCTUnwrap(leased.summaries.first?.payload)
        )
        XCTAssertEqual(summary.summaryDate, "2026-08-20")
        XCTAssertEqual(summary.inputSessionCount, 1)
        XCTAssertEqual(summary.chineseOnlySessionCount, 1)
    }

    func testConcurrentRepositoriesDoNotLoseCountsOrDuplicateFinalization() async throws {
        let url = try keyboardUsageTemporaryDatabaseURL()
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 20))
        let first = makeRepository(url: url, clock: clock, uuidStart: 1)
        let second = makeRepository(url: url, clock: clock, uuidStart: 1_000)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let repository = index.isMultiple(of: 2) ? first : second
                    await keyboardUsageRecord(
                        .init(chinese: 1, english: 1, other: 1),
                        sessionID: analyticsTestUUID(index + 1),
                        occurredAt: clock.now(),
                        repository: repository
                    )
                }
            }
        }
        let concurrentSnapshot = await first.debugSnapshot()
        let daily = try XCTUnwrap(concurrentSnapshot.daily.first)
        XCTAssertEqual(daily.chineseCharacterCount, 100)
        XCTAssertEqual(daily.englishCharacterCount, 100)
        XCTAssertEqual(daily.otherCharacterCount, 100)
        XCTAssertEqual(daily.inputSessionCount, 100)
        XCTAssertEqual(daily.mixedLanguageSessionCount, 100)

        clock.advance(by: 24 * 60 * 60)
        async let firstFinalize: Void = first.finalizeCompletedDays()
        async let secondFinalize: Void = second.finalizeCompletedDays()
        _ = await (firstFinalize, secondFinalize)

        let finalized = await first.debugSnapshot()
        XCTAssertTrue(finalized.daily.isEmpty)
        XCTAssertEqual(finalized.pending.count, 1)
        XCTAssertEqual(finalized.pending.first?.summaryDate, "2026-08-20")
    }

    func testRetryKeepsStableClientSummaryID() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 20))
        let repository = makeRepository(clock: clock)
        await keyboardUsageRecord(
            .init(other: 1),
            sessionID: analyticsTestUUID(30),
            occurredAt: clock.now(),
            repository: repository
        )
        clock.advance(by: 24 * 60 * 60)
        await repository.finalizeCompletedDays()
        let finalizedSnapshot = await repository.debugSnapshot()
        let originalID = try XCTUnwrap(
            finalizedSnapshot.pending.first?.clientSummaryID
        )

        let firstLeasedBatch = await repository.leaseBatch(
            ownerID: "retry",
            configuration: uploadConfiguration()
        )
        let firstLease = try XCTUnwrap(firstLeasedBatch)
        await repository.scheduleRetry(
            summaries: firstLease.summaries,
            leaseID: firstLease.leaseID,
            delay: 10
        )
        clock.advance(by: 10)
        let secondLeasedBatch = await repository.leaseBatch(
            ownerID: "retry",
            configuration: uploadConfiguration()
        )
        let secondLease = try XCTUnwrap(secondLeasedBatch)
        let retriedSummary = try JSONDecoder().decode(
            KeyboardUsageSummary.self,
            from: try XCTUnwrap(secondLease.summaries.first?.payload)
        )
        XCTAssertEqual(retriedSummary.clientSummaryId, originalID)
    }

    func testEachLeasedBatchContainsOnlyOneInstallation() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        for installationValue in [900, 901] {
            await keyboardUsageRecord(
                .init(chinese: 1),
                sessionID: analyticsTestUUID(installationValue),
                occurredAt: keyboardUsageDate(2026, 8, 20),
                repository: repository,
                installationID: analyticsTestUUID(installationValue)
            )
        }

        let firstBatch = await repository.leaseBatch(
            ownerID: "first",
            configuration: uploadConfiguration()
        )
        let first = try XCTUnwrap(firstBatch)
        XCTAssertEqual(first.summaries.count, 1)
        XCTAssertTrue(
            [analyticsTestUUID(900), analyticsTestUUID(901)]
                .contains(first.installationID)
        )
        let completed = await repository.complete(
            rowIDs: first.summaries.map(\.rowID),
            leaseID: first.leaseID
        )
        XCTAssertTrue(completed)
        await repository.releaseGlobalLease(ownerID: "first")

        let secondBatch = await repository.leaseBatch(
            ownerID: "second",
            configuration: uploadConfiguration()
        )
        let second = try XCTUnwrap(secondBatch)
        XCTAssertNotEqual(second.installationID, first.installationID)
        XCTAssertEqual(second.summaries.count, 1)
    }

    func testClearAllInvalidatesAnAlreadyLeasedBatch() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await keyboardUsageRecord(
            .init(english: 1),
            sessionID: analyticsTestUUID(50),
            occurredAt: keyboardUsageDate(2026, 8, 20),
            repository: repository
        )
        let leasedBatch = await repository.leaseBatch(
            ownerID: "old-account",
            configuration: uploadConfiguration()
        )
        let batch = try XCTUnwrap(leasedBatch)

        await repository.clearAll()

        let renewed = await repository.renewLease(
            ownerID: "old-account",
            leaseID: batch.leaseID,
            configuration: uploadConfiguration()
        )
        XCTAssertFalse(renewed)
        let snapshot = await repository.debugSnapshot()
        XCTAssertTrue(snapshot.daily.isEmpty)
        XCTAssertTrue(snapshot.pending.isEmpty)
        XCTAssertTrue(snapshot.quarantined.isEmpty)
    }

    func testDatabaseSchemaContainsNoRawInputOrHostContextColumns() async throws {
        let url = try keyboardUsageTemporaryDatabaseURL()
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(url: url, clock: clock)
        await keyboardUsageRecord(
            .init(chinese: 1),
            sessionID: analyticsTestUUID(40),
            occurredAt: clock.now(),
            repository: repository
        )

        let database = try SQLiteDatabase(
            url: url,
            busyTimeoutMilliseconds: 2_000
        )
        let tables = [
            "usage_daily_counters",
            "usage_session_fragments",
            "usage_outbox",
            "usage_quarantine"
        ]
        let forbidden = Set([
            "text",
            "raw_text",
            "pinyin",
            "candidate",
            "context_before",
            "context_after",
            "host_app",
            "bundle_id",
            "field_type",
            "transcript",
            "prompt",
            "clipboard"
        ])
        for table in tables {
            let columns = try database.query("PRAGMA table_info(\(table))")
                .compactMap { $0.text(at: 1) }
            XCTAssertTrue(forbidden.isDisjoint(with: columns), table)
            if table == "usage_quarantine" {
                XCTAssertTrue(
                    Set([
                        "installation_id",
                        "client_summary_id",
                        "payload"
                    ]).isDisjoint(with: columns)
                )
            }
        }
    }

    func testSuspendedDatabaseDropsCountsUntilExplicitResume() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await keyboardUsageRecord(
            .init(chinese: 1),
            sessionID: analyticsTestUUID(60),
            occurredAt: clock.now(),
            repository: repository
        )

        await repository.suspendDatabaseAccess()
        await keyboardUsageRecord(
            .init(english: 1),
            sessionID: analyticsTestUUID(61),
            occurredAt: clock.now(),
            repository: repository
        )
        let suspendedSnapshot = await repository.debugSnapshot()
        XCTAssertFalse(suspendedSnapshot.isAvailable)

        await repository.resumeDatabaseAccess()
        await keyboardUsageRecord(
            .init(other: 1),
            sessionID: analyticsTestUUID(62),
            occurredAt: clock.now(),
            repository: repository
        )
        let resumedSnapshot = await repository.debugSnapshot()
        let daily = try XCTUnwrap(resumedSnapshot.daily.first)
        XCTAssertEqual(daily.chineseCharacterCount, 1)
        XCTAssertEqual(daily.englishCharacterCount, 0)
        XCTAssertEqual(daily.otherCharacterCount, 1)
    }

    private func makeRepository(
        url: URL? = nil,
        clock: AnalyticsTestWallClock,
        uuidStart: Int = 100
    ) -> KeyboardUsageRepository {
        KeyboardUsageRepository(
            configuration: KeyboardUsageRepositoryConfiguration(
                databaseURL: url ?? (try! keyboardUsageTemporaryDatabaseURL())
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: uuidStart)
        )
    }

    private func uploadConfiguration() -> KeyboardUsageUploadConfiguration {
        KeyboardUsageUploadConfiguration(
            endpoint: URL(
                string: "https://analytics.test/v1/analytics/keyboard-usage"
            )!
        )
    }
}

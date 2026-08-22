// AnalyticsAIOperationTests.swift
// OSGKeyboardTests
//
// Ordering, duration, and exactly-once terminal semantics for AI operations.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class AnalyticsAIOperationTests: XCTestCase {
    func testStartedIsPersistedBeforeTerminalWithDurationBucket() async throws {
        let monotonicClock = AnalyticsTestMonotonicClock(1_000)
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: AnalyticsTestWallClock(),
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        let client = LiveAnalyticsClient(
            repository: repository,
            context: analyticsTestContext,
            monotonicClock: monotonicClock
        )

        let operation = client.startAIFeature(.polish, executionMode: .managed)
        monotonicClock.set(4_000_001_000)
        operation.succeed()

        _ = await analyticsWaitForPendingEventCount(2, repository: repository)
        let events = try await analyticsDecodePendingEvents(repository: repository)
        XCTAssertEqual(events.map(\.eventType), [.aiFeatureStarted, .aiFeatureSucceeded])
        XCTAssertEqual(events.map(\.feature), [.polish, .polish])
        XCTAssertEqual(events.map(\.executionMode), [.managed, .managed])
        XCTAssertNil(events[0].durationBucket)
        XCTAssertEqual(events[1].durationBucket, .threeToTenSeconds)
        XCTAssertNil(events[1].failureCategory)
    }

    func testConcurrentTerminalCallsPersistExactlyOneTerminalEvent() async throws {
        let monotonicClock = AnalyticsTestMonotonicClock(10)
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: AnalyticsTestWallClock(),
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        let client = LiveAnalyticsClient(
            repository: repository,
            context: analyticsTestContext,
            monotonicClock: monotonicClock
        )
        let operation = client.startAIFeature(.aiAssistant, executionMode: .local)
        monotonicClock.set(2_000_000_010)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<60 {
                group.addTask {
                    switch index % 3 {
                    case 0:
                        operation.succeed()
                    case 1:
                        operation.fail(category: .provider)
                    default:
                        operation.cancel()
                    }
                }
            }
        }

        _ = await analyticsWaitForPendingEventCount(2, repository: repository)
        let events = try await analyticsDecodePendingEvents(repository: repository)
        XCTAssertEqual(events.first?.eventType, .aiFeatureStarted)
        XCTAssertEqual(events.count, 2)
        let terminalEvents = events.filter {
            [.aiFeatureSucceeded, .aiFeatureFailed].contains($0.eventType)
        }
        XCTAssertEqual(terminalEvents.count, 1)
        XCTAssertEqual(terminalEvents.first?.feature, .aiAssistant)
        XCTAssertEqual(terminalEvents.first?.executionMode, .local)
        XCTAssertEqual(terminalEvents.first?.durationBucket, .oneToThreeSeconds)
    }

    func testCancelPersistsFailedWithCancelledCategory() async throws {
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: AnalyticsTestWallClock(),
            uuidGenerator: AnalyticsTestUUIDGenerator()
        )
        let client = LiveAnalyticsClient(
            repository: repository,
            context: analyticsTestContext,
            monotonicClock: AnalyticsTestMonotonicClock()
        )

        client.startAIFeature(
            .transcription,
            executionMode: .managed
        ).cancel()

        _ = await analyticsWaitForPendingEventCount(2, repository: repository)
        let events = try await analyticsDecodePendingEvents(repository: repository)
        XCTAssertEqual(events.map(\.eventType), [.aiFeatureStarted, .aiFeatureFailed])
        XCTAssertEqual(events.last?.failureCategory, .cancelled)
    }
}

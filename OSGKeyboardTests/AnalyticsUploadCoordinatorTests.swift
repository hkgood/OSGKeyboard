// AnalyticsUploadCoordinatorTests.swift
// OSGKeyboardTests
//
// HTTP outcome, authentication, retry, and poison-event isolation coverage.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class AnalyticsUploadCoordinatorTests: XCTestCase {
    private let endpoint = URL(string: "https://analytics.test/v1/events")!

    func testExactAcceptedAndReplayedCountDeletesUsingOriginalPayloadBytes() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = try await makeRepository(clock: clock, eventCount: 2)
        let payloads = try await analyticsPendingPayloads(repository: repository)
        let expectedBody = analyticsRequestBody(payloads: payloads)
        let network = AnalyticsQueueNetwork([
            .response(analyticsSuccessResponse(accepted: 1, replayed: 1))
        ])
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock
        )

        await coordinator.uploadAvailableEvents()

        let snapshot = await repository.debugSnapshot()
        XCTAssertTrue(snapshot.pendingEvents.isEmpty)
        let requests = await network.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.body, expectedBody)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertNil(request.headers["Authorization"])
        let topLevel = try XCTUnwrap(
            JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        )
        XCTAssertEqual(Set(topLevel.keys), ["installationId", "events"])
        XCTAssertEqual(topLevel["installationId"] as? String, analyticsTestUUID(1).uuidString.lowercased())
        let eventObjects = try XCTUnwrap(topLevel["events"] as? [[String: Any]])
        XCTAssertEqual(eventObjects.count, 2)
        XCTAssertTrue(eventObjects.allSatisfy { !$0.keys.contains("installationId") })
    }

    func testCountMismatchRetriesWithoutMutatingPayloadOrEventID() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = try await makeRepository(clock: clock, eventCount: 2)
        let originalPayloads = try await analyticsPendingPayloads(repository: repository)
        let originalIDs = try originalPayloads.map {
            try JSONDecoder().decode(AnalyticsEvent.self, from: $0).clientEventId
        }
        let network = AnalyticsQueueNetwork([
            .response(analyticsSuccessResponse(accepted: 1, replayed: 0))
        ])
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock,
            random: AnalyticsTestRandomGenerator(.upperBound)
        )

        await coordinator.uploadAvailableEvents()

        let snapshot = await repository.debugSnapshot()
        XCTAssertEqual(snapshot.pendingEvents.map(\.attemptCount), [1, 1])
        XCTAssertEqual(
            snapshot.pendingEvents.map(\.nextAttemptAt),
            [clock.now().addingTimeInterval(1), clock.now().addingTimeInterval(1)]
        )
        let retriedPayloads = try await analyticsPendingPayloads(repository: repository)
        XCTAssertEqual(retriedPayloads, originalPayloads)
        let retriedIDs = try retriedPayloads.map {
            try JSONDecoder().decode(AnalyticsEvent.self, from: $0).clientEventId
        }
        XCTAssertEqual(retriedIDs, originalIDs)
    }

    func testNetwork408429And5xxScheduleBoundedBackoff() async throws {
        let cases: [(AnalyticsQueueNetwork.Outcome, TimeInterval)] = [
            (.urlError(.notConnectedToInternet), 1),
            (.response(analyticsHTTPResponse(statusCode: 408)), 1),
            (
                .response(
                    analyticsHTTPResponse(
                        statusCode: 429,
                        headers: ["rEtRy-AfTeR": "120"]
                    )
                ),
                120
            ),
            (.response(analyticsHTTPResponse(statusCode: 503)), 1)
        ]

        for (index, testCase) in cases.enumerated() {
            let clock = AnalyticsTestWallClock()
            let repository = try await makeRepository(
                clock: clock,
                eventCount: 1,
                uuidStart: 100 * (index + 1)
            )
            let originalPayloads = try await analyticsPendingPayloads(
                repository: repository
            )
            let originalPayload = try XCTUnwrap(originalPayloads.first)
            let network = AnalyticsQueueNetwork([testCase.0])
            let coordinator = makeCoordinator(
                repository: repository,
                network: network,
                clock: clock,
                random: AnalyticsTestRandomGenerator(.upperBound)
            )

            await coordinator.uploadAvailableEvents()

            let snapshot = await repository.debugSnapshot()
            let diagnostic = try XCTUnwrap(snapshot.pendingEvents.first)
            XCTAssertEqual(diagnostic.attemptCount, 1, "case \(index)")
            XCTAssertEqual(
                diagnostic.nextAttemptAt,
                clock.now().addingTimeInterval(testCase.1),
                "case \(index)"
            )
            let storedPayload = await repository.debugPayloadBytes(rowID: diagnostic.rowID)
            XCTAssertEqual(storedPayload, originalPayload, "case \(index)")
        }
    }

    func testUnauthorizedRefreshesOnceAndRetriesWithNewAuthorization() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = try await makeRepository(clock: clock, eventCount: 1)
        let network = AnalyticsQueueNetwork([
            .response(analyticsHTTPResponse(statusCode: 401)),
            .response(analyticsSuccessResponse(accepted: 1))
        ])
        let bearer = AnalyticsTestBearerProvider(
            initialToken: "old-token",
            refreshedToken: "new-token"
        )
        let coordinator = AnalyticsUploadCoordinator(
            repository: repository,
            configuration: uploadConfiguration(),
            network: network,
            bearerProvider: bearer,
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 5_000),
            random: AnalyticsTestRandomGenerator()
        )

        await coordinator.uploadAvailableEvents()

        let requests = await network.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer old-token")
        XCTAssertEqual(requests[1].headers["Authorization"], "Bearer new-token")
        XCTAssertEqual(requests[0].body, requests[1].body)
        let refreshInputs = await bearer.recordedRefreshInputs()
        XCTAssertEqual(refreshInputs.count, 1)
        XCTAssertEqual(refreshInputs[0], "old-token")
        let snapshot = await repository.debugSnapshot()
        XCTAssertTrue(snapshot.pendingEvents.isEmpty)
    }

    func testSecondUnauthorizedDoesNotRefreshAgainAndSchedulesLongRetry() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = try await makeRepository(clock: clock, eventCount: 1)
        let network = AnalyticsQueueNetwork([
            .response(analyticsHTTPResponse(statusCode: 401)),
            .response(analyticsHTTPResponse(statusCode: 401))
        ])
        let bearer = AnalyticsTestBearerProvider(
            initialToken: "old-token",
            refreshedToken: "new-token"
        )
        let configuration = uploadConfiguration(maximumBackoff: 600)
        let coordinator = AnalyticsUploadCoordinator(
            repository: repository,
            configuration: configuration,
            network: network,
            bearerProvider: bearer,
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 5_000),
            random: AnalyticsTestRandomGenerator(.upperBound)
        )

        await coordinator.uploadAvailableEvents()

        let refreshInputs = await bearer.recordedRefreshInputs()
        XCTAssertEqual(refreshInputs.count, 1)
        let snapshot = await repository.debugSnapshot()
        XCTAssertEqual(snapshot.pendingEvents.first?.attemptCount, 1)
        XCTAssertEqual(
            snapshot.pendingEvents.first?.nextAttemptAt,
            clock.now().addingTimeInterval(600)
        )
    }

    func testValidationStatusesRecursivelyIsolateOnlyPoisonEvent() async throws {
        for statusCode in [400, 409, 422] {
            let clock = AnalyticsTestWallClock()
            let repository = try await makeRepository(
                clock: clock,
                eventCount: 4,
                uuidStart: statusCode
            )
            let events = try await analyticsDecodePendingEvents(repository: repository)
            let poisonID = try XCTUnwrap(events.dropFirst().first?.clientEventId)
            let network = AnalyticsPoisonNetwork(
                statusCode: statusCode,
                poisonID: poisonID
            )
            let coordinator = makeCoordinator(
                repository: repository,
                network: network,
                clock: clock
            )

            await coordinator.uploadAvailableEvents()

            let snapshot = await repository.debugSnapshot()
            XCTAssertTrue(snapshot.pendingEvents.isEmpty, "HTTP \(statusCode)")
            XCTAssertEqual(snapshot.quarantinedEvents.count, 1, "HTTP \(statusCode)")
            XCTAssertEqual(
                snapshot.quarantinedEvents.first?.reason,
                "http\(statusCode)"
            )
            let quarantinedRowID = try XCTUnwrap(
                snapshot.quarantinedEvents.first?.rowID
            )
            let quarantinedPayload = await repository.debugPayloadBytes(
                rowID: quarantinedRowID,
                quarantined: true
            )
            let quarantinedEvent = try JSONDecoder().decode(
                AnalyticsEvent.self,
                from: try XCTUnwrap(quarantinedPayload)
            )
            XCTAssertEqual(quarantinedEvent.clientEventId, poisonID)
            let requests = await network.requests()
            XCTAssertGreaterThan(requests.count, 1)
        }
    }

    func testOtherPermanent4xxQuarantinesWholeBatchWithoutRetry() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = try await makeRepository(clock: clock, eventCount: 3)
        let network = AnalyticsQueueNetwork([
            .response(analyticsHTTPResponse(statusCode: 403))
        ])
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock
        )

        await coordinator.uploadAvailableEvents()

        let snapshot = await repository.debugSnapshot()
        XCTAssertTrue(snapshot.pendingEvents.isEmpty)
        XCTAssertEqual(snapshot.quarantinedEvents.count, 3)
        XCTAssertEqual(Set(snapshot.quarantinedEvents.map(\.reason)), ["http403"])
        let requests = await network.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testCancellationReleasesLeasesWithoutSchedulingRetry() async throws {
        let clock = AnalyticsTestWallClock()
        let repository = try await makeRepository(clock: clock, eventCount: 1)
        let network = CancellableAnalyticsNetwork()
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock
        )
        let upload = Task {
            await coordinator.uploadAvailableEvents()
        }
        for _ in 0..<100 {
            if await network.didStart() {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let didStart = await network.didStart()
        XCTAssertTrue(didStart)

        upload.cancel()
        await upload.value

        let snapshot = await repository.debugSnapshot()
        XCTAssertEqual(snapshot.pendingEvents.first?.attemptCount, 0)
        let recovered = await repository.leaseBatch(
            ownerID: "after-cancellation",
            configuration: uploadConfiguration()
        )
        XCTAssertEqual(recovered?.events.count, 1)
    }

    private func makeRepository(
        clock: AnalyticsTestWallClock,
        eventCount: Int,
        uuidStart: Int = 1
    ) async throws -> AnalyticsRepository {
        let repository = AnalyticsRepository(
            configuration: AnalyticsRepositoryConfiguration(
                databaseURL: try analyticsTemporaryDatabaseURL()
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: uuidStart)
        )
        await analyticsRecordKeyboardEvents(
            count: eventCount,
            repository: repository
        )
        return repository
    }

    private func uploadConfiguration(
        maximumBackoff: TimeInterval = 600
    ) -> AnalyticsUploadConfiguration {
        AnalyticsUploadConfiguration(
            endpoint: endpoint,
            maximumBackoff: maximumBackoff
        )
    }

    private func makeCoordinator(
        repository: AnalyticsRepository,
        network: some AnalyticsNetworking,
        clock: AnalyticsTestWallClock,
        random: AnalyticsTestRandomGenerator = AnalyticsTestRandomGenerator()
    ) -> AnalyticsUploadCoordinator {
        AnalyticsUploadCoordinator(
            repository: repository,
            configuration: uploadConfiguration(),
            network: network,
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 5_000),
            random: random
        )
    }
}

private actor CancellableAnalyticsNetwork: AnalyticsNetworking {
    private var started = false

    func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse {
        _ = request
        started = true
        try await Task.sleep(for: .seconds(30))
        return analyticsSuccessResponse(accepted: 1)
    }

    func didStart() -> Bool {
        started
    }
}

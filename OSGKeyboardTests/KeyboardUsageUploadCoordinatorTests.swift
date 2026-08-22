// KeyboardUsageUploadCoordinatorTests.swift
// OSGKeyboardTests
//
// Aggregate endpoint authentication, acknowledgement and retry policy coverage.

import Foundation
@testable import OSGKeyboard
@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

final class KeyboardUsageUploadCoordinatorTests: XCTestCase {
    private let endpoint = URL(
        string: "https://analytics.test/v1/analytics/keyboard-usage"
    )!

    func testAcceptedAndReplayedDeleteOnlyAfterExactAcknowledgement() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await seedSummary(
            date: keyboardUsageDate(2026, 8, 19),
            session: 1,
            repository: repository
        )
        await seedSummary(
            date: keyboardUsageDate(2026, 8, 20),
            session: 2,
            repository: repository
        )
        let network = AnalyticsQueueNetwork([
            .response(keyboardUsageSuccessResponse(accepted: 1, replayed: 1))
        ])
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock
        )

        await coordinator.uploadAvailableSummaries()

        let snapshot = await repository.debugSnapshot()
        XCTAssertTrue(snapshot.pending.isEmpty)
        let requests = await network.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertNil(request.headers["Authorization"])
        let upload = try JSONDecoder().decode(
            KeyboardUsageUploadRequest.self,
            from: request.body
        )
        XCTAssertEqual(upload.installationId, analyticsTestUUID(900))
        XCTAssertEqual(upload.summaries.count, 2)
        XCTAssertEqual(
            Set(upload.summaries.map(\.summaryDate)),
            ["2026-08-19", "2026-08-20"]
        )
    }

    func testCurrentUTCDayIsNeverUploaded() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await keyboardUsageRecord(
            .init(chinese: 1),
            sessionID: analyticsTestUUID(3),
            occurredAt: clock.now(),
            repository: repository
        )
        let network = AnalyticsQueueNetwork([])
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock
        )

        await coordinator.uploadAvailableSummaries()

        let requests = await network.requests()
        XCTAssertTrue(requests.isEmpty)
        let snapshot = await repository.debugSnapshot()
        XCTAssertEqual(snapshot.daily.first?.summaryDate, "2026-08-21")
        XCTAssertTrue(snapshot.pending.isEmpty)
    }

    func testUnauthorizedRefreshesOnceAndRetriesSameSummary() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await seedSummary(
            date: keyboardUsageDate(2026, 8, 20),
            session: 4,
            repository: repository
        )
        let originalSnapshot = await repository.debugSnapshot()
        let originalID = try XCTUnwrap(
            originalSnapshot.pending.first?.clientSummaryID
        )
        let network = AnalyticsQueueNetwork([
            .response(analyticsHTTPResponse(statusCode: 401)),
            .response(keyboardUsageSuccessResponse(accepted: 1))
        ])
        let bearer = AnalyticsTestBearerProvider(
            initialToken: "old-token",
            refreshedToken: "new-token"
        )
        let coordinator = KeyboardUsageUploadCoordinator(
            repository: repository,
            configuration: uploadConfiguration(),
            network: network,
            bearerProvider: bearer,
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 5_000),
            random: AnalyticsTestRandomGenerator()
        )

        await coordinator.uploadAvailableSummaries()

        let requests = await network.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer old-token")
        XCTAssertEqual(requests[1].headers["Authorization"], "Bearer new-token")
        XCTAssertEqual(requests[0].body, requests[1].body)
        let replayed = try JSONDecoder().decode(
            KeyboardUsageUploadRequest.self,
            from: requests[1].body
        )
        XCTAssertEqual(replayed.summaries.first?.clientSummaryId, originalID)
        let refreshInputs = await bearer.recordedRefreshInputs()
        XCTAssertEqual(refreshInputs, ["old-token"])
    }

    func testAnonymousUploadOmitsAuthorizationWhenNoSessionExists() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await seedSummary(
            date: keyboardUsageDate(2026, 8, 20),
            session: 5,
            repository: repository
        )
        let network = AnalyticsQueueNetwork([
            .response(keyboardUsageSuccessResponse(accepted: 1))
        ])
        let bearer = AnalyticsTestBearerProvider(
            initialToken: nil,
            refreshedToken: nil
        )
        let coordinator = KeyboardUsageUploadCoordinator(
            repository: repository,
            configuration: uploadConfiguration(),
            network: network,
            bearerProvider: bearer,
            clock: clock
        )

        await coordinator.uploadAvailableSummaries()

        let requests = await network.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.headers["Authorization"])
    }

    func testKnownExpiredAccountSessionFallsBackToAnonymousToken() async throws {
        let store = InMemoryAccountSecurityStore(
            session: makeAccountSession(
                accessExpiry: 900,
                refreshExpiry: 950
            )
        )
        let transport = QueueAccountTransport([])
        let client = AccountAPIClient(
            baseURL: URL(string: "https://account.test")!,
            transport: transport,
            sessionVault: store,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let provider = AccountAnalyticsBearerProvider(apiClient: client)

        let token = try await provider.bearerToken()

        XCTAssertNil(token)
        let storedSession = await store.session
        let requests = await transport.requests
        XCTAssertNil(storedSession)
        XCTAssertTrue(requests.isEmpty)
    }

    func testValidationStatusesQuarantineWithoutInfiniteRetry() async throws {
        for statusCode in [400, 409, 422] {
            let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
            let repository = makeRepository(
                clock: clock,
                uuidStart: statusCode
            )
            await seedSummary(
                date: keyboardUsageDate(2026, 8, 20),
                session: statusCode,
                repository: repository
            )
            let network = AnalyticsQueueNetwork([
                .response(analyticsHTTPResponse(statusCode: statusCode))
            ])
            let coordinator = makeCoordinator(
                repository: repository,
                network: network,
                clock: clock
            )

            await coordinator.uploadAvailableSummaries()

            let snapshot = await repository.debugSnapshot()
            XCTAssertTrue(snapshot.pending.isEmpty, "HTTP \(statusCode)")
            XCTAssertEqual(snapshot.quarantined.count, 1, "HTTP \(statusCode)")
            XCTAssertEqual(
                snapshot.quarantined.first?.statusCode,
                statusCode
            )
            XCTAssertNil(snapshot.quarantined.first?.clientSummaryID)
            let requests = await network.requests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testNetworkAndServerFailuresUseExponentialRetry() async throws {
        let outcomes: [AnalyticsQueueNetwork.Outcome] = [
            .urlError(.notConnectedToInternet),
            .response(analyticsHTTPResponse(statusCode: 503))
        ]
        for (index, outcome) in outcomes.enumerated() {
            let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
            let repository = makeRepository(
                clock: clock,
                uuidStart: 100 + index
            )
            await seedSummary(
                date: keyboardUsageDate(2026, 8, 20),
                session: 10 + index,
                repository: repository
            )
            let originalSnapshot = await repository.debugSnapshot()
            let originalID = try XCTUnwrap(
                originalSnapshot.pending.first?.clientSummaryID
            )
            let network = AnalyticsQueueNetwork([outcome])
            let coordinator = makeCoordinator(
                repository: repository,
                network: network,
                clock: clock,
                random: AnalyticsTestRandomGenerator(.upperBound)
            )

            await coordinator.uploadAvailableSummaries()

            let retrySnapshot = await repository.debugSnapshot()
            let pending = try XCTUnwrap(retrySnapshot.pending.first)
            XCTAssertEqual(pending.attemptCount, 1)
            XCTAssertEqual(
                pending.nextAttemptAt,
                clock.now().addingTimeInterval(1)
            )
            XCTAssertEqual(pending.clientSummaryID, originalID)
        }
    }

    func testResponseCountMismatchRetainsOutbox() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await seedSummary(
            date: keyboardUsageDate(2026, 8, 20),
            session: 20,
            repository: repository
        )
        let network = AnalyticsQueueNetwork([
            .response(keyboardUsageSuccessResponse(accepted: 0, replayed: 0))
        ])
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock,
            random: AnalyticsTestRandomGenerator(.upperBound)
        )

        await coordinator.uploadAvailableSummaries()

        let pending = await repository.debugSnapshot().pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attemptCount, 1)
    }

    func testCancellationReleasesSummaryLeaseWithoutRetry() async throws {
        let clock = AnalyticsTestWallClock(keyboardUsageDate(2026, 8, 21))
        let repository = makeRepository(clock: clock)
        await seedSummary(
            date: keyboardUsageDate(2026, 8, 20),
            session: 21,
            repository: repository
        )
        let network = CancellableKeyboardUsageNetwork()
        let coordinator = makeCoordinator(
            repository: repository,
            network: network,
            clock: clock
        )
        let upload = Task {
            await coordinator.uploadAvailableSummaries()
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
        XCTAssertEqual(snapshot.pending.first?.attemptCount, 0)
        let recovered = await repository.leaseBatch(
            ownerID: "after-cancellation",
            configuration: uploadConfiguration()
        )
        XCTAssertEqual(recovered?.summaries.count, 1)
    }

    private func seedSummary(
        date: Date,
        session: Int,
        repository: KeyboardUsageRepository
    ) async {
        await keyboardUsageRecord(
            .init(chinese: 1, english: 1, other: 1),
            sessionID: analyticsTestUUID(session),
            occurredAt: date,
            repository: repository
        )
    }

    private func makeRepository(
        clock: AnalyticsTestWallClock,
        uuidStart: Int = 100
    ) -> KeyboardUsageRepository {
        KeyboardUsageRepository(
            configuration: KeyboardUsageRepositoryConfiguration(
                databaseURL: try! keyboardUsageTemporaryDatabaseURL()
            ),
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: uuidStart)
        )
    }

    private func uploadConfiguration() -> KeyboardUsageUploadConfiguration {
        KeyboardUsageUploadConfiguration(
            endpoint: endpoint,
            maximumBackoff: 600
        )
    }

    private func makeCoordinator(
        repository: KeyboardUsageRepository,
        network: some AnalyticsNetworking,
        clock: AnalyticsTestWallClock,
        random: AnalyticsTestRandomGenerator = AnalyticsTestRandomGenerator()
    ) -> KeyboardUsageUploadCoordinator {
        KeyboardUsageUploadCoordinator(
            repository: repository,
            configuration: uploadConfiguration(),
            network: network,
            clock: clock,
            uuidGenerator: AnalyticsTestUUIDGenerator(startingAt: 5_000),
            random: random
        )
    }
}

private actor CancellableKeyboardUsageNetwork: AnalyticsNetworking {
    private var started = false

    func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse {
        _ = request
        started = true
        try await Task.sleep(for: .seconds(30))
        return keyboardUsageSuccessResponse(accepted: 1)
    }

    func didStart() -> Bool {
        started
    }
}

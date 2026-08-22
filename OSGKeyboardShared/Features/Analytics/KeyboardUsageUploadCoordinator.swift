// KeyboardUsageUploadCoordinator.swift
// OSGKeyboard · Shared
//
// Uploads immutable daily summaries with the existing analytics transport,
// optional account bearer, bounded retry and cross-process leases.

import Foundation

public struct KeyboardUsageUploadConfiguration: Sendable {
    public let endpoint: URL
    public let maximumBatchCount: Int
    public let globalLeaseDuration: TimeInterval
    public let summaryLeaseDuration: TimeInterval
    public let maximumBackoff: TimeInterval

    public init(
        endpoint: URL,
        maximumBatchCount: Int = 50,
        globalLeaseDuration: TimeInterval = 2 * 60,
        summaryLeaseDuration: TimeInterval = 5 * 60,
        maximumBackoff: TimeInterval = 6 * 60 * 60
    ) {
        self.endpoint = endpoint
        self.maximumBatchCount = min(50, max(1, maximumBatchCount))
        self.globalLeaseDuration = max(60, globalLeaseDuration)
        self.summaryLeaseDuration = max(60, summaryLeaseDuration)
        self.maximumBackoff = min(6 * 60 * 60, max(60, maximumBackoff))
    }
}

public actor KeyboardUsageUploadCoordinator {
    private struct AuthorizationState {
        var token: String?
        var didRefresh = false
    }

    private let repository: KeyboardUsageRepository
    private let configuration: KeyboardUsageUploadConfiguration
    private let network: any AnalyticsNetworking
    private let bearerProvider: (any AnalyticsBearerProviding)?
    private let clock: any AnalyticsWallClock
    private let uuidGenerator: any AnalyticsUUIDGenerating
    private let random: any AnalyticsRandomGenerating
    private let logger: any AnalyticsLogging
    private var uploadInProgress = false

    public init(
        repository: KeyboardUsageRepository,
        configuration: KeyboardUsageUploadConfiguration,
        network: any AnalyticsNetworking = URLSessionAnalyticsNetwork(),
        bearerProvider: (any AnalyticsBearerProviding)? = nil,
        clock: any AnalyticsWallClock = SystemAnalyticsWallClock(),
        uuidGenerator: any AnalyticsUUIDGenerating = SystemAnalyticsUUIDGenerator(),
        random: any AnalyticsRandomGenerating = SystemAnalyticsRandomGenerator(),
        logger: any AnalyticsLogging = NoopAnalyticsLogger()
    ) {
        self.repository = repository
        self.configuration = configuration
        self.network = network
        self.bearerProvider = bearerProvider
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.random = random
        self.logger = logger
    }

    public func uploadAvailableSummaries(maximumBatches: Int = 1) async {
        guard !uploadInProgress, !Task.isCancelled else { return }
        uploadInProgress = true
        defer { uploadInProgress = false }

        guard configuration.endpoint.scheme?.lowercased() == "https" else {
            log(
                outcome: .skipped,
                count: 0,
                category: .client
            )
            return
        }

        let ownerID = uuidGenerator.makeUUID().uuidString.lowercased()
        for _ in 0..<max(1, maximumBatches) {
            guard !Task.isCancelled else { return }
            guard let batch = await repository.leaseBatch(
                ownerID: ownerID,
                configuration: configuration
            ) else {
                return
            }
            guard !Task.isCancelled else {
                await releaseForCancellation(
                    summaries: batch.summaries,
                    leaseID: batch.leaseID,
                    ownerID: ownerID
                )
                return
            }
            var authorization = AuthorizationState()
            if let bearerProvider {
                do {
                    authorization.token = try await bearerProvider.bearerToken()
                } catch {
                    if Task.isCancelled {
                        await releaseForCancellation(
                            summaries: batch.summaries,
                            leaseID: batch.leaseID,
                            ownerID: ownerID
                        )
                        return
                    }
                    await scheduleRetry(
                        batch.summaries,
                        leaseID: batch.leaseID,
                        response: nil,
                        category: .authentication
                    )
                    await repository.releaseGlobalLease(ownerID: ownerID)
                    return
                }
            }
            await process(
                batch.summaries,
                installationID: batch.installationID,
                leaseID: batch.leaseID,
                ownerID: ownerID,
                authorization: &authorization
            )
            await repository.releaseGlobalLease(ownerID: ownerID)
            guard !Task.isCancelled else { return }
        }
    }

    private func process(
        _ summaries: [KeyboardUsageLeasedSummary],
        installationID: UUID,
        leaseID: String,
        ownerID: String,
        authorization: inout AuthorizationState
    ) async {
        guard !summaries.isEmpty else { return }
        guard !Task.isCancelled else {
            await repository.release(summaries: summaries, leaseID: leaseID)
            return
        }
        guard await renewLease(
            summaries: summaries,
            leaseID: leaseID,
            ownerID: ownerID
        ) else {
            return
        }
        guard !Task.isCancelled else {
            await repository.release(summaries: summaries, leaseID: leaseID)
            return
        }

        let response: AnalyticsHTTPResponse
        do {
            response = try await send(
                summaries: summaries,
                installationID: installationID,
                token: authorization.token
            )
        } catch {
            if Task.isCancelled {
                await repository.release(summaries: summaries, leaseID: leaseID)
                return
            }
            await scheduleRetry(
                summaries,
                leaseID: leaseID,
                response: nil,
                category: Self.networkCategory(for: error)
            )
            return
        }

        if response.statusCode == 401,
           !authorization.didRefresh,
           let bearerProvider {
            authorization.didRefresh = true
            let failedToken = authorization.token
            do {
                authorization.token = try await bearerProvider.refreshBearerToken(
                    afterUnauthorizedAccessToken: failedToken
                )
                guard await renewLease(
                    summaries: summaries,
                    leaseID: leaseID,
                    ownerID: ownerID
                ) else {
                    return
                }
                let refreshed = try await send(
                    summaries: summaries,
                    installationID: installationID,
                    token: authorization.token
                )
                await processResponse(
                    refreshed,
                    summaries: summaries,
                    installationID: installationID,
                    leaseID: leaseID,
                    ownerID: ownerID,
                    authorization: &authorization
                )
            } catch {
                if Task.isCancelled {
                    await repository.release(summaries: summaries, leaseID: leaseID)
                    return
                }
                await scheduleRetry(
                    summaries,
                    leaseID: leaseID,
                    response: response,
                    category: .authentication,
                    minimumDelay: configuration.maximumBackoff
                )
            }
            return
        }

        await processResponse(
            response,
            summaries: summaries,
            installationID: installationID,
            leaseID: leaseID,
            ownerID: ownerID,
            authorization: &authorization
        )
    }

    private func processResponse(
        _ response: AnalyticsHTTPResponse,
        summaries: [KeyboardUsageLeasedSummary],
        installationID: UUID,
        leaseID: String,
        ownerID: String,
        authorization: inout AuthorizationState
    ) async {
        guard !Task.isCancelled else {
            await repository.release(summaries: summaries, leaseID: leaseID)
            return
        }
        switch response.statusCode {
        case 200:
            let decoded: KeyboardUsageUploadResponse
            do {
                decoded = try JSONDecoder().decode(
                    KeyboardUsageUploadResponse.self,
                    from: response.body
                )
            } catch {
                await scheduleRetry(
                    summaries,
                    leaseID: leaseID,
                    response: response,
                    category: .decoding
                )
                return
            }
            guard decoded.accepted + decoded.replayed == summaries.count else {
                await scheduleRetry(
                    summaries,
                    leaseID: leaseID,
                    response: response,
                    category: .countMismatch
                )
                return
            }
            let completed = await repository.complete(
                rowIDs: summaries.map(\.rowID),
                leaseID: leaseID
            )
            log(
                outcome: completed ? .uploaded : .retryScheduled,
                count: summaries.count,
                statusCode: response.statusCode,
                attempt: maximumAttempt(in: summaries),
                category: completed ? nil : .storage
            )

        case 400, 409, 422:
            if summaries.count == 1 {
                await repository.quarantine(
                    rowIDs: [summaries[0].rowID],
                    leaseID: leaseID,
                    statusCode: response.statusCode
                )
                log(
                    outcome: .quarantined,
                    count: 1,
                    statusCode: response.statusCode,
                    attempt: summaries[0].attemptCount,
                    category: .client
                )
                return
            }
            let midpoint = summaries.count / 2
            await process(
                Array(summaries[..<midpoint]),
                installationID: installationID,
                leaseID: leaseID,
                ownerID: ownerID,
                authorization: &authorization
            )
            await process(
                Array(summaries[midpoint...]),
                installationID: installationID,
                leaseID: leaseID,
                ownerID: ownerID,
                authorization: &authorization
            )

        case 401:
            await scheduleRetry(
                summaries,
                leaseID: leaseID,
                response: response,
                category: .authentication,
                minimumDelay: configuration.maximumBackoff
            )

        case 408:
            await scheduleRetry(
                summaries,
                leaseID: leaseID,
                response: response,
                category: .timeout
            )

        case 429:
            await scheduleRetry(
                summaries,
                leaseID: leaseID,
                response: response,
                category: .rateLimited
            )

        case 500...599:
            await scheduleRetry(
                summaries,
                leaseID: leaseID,
                response: response,
                category: .server
            )

        case 400...499:
            await repository.quarantine(
                rowIDs: summaries.map(\.rowID),
                leaseID: leaseID,
                statusCode: response.statusCode
            )
            log(
                outcome: .quarantined,
                count: summaries.count,
                statusCode: response.statusCode,
                attempt: maximumAttempt(in: summaries),
                category: .client
            )

        default:
            await scheduleRetry(
                summaries,
                leaseID: leaseID,
                response: response,
                category: .server
            )
        }
    }

    private func releaseForCancellation(
        summaries: [KeyboardUsageLeasedSummary],
        leaseID: String,
        ownerID: String
    ) async {
        await repository.release(summaries: summaries, leaseID: leaseID)
        await repository.releaseGlobalLease(ownerID: ownerID)
    }

    private func send(
        summaries: [KeyboardUsageLeasedSummary],
        installationID: UUID,
        token: String?
    ) async throws -> AnalyticsHTTPResponse {
        var headers = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        if let token, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        return try await network.send(
            AnalyticsHTTPRequest(
                url: configuration.endpoint,
                headers: headers,
                body: Self.requestBody(
                    summaries: summaries,
                    installationID: installationID
                )
            )
        )
    }

    private func renewLease(
        summaries: [KeyboardUsageLeasedSummary],
        leaseID: String,
        ownerID: String
    ) async -> Bool {
        let renewed = await repository.renewLease(
            ownerID: ownerID,
            leaseID: leaseID,
            configuration: configuration
        )
        guard renewed else {
            await repository.release(summaries: summaries, leaseID: leaseID)
            log(
                outcome: .skipped,
                count: summaries.count,
                attempt: maximumAttempt(in: summaries),
                category: .storage
            )
            return false
        }
        return true
    }

    private func scheduleRetry(
        _ summaries: [KeyboardUsageLeasedSummary],
        leaseID: String,
        response: AnalyticsHTTPResponse?,
        category: AnalyticsUploadErrorCategory,
        minimumDelay: TimeInterval = 0
    ) async {
        let attempt = maximumAttempt(in: summaries) + 1
        let exponent = min(attempt - 1, 16)
        let ceiling = min(
            configuration.maximumBackoff,
            pow(2, Double(exponent))
        )
        let jitterMilliseconds = random.next(
            upperBound: UInt64(max(0, ceiling * 1_000))
        )
        let jitter = TimeInterval(jitterMilliseconds) / 1_000
        let retryAfter = response.flatMap(retryAfterDelay) ?? 0
        let delay = min(
            configuration.maximumBackoff,
            max(minimumDelay, retryAfter, jitter)
        )
        await repository.scheduleRetry(
            summaries: summaries,
            leaseID: leaseID,
            delay: delay
        )
        log(
            outcome: .retryScheduled,
            count: summaries.count,
            statusCode: response?.statusCode,
            attempt: attempt,
            category: category
        )
    }

    private func retryAfterDelay(
        _ response: AnalyticsHTTPResponse
    ) -> TimeInterval? {
        guard let value = response.header(named: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return min(configuration.maximumBackoff, max(0, seconds))
        }
        guard let date = Self.httpDateFormatter.date(from: value) else {
            return nil
        }
        return min(
            configuration.maximumBackoff,
            max(0, date.timeIntervalSince(clock.now()))
        )
    }

    private func maximumAttempt(
        in summaries: [KeyboardUsageLeasedSummary]
    ) -> Int {
        summaries.map(\.attemptCount).max() ?? 0
    }

    private func log(
        outcome: AnalyticsUploadLogEntry.Outcome,
        count: Int,
        statusCode: Int? = nil,
        attempt: Int = 0,
        category: AnalyticsUploadErrorCategory?
    ) {
        logger.log(
            AnalyticsUploadLogEntry(
                outcome: outcome,
                eventCount: count,
                statusCode: statusCode,
                attempt: attempt,
                errorCategory: category
            )
        )
    }

    private static func requestBody(
        summaries: [KeyboardUsageLeasedSummary],
        installationID: UUID
    ) -> Data {
        var body = Data(
            #"{"installationId":"\#(installationID.uuidString.lowercased())","summaries":["#
                .utf8
        )
        for index in summaries.indices {
            if index > 0 {
                body.append(UInt8(ascii: ","))
            }
            body.append(summaries[index].payload)
        }
        body.append(Data("]}".utf8))
        return body
    }

    private static func networkCategory(
        for error: Error
    ) -> AnalyticsUploadErrorCategory {
        guard let urlError = error as? URLError else { return .network }
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .userAuthenticationRequired,
             .userCancelledAuthentication:
            return .authentication
        default:
            return .network
        }
    }

    private static var httpDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }
}

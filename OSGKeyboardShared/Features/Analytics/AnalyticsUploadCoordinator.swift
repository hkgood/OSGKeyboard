// AnalyticsUploadCoordinator.swift
// OSGKeyboard · Shared
//
// Bounded uploader with cross-process leases, retry policy and poison-event
// isolation. Logs never contain payloads, identifiers, endpoints or tokens.

import Foundation

public final class URLSessionAnalyticsNetwork: AnalyticsNetworking, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 30
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (body, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyticsNetworkError.nonHTTPResponse
        }
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return AnalyticsHTTPResponse(
            statusCode: httpResponse.statusCode,
            headers: headers,
            body: body
        )
    }
}

public actor AnalyticsUploadCoordinator {
    private struct AuthorizationState {
        var token: String?
        var didRefresh = false
    }

    private let repository: AnalyticsRepository
    private let configuration: AnalyticsUploadConfiguration
    private let network: any AnalyticsNetworking
    private let bearerProvider: (any AnalyticsBearerProviding)?
    private let clock: any AnalyticsWallClock
    private let uuidGenerator: any AnalyticsUUIDGenerating
    private let random: any AnalyticsRandomGenerating
    private let logger: any AnalyticsLogging
    private var uploadInProgress = false

    public init(
        repository: AnalyticsRepository,
        configuration: AnalyticsUploadConfiguration,
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

    /// Performs a bounded drain. The default keeps extension execution time and
    /// memory predictable while allowing a host app to request more batches.
    public func uploadAvailableEvents(maximumBatches: Int = 1) async {
        guard !uploadInProgress else { return }
        uploadInProgress = true
        defer { uploadInProgress = false }

        guard configuration.endpoint.scheme?.lowercased() == "https" else {
            logger.log(
                AnalyticsUploadLogEntry(
                    outcome: .skipped,
                    eventCount: 0,
                    errorCategory: .client
                )
            )
            return
        }

        let ownerID = uuidGenerator.makeUUID().uuidString.lowercased()
        let batchLimit = max(1, maximumBatches)
        for _ in 0..<batchLimit {
            guard let batch = await repository.leaseBatch(
                ownerID: ownerID,
                configuration: configuration
            ) else {
                return
            }

            var authorization = AuthorizationState()
            if let bearerProvider {
                do {
                    authorization.token = try await bearerProvider.bearerToken()
                } catch {
                    await scheduleRetry(
                        events: batch.events,
                        leaseID: batch.leaseID,
                        response: nil,
                        category: .authentication
                    )
                    await repository.releaseGlobalLease(ownerID: ownerID)
                    return
                }
            }

            await process(
                events: batch.events,
                leaseID: batch.leaseID,
                ownerID: ownerID,
                authorization: &authorization
            )
            await repository.releaseGlobalLease(ownerID: ownerID)
        }
    }

    private func process(
        events: [AnalyticsLeasedEvent],
        leaseID: String,
        ownerID: String,
        authorization: inout AuthorizationState
    ) async {
        guard !events.isEmpty else { return }
        guard await renewLease(
            events: events,
            leaseID: leaseID,
            ownerID: ownerID
        ) else {
            return
        }

        let response: AnalyticsHTTPResponse
        do {
            response = try await send(events: events, token: authorization.token)
        } catch {
            await scheduleRetry(
                events: events,
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
                    events: events,
                    leaseID: leaseID,
                    ownerID: ownerID
                ) else {
                    return
                }
                let refreshed = try await send(events: events, token: authorization.token)
                await processResponse(
                    refreshed,
                    events: events,
                    leaseID: leaseID,
                    ownerID: ownerID,
                    authorization: &authorization
                )
            } catch {
                await scheduleRetry(
                    events: events,
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
            events: events,
            leaseID: leaseID,
            ownerID: ownerID,
            authorization: &authorization
        )
    }

    private func processResponse(
        _ response: AnalyticsHTTPResponse,
        events: [AnalyticsLeasedEvent],
        leaseID: String,
        ownerID: String,
        authorization: inout AuthorizationState
    ) async {
        switch response.statusCode {
        case 200:
            let decoded: AnalyticsUploadResponse
            do {
                decoded = try JSONDecoder().decode(
                    AnalyticsUploadResponse.self,
                    from: response.body
                )
            } catch {
                await scheduleRetry(
                    events: events,
                    leaseID: leaseID,
                    response: response,
                    category: .decoding
                )
                return
            }
            guard decoded.accepted + decoded.replayed == events.count else {
                await scheduleRetry(
                    events: events,
                    leaseID: leaseID,
                    response: response,
                    category: .countMismatch
                )
                return
            }
            let completed = await repository.complete(
                rowIDs: events.map(\.rowID),
                leaseID: leaseID
            )
            logger.log(
                AnalyticsUploadLogEntry(
                    outcome: completed ? .uploaded : .retryScheduled,
                    eventCount: events.count,
                    statusCode: response.statusCode,
                    attempt: maximumAttempt(in: events),
                    errorCategory: completed ? nil : .storage
                )
            )

        case 400, 409, 422:
            if events.count == 1 {
                await repository.quarantine(
                    rowIDs: [events[0].rowID],
                    leaseID: leaseID,
                    reason: "http\(response.statusCode)"
                )
                logger.log(
                    AnalyticsUploadLogEntry(
                        outcome: .quarantined,
                        eventCount: 1,
                        statusCode: response.statusCode,
                        attempt: events[0].attemptCount,
                        errorCategory: .client
                    )
                )
                return
            }

            let midpoint = events.count / 2
            await process(
                events: Array(events[..<midpoint]),
                leaseID: leaseID,
                ownerID: ownerID,
                authorization: &authorization
            )
            await process(
                events: Array(events[midpoint...]),
                leaseID: leaseID,
                ownerID: ownerID,
                authorization: &authorization
            )

        case 401:
            await scheduleRetry(
                events: events,
                leaseID: leaseID,
                response: response,
                category: .authentication,
                minimumDelay: configuration.maximumBackoff
            )

        case 408:
            await scheduleRetry(
                events: events,
                leaseID: leaseID,
                response: response,
                category: .timeout
            )

        case 429:
            await scheduleRetry(
                events: events,
                leaseID: leaseID,
                response: response,
                category: .rateLimited
            )

        case 500...599:
            await scheduleRetry(
                events: events,
                leaseID: leaseID,
                response: response,
                category: .server
            )

        case 400...499:
            await repository.quarantine(
                rowIDs: events.map(\.rowID),
                leaseID: leaseID,
                reason: "http\(response.statusCode)"
            )
            logger.log(
                AnalyticsUploadLogEntry(
                    outcome: .quarantined,
                    eventCount: events.count,
                    statusCode: response.statusCode,
                    attempt: maximumAttempt(in: events),
                    errorCategory: .client
                )
            )

        default:
            await scheduleRetry(
                events: events,
                leaseID: leaseID,
                response: response,
                category: .server
            )
        }
    }

    private func send(
        events: [AnalyticsLeasedEvent],
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
                body: Self.requestBody(for: events)
            )
        )
    }

    private func renewLease(
        events: [AnalyticsLeasedEvent],
        leaseID: String,
        ownerID: String
    ) async -> Bool {
        let renewed = await repository.renewUploadLease(
            ownerID: ownerID,
            leaseID: leaseID,
            globalLeaseDuration: configuration.globalLeaseDuration,
            eventLeaseDuration: configuration.eventLeaseDuration
        )
        guard renewed else {
            await repository.releaseEvents(events, leaseID: leaseID)
            logger.log(
                AnalyticsUploadLogEntry(
                    outcome: .skipped,
                    eventCount: events.count,
                    attempt: maximumAttempt(in: events),
                    errorCategory: .storage
                )
            )
            return false
        }
        return true
    }

    private func scheduleRetry(
        events: [AnalyticsLeasedEvent],
        leaseID: String,
        response: AnalyticsHTTPResponse?,
        category: AnalyticsUploadErrorCategory,
        minimumDelay: TimeInterval = 0
    ) async {
        let attempt = maximumAttempt(in: events) + 1
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
            events: events,
            leaseID: leaseID,
            delay: delay
        )
        logger.log(
            AnalyticsUploadLogEntry(
                outcome: .retryScheduled,
                eventCount: events.count,
                statusCode: response?.statusCode,
                attempt: attempt,
                errorCategory: category
            )
        )
    }

    private func retryAfterDelay(_ response: AnalyticsHTTPResponse) -> TimeInterval? {
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

    private func maximumAttempt(in events: [AnalyticsLeasedEvent]) -> Int {
        events.map(\.attemptCount).max() ?? 0
    }

    private static func requestBody(for events: [AnalyticsLeasedEvent]) -> Data {
        var body = Data(#"{"events":["#.utf8)
        for index in events.indices {
            if index > 0 {
                body.append(UInt8(ascii: ","))
            }
            body.append(events[index].payload)
        }
        body.append(Data("]}".utf8))
        return body
    }

    private static func networkCategory(for error: Error) -> AnalyticsUploadErrorCategory {
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

private enum AnalyticsNetworkError: Error {
    case nonHTTPResponse
}

// AnalyticsTestSupport.swift
// OSGKeyboardTests
//
// Deterministic analytics clocks, identifiers, transport doubles, and fixtures.

import Foundation
@testable import OSGKeyboardShared
import XCTest

let analyticsTestContext = AnalyticsBootstrapContext(
    surface: .app,
    environment: AnalyticsEnvironment(appVersion: "2.0.0", osVersion: "26.0")
)

func analyticsTestUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
}

func analyticsTemporaryDatabaseURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("OSGKeyboardAnalyticsTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory.appendingPathComponent("analytics.sqlite3")
}

final class AnalyticsTestWallClock: AnalyticsWallClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.value = value
    }

    func now() -> Date {
        lock.withLock { value }
    }

    func set(_ value: Date) {
        lock.withLock { self.value = value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { value = value.addingTimeInterval(interval) }
    }
}

final class AnalyticsTestMonotonicClock: AnalyticsMonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64 = 0) {
        self.value = value
    }

    func nowNanoseconds() -> UInt64 {
        lock.withLock { value }
    }

    func set(_ value: UInt64) {
        lock.withLock { self.value = value }
    }
}

final class AnalyticsTestUUIDGenerator: AnalyticsUUIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var nextValue: Int

    init(startingAt value: Int = 1) {
        nextValue = value
    }

    func makeUUID() -> UUID {
        lock.withLock {
            defer { nextValue += 1 }
            return analyticsTestUUID(nextValue)
        }
    }
}

final class AnalyticsTestRandomGenerator: AnalyticsRandomGenerating, @unchecked Sendable {
    enum Value {
        case zero
        case upperBound
        case fixed(UInt64)
    }

    private let value: Value

    init(_ value: Value = .zero) {
        self.value = value
    }

    func next(upperBound: UInt64) -> UInt64 {
        switch value {
        case .zero:
            return 0
        case .upperBound:
            return upperBound
        case .fixed(let fixed):
            return min(fixed, upperBound)
        }
    }
}

actor AnalyticsQueueNetwork: AnalyticsNetworking {
    enum Outcome: Sendable {
        case response(AnalyticsHTTPResponse)
        case urlError(URLError.Code)
    }

    private var outcomes: [Outcome]
    private var capturedRequests: [AnalyticsHTTPRequest] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse {
        capturedRequests.append(request)
        guard !outcomes.isEmpty else {
            return AnalyticsHTTPResponse(statusCode: 500, headers: [:], body: Data())
        }
        switch outcomes.removeFirst() {
        case .response(let response):
            return response
        case .urlError(let code):
            throw URLError(code)
        }
    }

    func requests() -> [AnalyticsHTTPRequest] {
        capturedRequests
    }
}

actor AnalyticsPoisonNetwork: AnalyticsNetworking {
    private let statusCode: Int
    private let poisonID: UUID
    private var capturedRequests: [AnalyticsHTTPRequest] = []

    init(statusCode: Int, poisonID: UUID) {
        self.statusCode = statusCode
        self.poisonID = poisonID
    }

    func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse {
        capturedRequests.append(request)
        let upload = try JSONDecoder().decode(AnalyticsUploadRequest.self, from: request.body)
        if upload.events.contains(where: { $0.clientEventId == poisonID }) {
            return AnalyticsHTTPResponse(statusCode: statusCode, headers: [:], body: Data())
        }
        return analyticsSuccessResponse(accepted: upload.events.count)
    }

    func requests() -> [AnalyticsHTTPRequest] {
        capturedRequests
    }
}

actor AnalyticsTestBearerProvider: AnalyticsBearerProviding {
    private let initialToken: String?
    private let refreshedToken: String?
    private var refreshInputs: [String?] = []

    init(initialToken: String?, refreshedToken: String?) {
        self.initialToken = initialToken
        self.refreshedToken = refreshedToken
    }

    func bearerToken() async throws -> String? {
        initialToken
    }

    func refreshBearerToken(
        afterUnauthorizedAccessToken failedToken: String?
    ) async throws -> String? {
        refreshInputs.append(failedToken)
        return refreshedToken
    }

    func recordedRefreshInputs() -> [String?] {
        refreshInputs
    }
}

func analyticsSuccessResponse(
    accepted: Int,
    replayed: Int = 0
) -> AnalyticsHTTPResponse {
    AnalyticsHTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"accepted":\#(accepted),"replayed":\#(replayed)}"#.utf8)
    )
}

func analyticsHTTPResponse(
    statusCode: Int,
    headers: [String: String] = [:],
    body: Data = Data()
) -> AnalyticsHTTPResponse {
    AnalyticsHTTPResponse(statusCode: statusCode, headers: headers, body: body)
}

func analyticsRecordKeyboardEvents(
    count: Int,
    repository: AnalyticsRepository,
    context: AnalyticsBootstrapContext = analyticsTestContext
) async {
    for _ in 0..<count {
        await repository.record(
            eventType: .keyboardActivated,
            context: context
        )
    }
}

func analyticsPendingPayloads(
    repository: AnalyticsRepository
) async throws -> [Data] {
    let snapshot = await repository.debugSnapshot()
    var payloads: [Data] = []
    for diagnostic in snapshot.pendingEvents {
        let payload = await repository.debugPayloadBytes(rowID: diagnostic.rowID)
        payloads.append(try XCTUnwrap(payload))
    }
    return payloads
}

func analyticsDecodePendingEvents(
    repository: AnalyticsRepository
) async throws -> [AnalyticsEvent] {
    let payloads = try await analyticsPendingPayloads(repository: repository)
    return try payloads.map { try JSONDecoder().decode(AnalyticsEvent.self, from: $0) }
}

func analyticsRequestBody(
    payloads: [Data],
    installationID: UUID = analyticsTestUUID(1)
) -> Data {
    var body = Data(
        #"{"installationId":"\#(installationID.uuidString.lowercased())","events":["#
            .utf8
    )
    for index in payloads.indices {
        if index > 0 {
            body.append(UInt8(ascii: ","))
        }
        body.append(payloads[index])
    }
    body.append(Data("]}".utf8))
    return body
}

func analyticsWaitForPendingEventCount(
    _ count: Int,
    repository: AnalyticsRepository,
    timeoutIterations: Int = 200
) async -> AnalyticsRepositoryDebugSnapshot {
    for _ in 0..<timeoutIterations {
        let snapshot = await repository.debugSnapshot()
        if snapshot.pendingEvents.count >= count {
            return snapshot
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for \(count) analytics events")
    return await repository.debugSnapshot()
}

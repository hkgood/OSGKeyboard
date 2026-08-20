// AnalyticsDependencies.swift
// OSGKeyboard · Shared
//
// Injectable system boundaries used by both the host app and keyboard extension.

import Foundation

public protocol AnalyticsWallClock: Sendable {
    func now() -> Date
}

public protocol AnalyticsMonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public protocol AnalyticsUUIDGenerating: Sendable {
    func makeUUID() -> UUID
}

public protocol AnalyticsRandomGenerating: Sendable {
    /// Returns a value in the closed range 0...upperBound.
    func next(upperBound: UInt64) -> UInt64
}

public struct SystemAnalyticsWallClock: AnalyticsWallClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public struct SystemAnalyticsMonotonicClock: AnalyticsMonotonicClock {
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

public struct SystemAnalyticsUUIDGenerator: AnalyticsUUIDGenerating {
    public init() {}

    public func makeUUID() -> UUID {
        UUID()
    }
}

public final class SystemAnalyticsRandomGenerator: AnalyticsRandomGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var generator = SystemRandomNumberGenerator()

    public init() {}

    public func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 0 else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        return UInt64.random(in: 0...upperBound, using: &generator)
    }
}

public struct AnalyticsHTTPRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public init(url: URL, headers: [String: String], body: Data) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct AnalyticsHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol AnalyticsNetworking: Sendable {
    func send(_ request: AnalyticsHTTPRequest) async throws -> AnalyticsHTTPResponse
}

public protocol AnalyticsBearerProviding: Sendable {
    func bearerToken() async throws -> String?
    func refreshBearerToken(
        afterUnauthorizedAccessToken failedToken: String?
    ) async throws -> String?
}

public protocol AnalyticsUploadTriggering: Sendable {
    func requestUpload() async
}

public struct NoopAnalyticsUploadTrigger: AnalyticsUploadTriggering {
    public init() {}

    public func requestUpload() async {}
}

public enum AnalyticsUploadErrorCategory: String, Sendable {
    case network
    case timeout
    case authentication
    case rateLimited
    case server
    case client
    case decoding
    case countMismatch
    case storage
}

public struct AnalyticsUploadLogEntry: Sendable {
    public enum Outcome: String, Sendable {
        case uploaded
        case retryScheduled
        case quarantined
        case skipped
    }

    public let outcome: Outcome
    public let eventCount: Int
    public let statusCode: Int?
    public let attempt: Int
    public let errorCategory: AnalyticsUploadErrorCategory?

    public init(
        outcome: Outcome,
        eventCount: Int,
        statusCode: Int? = nil,
        attempt: Int = 0,
        errorCategory: AnalyticsUploadErrorCategory? = nil
    ) {
        self.outcome = outcome
        self.eventCount = eventCount
        self.statusCode = statusCode
        self.attempt = attempt
        self.errorCategory = errorCategory
    }
}

public protocol AnalyticsLogging: Sendable {
    func log(_ entry: AnalyticsUploadLogEntry)
}

public struct NoopAnalyticsLogger: AnalyticsLogging {
    public init() {}

    public func log(_ entry: AnalyticsUploadLogEntry) {}
}

public struct AnalyticsRepositoryConfiguration: Sendable {
    public static let defaultDatabaseFilename = "analytics.sqlite3"

    public let databaseURL: URL?
    public let maximumEventCount: Int
    public let maximumStoredBytes: Int
    public let eventRetention: TimeInterval
    public let busyTimeoutMilliseconds: Int32

    public init(
        databaseURL: URL?,
        maximumEventCount: Int = 10_000,
        maximumStoredBytes: Int = 5 * 1_024 * 1_024,
        eventRetention: TimeInterval = 34 * 24 * 60 * 60,
        busyTimeoutMilliseconds: Int32 = 2_000
    ) {
        self.databaseURL = databaseURL
        self.maximumEventCount = max(1, maximumEventCount)
        self.maximumStoredBytes = max(1_024, maximumStoredBytes)
        self.eventRetention = max(60, eventRetention)
        self.busyTimeoutMilliseconds = max(0, busyTimeoutMilliseconds)
    }

    public static func appGroupDefault(
        appGroupIdentifier: String = AppGroup.identifier
    ) -> Self {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        let directory = container?.appendingPathComponent(
            "Library/Application Support/Analytics",
            isDirectory: true
        )
        return Self(
            databaseURL: directory?.appendingPathComponent(defaultDatabaseFilename)
        )
    }
}

public struct AnalyticsUploadConfiguration: Sendable {
    public let endpoint: URL
    public let maximumBatchCount: Int
    public let maximumBodyBytes: Int
    public let globalLeaseDuration: TimeInterval
    public let eventLeaseDuration: TimeInterval
    public let maximumBackoff: TimeInterval

    public init(
        endpoint: URL,
        maximumBatchCount: Int = 50,
        maximumBodyBytes: Int = 60 * 1_024,
        globalLeaseDuration: TimeInterval = 2 * 60,
        eventLeaseDuration: TimeInterval = 5 * 60,
        maximumBackoff: TimeInterval = 6 * 60 * 60
    ) {
        self.endpoint = endpoint
        self.maximumBatchCount = min(50, max(1, maximumBatchCount))
        self.maximumBodyBytes = min(60 * 1_024, max(1_024, maximumBodyBytes))
        // Both leases outlive the default 30-second transport timeout. The
        // coordinator also renews them immediately before every request.
        self.globalLeaseDuration = max(60, globalLeaseDuration)
        self.eventLeaseDuration = max(60, eventLeaseDuration)
        self.maximumBackoff = min(6 * 60 * 60, max(60, maximumBackoff))
    }
}

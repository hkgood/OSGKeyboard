// AnalyticsModels.swift
// OSGKeyboard · Shared
//
// Privacy-preserving analytics wire contract. There is intentionally no
// free-form properties dictionary or user-provided text in this model.

import Foundation

public enum AnalyticsEventType: String, Codable, CaseIterable, Sendable {
    case firstOpen = "FIRST_OPEN"
    case sessionStarted = "SESSION_STARTED"
    case keyboardActivated = "KEYBOARD_ACTIVATED"
    case aiFeatureStarted = "AI_FEATURE_STARTED"
    case aiFeatureSucceeded = "AI_FEATURE_SUCCEEDED"
    case aiFeatureFailed = "AI_FEATURE_FAILED"
    case purchaseViewed = "PURCHASE_VIEWED"
    case purchaseStarted = "PURCHASE_STARTED"
    case purchaseCancelled = "PURCHASE_CANCELLED"
    case referralShared = "REFERRAL_SHARED"
    case inviteOpened = "INVITE_OPENED"
}

public enum AnalyticsSurface: String, Codable, CaseIterable, Sendable {
    case app = "APP"
    case keyboard = "KEYBOARD"
    case inviteWeb = "INVITE_WEB"
}

public enum AnalyticsAcquisitionChannel: String, Codable, CaseIterable, Sendable {
    case appStoreOrganic = "APP_STORE_ORGANIC"
    case referral = "REFERRAL"
    case socialContent = "SOCIAL_CONTENT"
    case unknown = "UNKNOWN"
}

public enum AnalyticsFeature: String, Codable, CaseIterable, Sendable {
    case transcription = "TRANSCRIPTION"
    case polish = "POLISH"
    case aiAssistant = "AI_ASSISTANT"
    case agent = "AGENT"
    case hotword = "HOTWORD"
    case other = "OTHER"
}

public enum AnalyticsExecutionMode: String, Codable, CaseIterable, Sendable {
    case managed = "MANAGED"
    case local = "LOCAL"
    case byok = "BYOK"
}

public enum AnalyticsFailureCategory: String, Codable, CaseIterable, Sendable {
    case network = "NETWORK"
    case provider = "PROVIDER"
    case timeout = "TIMEOUT"
    case cancelled = "CANCELLED"
    case insufficientCredits = "INSUFFICIENT_CREDITS"
    case validation = "VALIDATION"
    case unknown = "UNKNOWN"
}

public enum AnalyticsDurationBucket: String, Codable, CaseIterable, Sendable {
    case lessThanOneSecond = "LT_1S"
    case oneToThreeSeconds = "S1_TO_3"
    case threeToTenSeconds = "S3_TO_10"
    case tenToThirtySeconds = "S10_TO_30"
    case thirtySecondsOrMore = "GTE_30S"

    public init(elapsedNanoseconds: UInt64) {
        switch elapsedNanoseconds {
        case ..<1_000_000_000:
            self = .lessThanOneSecond
        case ..<3_000_000_000:
            self = .oneToThreeSeconds
        case ..<10_000_000_000:
            self = .threeToTenSeconds
        case ..<30_000_000_000:
            self = .tenToThirtySeconds
        default:
            self = .thirtySecondsOrMore
        }
    }
}

public enum AnalyticsModelError: Error, Sendable {
    case unknownField(String)
    case invalidDimensions(AnalyticsEventType)
    case invalidVersion
    case invalidResponseCounts
}

public struct AnalyticsEvent: Codable, Equatable, Sendable {
    public let clientEventId: UUID
    public let eventType: AnalyticsEventType
    public let occurredAt: Date
    public let surface: AnalyticsSurface
    public let appVersion: String
    public let osVersion: String
    public let acquisitionChannel: AnalyticsAcquisitionChannel?
    public let feature: AnalyticsFeature?
    public let executionMode: AnalyticsExecutionMode?
    public let failureCategory: AnalyticsFailureCategory?
    public let durationBucket: AnalyticsDurationBucket?

    public init(
        clientEventId: UUID,
        eventType: AnalyticsEventType,
        occurredAt: Date,
        surface: AnalyticsSurface,
        appVersion: String,
        osVersion: String,
        acquisitionChannel: AnalyticsAcquisitionChannel? = nil,
        feature: AnalyticsFeature? = nil,
        executionMode: AnalyticsExecutionMode? = nil,
        failureCategory: AnalyticsFailureCategory? = nil,
        durationBucket: AnalyticsDurationBucket? = nil
    ) throws {
        guard AnalyticsEnvironment.isSafeVersion(appVersion),
              AnalyticsEnvironment.isSafeVersion(osVersion) else {
            throw AnalyticsModelError.invalidVersion
        }

        self.clientEventId = clientEventId
        self.eventType = eventType
        self.occurredAt = occurredAt
        self.surface = surface
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.acquisitionChannel = acquisitionChannel
        self.feature = feature
        self.executionMode = executionMode
        self.failureCategory = failureCategory
        self.durationBucket = durationBucket

        guard dimensionsAreAllowed else {
            throw AnalyticsModelError.invalidDimensions(eventType)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clientEventId
        case eventType
        case occurredAt
        case surface
        case appVersion
        case osVersion
        case acquisitionChannel
        case feature
        case executionMode
        case failureCategory
        case durationBucket
    }

    public init(from decoder: Decoder) throws {
        try AnalyticsCodableAllowlist.rejectUnknownKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let clientEventId = try container.decode(UUID.self, forKey: .clientEventId)
        let eventType = try container.decode(AnalyticsEventType.self, forKey: .eventType)
        let occurredAtText = try container.decode(String.self, forKey: .occurredAt)
        guard let occurredAt = AnalyticsWireDate.date(from: occurredAtText) else {
            throw DecodingError.dataCorruptedError(
                forKey: .occurredAt,
                in: container,
                debugDescription: "occurredAt must be a UTC ISO-8601 timestamp"
            )
        }
        try self.init(
            clientEventId: clientEventId,
            eventType: eventType,
            occurredAt: occurredAt,
            surface: try container.decode(AnalyticsSurface.self, forKey: .surface),
            appVersion: try container.decode(String.self, forKey: .appVersion),
            osVersion: try container.decode(String.self, forKey: .osVersion),
            acquisitionChannel: try container.decodeIfPresent(
                AnalyticsAcquisitionChannel.self,
                forKey: .acquisitionChannel
            ),
            feature: try container.decodeIfPresent(AnalyticsFeature.self, forKey: .feature),
            executionMode: try container.decodeIfPresent(
                AnalyticsExecutionMode.self,
                forKey: .executionMode
            ),
            failureCategory: try container.decodeIfPresent(
                AnalyticsFailureCategory.self,
                forKey: .failureCategory
            ),
            durationBucket: try container.decodeIfPresent(
                AnalyticsDurationBucket.self,
                forKey: .durationBucket
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        guard dimensionsAreAllowed else {
            throw AnalyticsModelError.invalidDimensions(eventType)
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientEventId, forKey: .clientEventId)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(AnalyticsWireDate.string(from: occurredAt), forKey: .occurredAt)
        try container.encode(surface, forKey: .surface)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encodeIfPresent(acquisitionChannel, forKey: .acquisitionChannel)
        try container.encodeIfPresent(feature, forKey: .feature)
        try container.encodeIfPresent(executionMode, forKey: .executionMode)
        try container.encodeIfPresent(failureCategory, forKey: .failureCategory)
        try container.encodeIfPresent(durationBucket, forKey: .durationBucket)
    }

    private var dimensionsAreAllowed: Bool {
        let present = DimensionSet(
            acquisitionChannel: acquisitionChannel != nil,
            feature: feature != nil,
            executionMode: executionMode != nil,
            failureCategory: failureCategory != nil,
            durationBucket: durationBucket != nil
        )
        guard eventType.allowedDimensionSets.contains(present) else {
            return false
        }
        if eventType == .purchaseCancelled {
            return failureCategory == .cancelled
        }
        return true
    }
}

public struct AnalyticsUploadRequest: Codable, Equatable, Sendable {
    public let installationId: UUID
    public let events: [AnalyticsEvent]

    public init(installationId: UUID, events: [AnalyticsEvent]) {
        self.installationId = installationId
        self.events = events
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case installationId
        case events
    }

    public init(from decoder: Decoder) throws {
        try AnalyticsCodableAllowlist.rejectUnknownKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installationId = try container.decode(UUID.self, forKey: .installationId)
        events = try container.decode([AnalyticsEvent].self, forKey: .events)
    }
}

public struct AnalyticsUploadResponse: Codable, Equatable, Sendable {
    public let accepted: Int
    public let replayed: Int

    public init(accepted: Int, replayed: Int) throws {
        guard accepted >= 0, replayed >= 0 else {
            throw AnalyticsModelError.invalidResponseCounts
        }
        self.accepted = accepted
        self.replayed = replayed
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accepted
        case replayed
    }

    public init(from decoder: Decoder) throws {
        try AnalyticsCodableAllowlist.rejectUnknownKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accepted: container.decode(Int.self, forKey: .accepted),
            replayed: container.decode(Int.self, forKey: .replayed)
        )
    }
}

public struct AnalyticsEnvironment: Equatable, Sendable {
    public let appVersion: String
    public let osVersion: String

    public init(appVersion: String, osVersion: String) {
        self.appVersion = Self.sanitizedVersion(appVersion)
        self.osVersion = Self.sanitizedVersion(osVersion)
    }

    static func isSafeVersion(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 32
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-_")
                    .contains($0)
            }
    }

    private static func sanitizedVersion(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz.-_"
        )
        let filtered = String(value.unicodeScalars.filter(allowed.contains).prefix(32))
        return filtered.isEmpty ? "unknown" : filtered
    }
}

private struct DimensionSet: Hashable {
    let acquisitionChannel: Bool
    let feature: Bool
    let executionMode: Bool
    let failureCategory: Bool
    let durationBucket: Bool

    static let none = Self(
        acquisitionChannel: false,
        feature: false,
        executionMode: false,
        failureCategory: false,
        durationBucket: false
    )
}

private extension AnalyticsEventType {
    var allowedDimensionSets: Set<DimensionSet> {
        switch self {
        case .firstOpen, .inviteOpened:
            return [
                .none,
                DimensionSet(
                    acquisitionChannel: true,
                    feature: false,
                    executionMode: false,
                    failureCategory: false,
                    durationBucket: false
                )
            ]
        case .aiFeatureStarted:
            return [
                DimensionSet(
                    acquisitionChannel: false,
                    feature: true,
                    executionMode: true,
                    failureCategory: false,
                    durationBucket: false
                )
            ]
        case .aiFeatureSucceeded:
            return [
                DimensionSet(
                    acquisitionChannel: false,
                    feature: true,
                    executionMode: true,
                    failureCategory: false,
                    durationBucket: true
                )
            ]
        case .aiFeatureFailed:
            return [
                DimensionSet(
                    acquisitionChannel: false,
                    feature: true,
                    executionMode: true,
                    failureCategory: true,
                    durationBucket: true
                )
            ]
        case .sessionStarted,
             .keyboardActivated,
             .purchaseViewed,
             .purchaseStarted,
             .referralShared:
            return [.none]
        case .purchaseCancelled:
            return [
                DimensionSet(
                    acquisitionChannel: false,
                    feature: false,
                    executionMode: false,
                    failureCategory: true,
                    durationBucket: false
                )
            ]
        }
    }
}

enum AnalyticsCanonicalJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

enum AnalyticsWireDate {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }

    private static var formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

private enum AnalyticsCodableAllowlist {
    static func rejectUnknownKeys(
        in decoder: Decoder,
        allowed: Set<String>
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        if let unknown = container.allKeys.first(where: { !allowed.contains($0.stringValue) }) {
            throw AnalyticsModelError.unknownField(unknown.stringValue)
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

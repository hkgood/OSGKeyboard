// FlowAck.swift
// OSGKeyboard · Shared

import Foundation

/// Keyboard delivery acknowledgement. It carries the echoed result identity,
/// generation, and revision; matching identity/revision releases that terminal result.
public struct FlowAck: Codable, Equatable, Sendable {
    public enum DeliveryOutcome: String, Codable, Sendable {
        case replaced
        case appended
        case rejected
    }

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let hostGeneration: String?
    public let revision: Int64?
    public let deliveryOutcome: DeliveryOutcome?
    public let consumedAt: TimeInterval

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        hostGeneration: String? = nil,
        revision: Int64? = nil,
        deliveryOutcome: DeliveryOutcome? = nil,
        consumedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.hostGeneration = hostGeneration
        self.revision = revision
        self.deliveryOutcome = deliveryOutcome
        self.consumedAt = consumedAt
    }
}

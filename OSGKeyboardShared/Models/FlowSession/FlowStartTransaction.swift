// FlowStartTransaction.swift
// OSGKeyboard · Shared

import Foundation

public struct FlowStartTransaction: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case issued
        case starting
        case recording
        case terminal
    }

    public let sessionID: UUID
    public let utteranceID: UUID
    public let deadlineAt: TimeInterval
    public let phase: Phase
    public let updatedAt: TimeInterval

    public init(
        sessionID: UUID,
        utteranceID: UUID,
        deadlineAt: TimeInterval,
        phase: Phase,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.sessionID = sessionID
        self.utteranceID = utteranceID
        self.deadlineAt = deadlineAt
        self.phase = phase
        self.updatedAt = updatedAt
    }
}

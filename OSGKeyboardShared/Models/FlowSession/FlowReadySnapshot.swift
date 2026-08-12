// FlowReadySnapshot.swift
// OSGKeyboard · Shared

import Foundation

public struct FlowReadySnapshot: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case ready
        case noSession
        case starting
        case audioEngineNotLive
        case waitingForAudioProof
        case recording
        case processing
        case awaitingDelivery
        case permissionMissing
        case appGroupUnavailable
        case hostLost
        case error
    }

    public let protocolVersion: Int
    public let sessionId: UUID?
    public let ready: Bool
    public let reason: Reason
    public let heartbeatAt: TimeInterval
    public let readyAt: TimeInterval?
    public let audioProofAt: TimeInterval?
    public let engineMode: String
    public let localeId: String
    public let busyUtteranceId: UUID?
    public let sessionExpiresAt: TimeInterval?
    /// Host process generation that wrote this snapshot. A snapshot whose
    /// generation no longer matches `FlowSessionKeys.hostGeneration` was
    /// written by a dead process and is void immediately — no need to wait
    /// out the heartbeat-zombie window. Optional for wire compatibility with
    /// snapshots written before this field existed.
    public let hostGeneration: String?

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID?,
        ready: Bool,
        reason: Reason,
        heartbeatAt: TimeInterval = Date().timeIntervalSince1970,
        readyAt: TimeInterval? = nil,
        audioProofAt: TimeInterval? = nil,
        engineMode: String,
        localeId: String,
        busyUtteranceId: UUID? = nil,
        sessionExpiresAt: TimeInterval? = nil,
        hostGeneration: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.ready = ready
        self.reason = reason
        self.heartbeatAt = heartbeatAt
        self.readyAt = readyAt
        self.audioProofAt = audioProofAt
        self.engineMode = engineMode
        self.localeId = localeId
        self.busyUtteranceId = busyUtteranceId
        self.sessionExpiresAt = sessionExpiresAt
        self.hostGeneration = hostGeneration
    }
}

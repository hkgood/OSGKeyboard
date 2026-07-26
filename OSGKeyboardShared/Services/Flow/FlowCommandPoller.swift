// FlowCommandPoller.swift
// OSGKeyboard · Shared
//
// Dedupes and validates keyboard → host Flow commands before dispatch.

import Foundation

/// Host-side command polling state: fingerprint dedup + monotonic seq gate.
public struct FlowCommandPoller: Sendable, Equatable {
    public enum RejectReason: Equatable, Sendable {
        case staleSession
        case seqNotIncreasing
    }

    public private(set) var lastCommandFingerprint = ""
    public private(set) var lastHandledCommandSeq: Int64 = 0

    public init() {}

    /// Stable fingerprint for deduping repeated App Group reads.
    public static func fingerprint(for command: FlowCommand) -> String {
        "\(command.sessionId.uuidString)|\(command.utteranceId.uuidString)|" +
        "\(command.action.rawValue)|\(command.commandSeq)"
    }

    /// Returns the command when it is new since the last poll; clears fingerprint when nil.
    public mutating func consumeIfNew(_ command: FlowCommand?) -> FlowCommand? {
        guard let command else {
            lastCommandFingerprint = ""
            return nil
        }
        let fingerprint = Self.fingerprint(for: command)
        guard fingerprint != lastCommandFingerprint else { return nil }
        lastCommandFingerprint = fingerprint
        return command
    }

    /// Validates session id + monotonic seq before handling.
    public func validate(
        command: FlowCommand,
        activeSessionId: UUID?
    ) -> RejectReason? {
        guard let activeSessionId, command.sessionId == activeSessionId else {
            return .staleSession
        }
        guard command.commandSeq > lastHandledCommandSeq else {
            return .seqNotIncreasing
        }
        return nil
    }

    /// Records a successfully handled command seq.
    public mutating func markHandled(_ command: FlowCommand) {
        lastHandledCommandSeq = command.commandSeq
    }

    /// Resets dedup + seq state when a Flow session ends or restarts.
    public mutating func reset() {
        lastCommandFingerprint = ""
        lastHandledCommandSeq = 0
    }
}

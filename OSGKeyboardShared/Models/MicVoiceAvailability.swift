// MicVoiceAvailability.swift
// OSGKeyboard · Shared
//
// Single source of truth for keyboard mic color, hint text, and tap behavior.

import Foundation

/// Whether the keyboard mic can start a Flow utterance right now.
public enum MicVoiceAvailability: Equatable, Sendable {
    /// Green — tap records immediately without opening the host app.
    case ready
    /// Orange — voice input blocked; see `Reason` for hint copy.
    case unavailable(Reason)
    /// Red — user is actively recording.
    case recording
    /// White — waiting for ASR / cloud polish after stop.
    case processing

    public enum Reason: Equatable, Sendable {
        case missingAPIKey
        case hostNotReady
        case noFullAccess
        case appGroupUnavailable
        /// User tapped mic; host app jump in progress, awaiting ready contract.
        case preparingSession
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

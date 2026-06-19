// FlowSessionKeys.swift
// OSGKeyboard · Shared
//
// App Group keys for TypeWhisper-style Flow sessions between the
// keyboard extension and the host app (Session Owner).

import Foundation

public enum FlowSessionKeys {
    public static let flowSessionActive = "flow.flowSessionActive"
    public static let flowSessionExpires = "flow.flowSessionExpires"
    public static let flowHeartbeat = "flow.flowHeartbeat"
    public static let keyboardRecordingState = "flow.keyboardRecordingState"
    public static let transcriptionLanguage = "flow.transcriptionLanguage"
    public static let transcriptionResult = "flow.transcriptionResult"
    public static let transcriptionError = "flow.transcriptionError"
    public static let audioLevels = "flow.audioLevels"

    /// Heartbeat older than this implies the host app was killed.
    public static let heartbeatStaleInterval: TimeInterval = 3

    /// Default Flow session length when started from the keyboard.
    public static let defaultSessionDuration: TimeInterval = 480

    /// Maximum duration for a single keyboard utterance.
    public static let maxUtteranceDuration: TimeInterval = 60

    public enum RecordingState: String, Sendable, Equatable {
        case idle
        case recording
        case stopped
        case processing
        case aborted
    }
}

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
    /// Soft warning when polish failed but raw transcript was delivered.
    public static let transcriptionPolishWarning = "flow.transcriptionPolishWarning"
    public static let transcriptionError = "flow.transcriptionError"
    public static let audioLevels = "flow.audioLevels"

    /// Heartbeat older than this while the host is foreground → likely killed.
    public static let heartbeatStaleInterval: TimeInterval = 3

    /// Default Flow session length when started from the keyboard.
    public static let defaultSessionDuration: TimeInterval = 480

    /// Maximum duration for a single keyboard utterance (3.5 minutes).
    public static let maxUtteranceDuration: TimeInterval = 210

    /// Host polls for pipelined ASR drain after mic stop. Pipelining usually
    /// finishes most chunks during recording; this is a soft deadline before
    /// blocking on `asrTask.value` (which waits until the pipeline exits).
    public static let localASRWaitTimeout: TimeInterval = 120
    public static let cloudASRWaitTimeout: TimeInterval = 120

    /// Keyboard watchdog after the user stops recording (not utterance max length).
    /// Must cover worst-case post-stop backlog: remaining SpeechAnalyzer chunks
    /// plus cloud LLM polish (see `PolishingService.effectiveTimeout` cap).
    ///
    /// As of v0.2.0 the local engine uses iOS `SpeechAnalyzer` only, so the
    /// previous Qwen3-specific timeout (240 s) collapses into the shared
    /// local path. We keep `localASRBackend` on the signature for symmetry
    /// with other shared helpers.
    public static func keyboardResultTimeout(
        engineMode: String,
        localASRBackend: LocalASRBackend
    ) -> TimeInterval {
        if engineMode == "local" {
            return 180
        }
        return 240
    }

    public enum RecordingState: String, Sendable, Equatable {
        case idle
        case recording
        case stopped
        case processing
        case aborted
    }
}

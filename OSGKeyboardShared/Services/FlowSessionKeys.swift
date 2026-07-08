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
    /// Host-published contract: capture + polling idle and able to accept utterances.
    public static let flowHostReady = "flow.flowHostReady"
    /// Wall-clock timestamp paired with `flowHostReady` (seconds since 1970).
    public static let flowHostReadyAt = "flow.flowHostReadyAt"
    public static let keyboardRecordingState = "flow.keyboardRecordingState"
    public static let transcriptionLanguage = "flow.transcriptionLanguage"
    public static let transcriptionResult = "flow.transcriptionResult"
    /// Live pipelined ASR partial for the keyboard transcript line.
    public static let transcriptionPartial = "flow.transcriptionPartial"
    /// Soft warning when polish failed but raw transcript was delivered.
    public static let transcriptionPolishWarning = "flow.transcriptionPolishWarning"
    public static let transcriptionError = "flow.transcriptionError"
    /// Structured kind paired with `transcriptionError` for keyboard UI.
    public static let transcriptionErrorKind = "flow.transcriptionErrorKind"
    public static let audioLevels = "flow.audioLevels"
    /// Bundle id of the app that opened `osgkeyboard://startflow` (scheme D).
    public static let pendingHostBundleId = "flow.pendingHostBundleId"
    /// Wall-clock timestamp of the last utterance completion or session start.
    public static let lastActivityAt = "flow.lastActivityAt"

    /// Heartbeat older than this → host is not actively reachable for recording.
    public static let heartbeatStaleInterval: TimeInterval = 3

    /// `flowHostReadyAt` must be within this window of the latest heartbeat.
    public static let hostReadyMaxHeartbeatSkew: TimeInterval = 5

    /// Session flag still set but heartbeat older than this → host process is
    /// dead (force-quit, reboot). Keyboard / host should clear persisted state.
    public static let heartbeatZombieInterval: TimeInterval = 60

    /// After mic stop, fail fast when the host heartbeat is gone longer than this.
    public static let keyboardHostDisconnectFailFast: TimeInterval = 15

    /// Legacy fixed session length — prefer `FlowSessionPolicy.sessionDuration()`.
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
    public static func keyboardResultTimeout(engineMode: String) -> TimeInterval {
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

    /// Structured host → keyboard transcription failure kind.
    public enum TranscriptionErrorKind: String, Sendable, Equatable {
        case noSpeech
        case recognitionInterrupted
        case audioUnavailable
        case asrFailed
        case generic
    }
}

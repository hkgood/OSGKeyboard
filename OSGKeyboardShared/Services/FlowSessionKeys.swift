// FlowSessionKeys.swift
// OSGKeyboard · Shared
//
// App Group keys for TypeWhisper-style Flow sessions between the
// keyboard extension and the host app (Session Owner).

import Foundation

public enum FlowSessionKeys {
    public static let flowCommandPayload = "flow.commandPayload.v1"
    public static let flowCommandJournalPayload = "flow.commandJournalPayload.v2"
    public static let flowResultPayload = "flow.resultPayload.v1"
    public static let flowAckPayload = "flow.ackPayload.v1"
    public static let pendingKeyboardUtteranceId = "flow.pendingKeyboardUtteranceId.v1"
    public static let flowReadyPayload = "flow.readyPayload.v1"
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
    /// Wall-clock of the last keyboard→`startflow` PiP arm attempt (debounce re-jumps).
    public static let lastPiPArmAttemptAt = "flow.lastPiPArmAttemptAt.v1"
    /// Minimum gap between proactive / clipboard startflow jumps.
    public static let pipArmCooldown: TimeInterval = 45
    /// Wall-clock timestamp of the last utterance completion or session start.
    public static let lastActivityAt = "flow.lastActivityAt"
    /// One-shot token rotated by every host-process launch. State written by
    /// a previous generation is void by definition — a fresh launch proves the
    /// previous process is dead, whether or not its `applicationWillTerminate`
    /// cleanup ever ran (it does NOT run when a suspended app is force-quit).
    public static let hostGeneration = "flow.hostGeneration.v1"
    /// Host is mid heavy work (Rime/CLM/ASR). Extension should stay on voice
    /// and skip typing engine prepare until this clears.
    public static let hostHeavy = "flow.hostHeavy.v1"
    /// Wall-clock timestamp paired with `hostHeavy` (seconds since 1970).
    /// Lets the keyboard ignore a sticky flag left behind when the host died
    /// mid-warmup without ever clearing App Group state.
    public static let hostHeavyAt = "flow.hostHeavyAt.v1"

    /// `hostHeavy` older than this is treated as stale (host likely jetsammed
    /// or force-quit before `setHostHeavy(false)`). Rime/CLM/ASR bursts are
    /// expected well under this window.
    public static let hostHeavyMaxAge: TimeInterval = 120

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
    public static let localASRWaitTimeout: TimeInterval = 8
    public static let cloudASRWaitTimeout: TimeInterval = 12
    public static let batchASRFallbackTimeout: TimeInterval = 8

    /// Hard cap on a single LLM polish request. `PolishingService`'s scaled
    /// per-request timeout clamps to this value, so it participates in the
    /// keyboard-watchdog budget below.
    public static let maxPolishTimeout: TimeInterval = 35

    /// Extra slack for result serialization, cross-process propagation, and
    /// the host's own polling cadence.
    public static let resultDeliveryMargin: TimeInterval = 5

    public static func polishTimeout(forCharacterCount count: Int) -> TimeInterval {
        if count <= 150 { return 10 }
        if count <= 500 { return 20 }
        return maxPolishTimeout
    }

    /// Keyboard watchdog after the user stops recording (not utterance max
    /// length). Derived from the host-side budget so it always outlasts the
    /// host's worst case (ASR drain wait + polish cap + margin) — hand-tuned
    /// constants drifted below the real host maximum, making the keyboard
    /// report a timeout for transcriptions that were still going to succeed.
    public static func keyboardResultTimeout(engineMode: String) -> TimeInterval {
        let asrWait = engineMode == "local" ? localASRWaitTimeout : cloudASRWaitTimeout
        return asrWait + batchASRFallbackTimeout + maxPolishTimeout + resultDeliveryMargin
    }

    public enum RecordingState: String, Sendable, Equatable {
        case idle
        case recording
        case stopped
        case processing
        case aborted
    }

    /// Structured host → keyboard transcription failure kind.
    public enum TranscriptionErrorKind: String, Sendable, Equatable, Codable {
        case noSpeech
        case recognitionInterrupted
        case audioUnavailable
        case asrFailed
        case generic
    }
}

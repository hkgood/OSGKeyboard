// FlowKeyboardPolicies.swift
// OSGKeyboard · Shared
//
// Pure decision helpers extracted from KeyboardFlowCoordinator so mic
// warming / host re-adopt / result matching stay hermetic and regression-tested.

import Foundation

// MARK: - Host warming (orange "starting" vs busy)

public enum FlowKeyboardHostWarming {
    /// Host is mid-utterance — never treat as "still starting".
    public static func isHostBusy(reason: FlowReadySnapshot.Reason?) -> Bool {
        reason == .recording || reason == .processing || reason == .awaitingDelivery
    }

    /// Keep the mic green after the session has already proven ready.
    ///
    /// Inter-utterance PiP flaps (mic release, ack lag, brief `reason=.starting`)
    /// used to flash yellow「正在启动画中画」even though Picture in Picture was
    /// already running. Hold ready through those windows; real cold starts still
    /// go through `isHostWarming` while `sessionProvenReady` is false.
    public static func shouldHoldReady(
        hostReady: Bool,
        hostBusy: Bool,
        sessionActive: Bool,
        sessionProvenReady: Bool,
        isPendingFlowStart: Bool,
        snapshotReason: FlowReadySnapshot.Reason?
    ) -> Bool {
        guard !hostReady,
              sessionProvenReady,
              sessionActive,
              !isPendingFlowStart else {
            return false
        }
        // After insert the host may still publish awaitingDelivery until it
        // consumes the ack — that is not a PiP restart.
        if hostBusy {
            return snapshotReason == .awaitingDelivery
        }
        return true
    }

    /// Session lives but ready contract is not fresh — keep mic orange (wait)
    /// instead of launching another cold start.
    ///
    /// `withinReadyGrace` is intentionally unused for warming: a recent ready
    /// must hold green via `shouldHoldReady`, not flash preparingSession.
    public static func isHostWarming(
        hostReady: Bool,
        hostBusy: Bool,
        sessionActive: Bool,
        hostReachable: Bool,
        isPendingFlowStart: Bool,
        withinReadyGrace: Bool,
        snapshotReason: FlowReadySnapshot.Reason?
    ) -> Bool {
        _ = withinReadyGrace
        return !hostReady
            && !hostBusy
            && sessionActive
            && (
                hostReachable
                    || isPendingFlowStart
                    || snapshotReason == .starting
            )
    }
}

// MARK: - Re-adopt busy host after extension jetsam

public enum FlowKeyboardAdoptBusyAction: Equatable, Sendable {
    case none
    case clearStickyProcessing
    case adoptRecording(sessionId: UUID, utteranceId: UUID)
    case adoptProcessing(sessionId: UUID, utteranceId: UUID)
}

public enum FlowKeyboardAdoptBusyPolicy {
    public static func decide(
        snapshot: FlowReadySnapshot?,
        currentHostGeneration: String?,
        isFlowRecording: Bool,
        isAwaitingFlowResult: Bool,
        lastConsumedUtteranceId: UUID?,
        lastStoppedUtteranceId: UUID?
    ) -> FlowKeyboardAdoptBusyAction {
        guard let snapshot, let sessionId = snapshot.sessionId else { return .none }

        if let snapGen = snapshot.hostGeneration,
           let liveGen = currentHostGeneration,
           snapGen != liveGen {
            return .none
        }

        if snapshot.reason != .recording, snapshot.reason != .processing {
            return .clearStickyProcessing
        }

        switch snapshot.reason {
        case .recording:
            guard !isFlowRecording else { return .none }
            guard !isAwaitingFlowResult else { return .none }
            guard let busyId = snapshot.busyUtteranceId else { return .none }
            guard busyId != lastConsumedUtteranceId else { return .none }
            guard busyId != lastStoppedUtteranceId else { return .none }
            return .adoptRecording(sessionId: sessionId, utteranceId: busyId)
        case .processing:
            guard !isAwaitingFlowResult else { return .none }
            guard let busyId = snapshot.busyUtteranceId else { return .none }
            guard busyId != lastConsumedUtteranceId else { return .none }
            return .adoptProcessing(sessionId: sessionId, utteranceId: busyId)
        default:
            return .none
        }
    }
}

// MARK: - Result matching

public enum FlowKeyboardResultMatcher {
    public static func matchingResult(
        latest: FlowResult?,
        activeSessionId: UUID?,
        currentUtteranceId: UUID?,
        currentHostGeneration: String? = nil
    ) -> FlowResult? {
        guard let latest, let activeSessionId, let currentUtteranceId else { return nil }
        if let resultGeneration = latest.hostGeneration,
           let currentHostGeneration,
           resultGeneration != currentHostGeneration {
            return nil
        }
        guard latest.sessionId == activeSessionId,
              latest.utteranceId == currentUtteranceId else {
            return nil
        }
        return latest
    }

    public static func isTerminalFailure(_ result: FlowResult) -> Bool {
        result.status == .error || result.status == .timeout || result.status == .aborted
    }
}

// MARK: - Host command gate

public enum FlowCommandGateDecision: Equatable, Sendable {
    case accept
    case rejectWrongSession
    case rejectStaleSeq
}

public enum FlowCommandGatekeeper {
    public static func decide(
        commandSessionId: UUID,
        commandSeq: Int64,
        activeSessionId: UUID?,
        lastHandledCommandSeq: Int64
    ) -> FlowCommandGateDecision {
        guard let activeSessionId, commandSessionId == activeSessionId else {
            return .rejectWrongSession
        }
        guard commandSeq > lastHandledCommandSeq else {
            return .rejectStaleSeq
        }
        return .accept
    }
}

// MARK: - Orphan recording before host start

public enum FlowOrphanRecordingDecision: Equatable, Sendable {
    case none
    case clearZombieSession
    case clearOrphanedRecording(FlowSessionKeys.RecordingState)
}

public enum FlowOrphanRecordingReconciler {
    public static func decide(
        isHostStale: Bool,
        isActive: Bool,
        recordingState: FlowSessionKeys.RecordingState
    ) -> FlowOrphanRecordingDecision {
        if isHostStale {
            return .clearZombieSession
        }
        guard !isActive else { return .none }
        switch recordingState {
        case .recording, .stopped, .processing:
            return .clearOrphanedRecording(recordingState)
        case .idle, .aborted:
            return .none
        }
    }
}

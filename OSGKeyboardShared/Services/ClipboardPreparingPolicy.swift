// ClipboardPreparingPolicy.swift
// OSGKeyboard · Shared
//
// Pure decisions for clipboard「准备录音…」so paste-alert restore / double-start
// / host-failure recovery stay hermetic and regression-tested.

import Foundation

// MARK: - Restore after paste-alert / cold-start recreate

public enum ClipboardRestoreAction: Equatable, Sendable {
    /// Mid-flight claim exists — reattach preparing/recording, never pressBegan again.
    case awaitExistingStart
    /// Intent exists but start is not issued — resume acquisition / host warm-up automatically.
    case resumeIntent
    /// Already in a live clipboard phase — only refresh UI / recover.
    case refreshOnly
}

/// Whether a clipboard intent may start now or must warm the host first.
public enum ClipboardHostGateAction: Equatable, Sendable {
    case startRecordingNow
    case openHostColdStart
    case waitForHost
    case ignore
}

/// Mic chrome while a clipboard round is live.
public enum ClipboardMicChrome: Equatable, Sendable {
    /// Grey / spinner / tappable to cancel — acquiring paste or waiting for host.
    case preparingCancelable
    /// Blue recording chrome + side captions.
    case recordingBlue
    /// Not a clipboard recording chrome state.
    case none
}

public enum ClipboardPreparingPolicy: Sendable {

    public static func restoreAction(
        hasStartIssued: Bool,
        phase: ClipboardPreparingPhase
    ) -> ClipboardRestoreAction {
        switch phase {
        case .idle, .denied, .error:
            return hasStartIssued ? .awaitExistingStart : .resumeIntent
        case .requestingPermissions, .recording, .processing:
            return .refreshOnly
        }
    }

    /// Map the shared mic handoff decision onto the auto-resuming clipboard intent.
    public static func hostGateAction(
        micPressAction: FlowMicPressAction
    ) -> ClipboardHostGateAction {
        switch micPressAction {
        case .startRecording:
            return .startRecordingNow
        case .openHostColdStart:
            return .openHostColdStart
        case .waitForHostReady:
            // The coordinator keeps the same intent and auto-records once ready.
            return .waitForHost
        case .ignore:
            return .ignore
        }
    }

    public static func micChrome(
        isClipboardUtterance: Bool,
        phase: ClipboardPreparingPhase,
        awaitingHostConfirm: Bool
    ) -> ClipboardMicChrome {
        guard isClipboardUtterance else { return .none }
        switch phase {
        case .requestingPermissions:
            return .preparingCancelable
        case .recording:
            return awaitingHostConfirm ? .preparingCancelable : .recordingBlue
        case .processing:
            return .preparingCancelable
        case .idle, .denied, .error:
            return .none
        }
    }

    // MARK: - Stop while preparing

    public static func stopWhilePreparing(
        awaitingHostConfirm: Bool
    ) -> ClipboardPreparingStopAction {
        awaitingHostConfirm ? .abortPreparing : .requestStop
    }

    // MARK: - Host moved on while preparing

    public static func recoverWhilePreparing(
        awaitingHostConfirm: Bool,
        currentUtteranceId: UUID?,
        hostBusyUtteranceId: UUID?,
        hostReason: ClipboardHostBusyReason?,
        hasTerminalFailureForCurrent: Bool
    ) -> ClipboardPreparingRecoverAction {
        guard awaitingHostConfirm else { return .none }

        if hasTerminalFailureForCurrent {
            return .abortForHostFailure
        }

        guard let hostReason, let busyId = hostBusyUtteranceId else {
            return .none
        }

        switch hostReason {
        case .recording:
            if busyId == currentUtteranceId {
                return .confirmRecording
            }
            return .adoptSibling(busyId)
        case .processing:
            if busyId == currentUtteranceId {
                return .wait
            }
            return .adoptSibling(busyId)
        }
    }

    // MARK: - Ensure at most one startRecording

    public static func ensureStartAction(
        issuedUtteranceId: UUID?,
        isFlowRecording: Bool,
        currentUtteranceId: UUID?,
        hostBusyUtteranceId: UUID?,
        hostReason: ClipboardHostBusyReason?,
        hostReadyWithSession: Bool
    ) -> ClipboardEnsureStartAction {
        guard let issued = issuedUtteranceId else { return .none }

        if let busyId = hostBusyUtteranceId, let hostReason {
            switch hostReason {
            case .recording, .processing:
                return .adoptBusy(busyId, hostReason)
            }
        }

        if isFlowRecording, currentUtteranceId == issued {
            return .alreadyInFlight
        }

        if hostReadyWithSession {
            return .writeStart(issued)
        }

        return .waitForHost
    }
}

/// Keyboard phase subset relevant to clipboard prepare/restore.
public enum ClipboardPreparingPhase: Equatable, Sendable {
    case idle
    case denied
    case error
    case requestingPermissions
    case recording
    case processing
}

public enum ClipboardPreparingStopAction: Equatable, Sendable {
    case abortPreparing
    case requestStop
}

public enum ClipboardHostBusyReason: Equatable, Sendable {
    case recording
    case processing
}

public enum ClipboardPreparingRecoverAction: Equatable, Sendable {
    case none
    case wait
    case confirmRecording
    case adoptSibling(UUID)
    case abortForHostFailure
}

public enum ClipboardEnsureStartAction: Equatable, Sendable {
    case none
    case alreadyInFlight
    case adoptBusy(UUID, ClipboardHostBusyReason)
    case writeStart(UUID)
    case waitForHost
}

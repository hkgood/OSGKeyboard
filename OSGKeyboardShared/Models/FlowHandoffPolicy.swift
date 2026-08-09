// FlowHandoffPolicy.swift
// OSGKeyboard · Shared
//
// Pure decision helpers for keyboard → host handoff. Keeps "session still
// alive, ready contract briefly missing" from being treated as a cold start.

import Foundation

/// Action the keyboard should take when the user presses the mic.
public enum FlowMicPressAction: Equatable, Sendable {
    case startRecording
    /// Session is alive (or was very recently); poll for ready, then optionally record.
    case waitForHostReady(recordWhenReady: Bool)
    /// Host process is gone / no session — open `osgkeyboard://startflow`.
    case openHostColdStart
    case ignore
}

/// Whether the host app should show the cold-start overlay for a `startflow`.
public enum FlowColdStartOverlayDecision: Equatable, Sendable {
    /// Do not set handoff flags or show preparing/ready UI.
    case silence
    /// Show preparing and run the cold-start / recovery path.
    case present
}

public enum FlowHandoffPolicy {
    /// Low-profile PiP is armed proactively whenever the keyboard appears.
    /// This opens the lightweight host only when its ready contract is absent;
    /// capture, ASR and model warm-up remain lazy until an actual mic press.
    public static let allowsProactiveHostAutoLaunch = true

    /// Samples of "host truly dead" required before a cold-start jump is allowed
    /// from a mic-driven ready-wait recovery. Idle opens must never cold-start.
    /// Mic press uses `shouldOpenHostColdStart` directly.
    public static let coldStartDeadSampleThreshold = 2

    /// True when the session contract still implies a living (or recoverable)
    /// host — so a transient `ready=false` must wait, not jump.
    public static func shouldTreatHostAsAlive(
        sessionActive: Bool,
        hostReachable: Bool,
        hostStale: Bool,
        withinReadyGrace: Bool
    ) -> Bool {
        if hostStale { return false }
        guard sessionActive else { return false }
        // Reachable heartbeat, or a recent ready sample, means the process is
        // still ours — finalize races often look like hostNotReady for one frame.
        if hostReachable || withinReadyGrace { return true }
        // Session flag still valid and not past the zombie window: prefer wait.
        return true
    }

    /// Whether `osgkeyboard://startflow` is justified for the current host state.
    public static func shouldOpenHostColdStart(
        sessionActive: Bool,
        hostReachable: Bool,
        hostStale: Bool,
        withinReadyGrace: Bool
    ) -> Bool {
        !shouldTreatHostAsAlive(
            sessionActive: sessionActive,
            hostReachable: hostReachable,
            hostStale: hostStale,
            withinReadyGrace: withinReadyGrace
        )
    }

    /// Proactive keyboard-open PiP arm. Returns false when the host is already
    /// ready, warming, busy, or a recent startflow is still in cooldown —
    /// so Voice-tab / appear noise cannot re-jump to the app.
    ///
    /// `heartbeatStaleness`: seconds since last host heartbeat (`nil` = never).
    /// A lingering `sessionActive` after force-quit must still allow arm once the
    /// heartbeat is clearly gone — without treating brief switcher flaps as death.
    public static let proactiveUnreachableArmGrace: TimeInterval = 8

    public static func shouldProactivePiPArm(
        hostReady: Bool,
        snapshotReason: FlowReadySnapshot.Reason?,
        sessionActive: Bool,
        hostReachable: Bool,
        hostStale: Bool,
        withinReadyGrace: Bool,
        inCooldown: Bool,
        heartbeatStaleness: TimeInterval? = nil
    ) -> Bool {
        guard !hostReady, !inCooldown else { return false }
        if let snapshotReason {
            switch snapshotReason {
            case .recording, .processing, .awaitingDelivery, .starting,
                 .waitingForAudioProof, .audioEngineNotLive:
                return false
            case .ready, .noSession, .permissionMissing, .appGroupUnavailable,
                 .hostLost, .error:
                break
            }
        }
        // Force-quit leaves sessionActive=true until the 60s zombie window.
        // If heartbeat has been gone long enough, arm once (cooldown still applies).
        if sessionActive,
           !hostReachable,
           !hostStale,
           let staleness = heartbeatStaleness,
           staleness >= proactiveUnreachableArmGrace {
            return true
        }
        return shouldOpenHostColdStart(
            sessionActive: sessionActive,
            hostReachable: hostReachable,
            hostStale: hostStale,
            withinReadyGrace: withinReadyGrace
        )
    }

    /// Mic-press routing shared by the keyboard coordinator and unit tests.
    public static func micPressAction(
        availability: MicVoiceAvailability,
        sessionActive: Bool,
        hostReachable: Bool,
        hostStale: Bool,
        withinReadyGrace: Bool
    ) -> FlowMicPressAction {
        switch availability {
        case .ready:
            return .startRecording
        case .recording, .processing:
            return .ignore
        case .unavailable(.missingAPIKey),
             .unavailable(.noFullAccess),
             .unavailable(.appGroupUnavailable),
             .unavailable(.onboardingIncomplete):
            // Caller surfaces the specific error UI / host jump.
            return .ignore
        case .unavailable(.preparingSession):
            // Session is warming — never cold-start; wait then record.
            return .waitForHostReady(recordWhenReady: true)
        case .unavailable(.hostNotReady):
            if shouldTreatHostAsAlive(
                sessionActive: sessionActive,
                hostReachable: hostReachable,
                hostStale: hostStale,
                withinReadyGrace: withinReadyGrace
            ) {
                return .waitForHostReady(recordWhenReady: true)
            }
            return .openHostColdStart
        }
    }

    /// Host-app gate: a `startflow` against an already-healthy (or busy) session
    /// must not flash "Voice is ready".
    public static func coldStartOverlayDecision(
        sessionIsActive: Bool,
        hostIsReady: Bool,
        isUtteranceBusy: Bool
    ) -> FlowColdStartOverlayDecision {
        guard sessionIsActive else { return .present }
        if hostIsReady || isUtteranceBusy { return .silence }
        // Active but not ready and not busy — engine recovery may need UI.
        return .present
    }
}

/// Counts consecutive "host truly dead" observations to ignore single-frame races.
public struct FlowColdStartDebouncer: Equatable, Sendable {
    public private(set) var consecutiveDeadSamples: Int = 0

    public init(consecutiveDeadSamples: Int = 0) {
        self.consecutiveDeadSamples = consecutiveDeadSamples
    }

    /// Returns true once enough consecutive dead samples have been seen.
    public mutating func observe(hostTrulyDead: Bool) -> Bool {
        if hostTrulyDead {
            consecutiveDeadSamples += 1
        } else {
            consecutiveDeadSamples = 0
        }
        return consecutiveDeadSamples >= FlowHandoffPolicy.coldStartDeadSampleThreshold
    }

    public mutating func reset() {
        consecutiveDeadSamples = 0
    }
}

// FlowUtteranceEndCoordinator.swift
// OSGKeyboard · Shared
//
// Unified tail-drain + post-roll orchestration after the user stops recording.
// Keeps the mic gate open through silence detection, then a fixed post-roll
// window that does not depend on RMS (captures weak trailing syllables).

import Foundation

/// Outcome of `FlowUtteranceEndCoordinator.awaitTailCapture`.
public struct FlowUtteranceEndTiming: Sendable, Equatable {
    public let endedBySilence: Bool
    public let postRollDurationSeconds: Double

    public init(endedBySilence: Bool, postRollDurationSeconds: Double) {
        self.endedBySilence = endedBySilence
        self.postRollDurationSeconds = postRollDurationSeconds
    }
}

public enum FlowUtteranceEndCoordinator {
    /// Poll interval while waiting for silence / max drain (20 ms).
    public static let pollIntervalNs: UInt64 = 20_000_000

    /// Waits until trailing speech drains (silence or max cap), then sleeps
    /// through a fixed post-roll window so weak tail audio still reaches ASR.
    ///
    /// Callers must keep forwarding PCM from the audio tap while this runs
    /// (gate `.draining` or equivalent).
    public static func awaitTailCapture(
        tracker: FlowCaptureDrainTracker,
        policy: FlowCaptureTailDrainPolicy,
        pollIntervalNs: UInt64 = pollIntervalNs
    ) async -> FlowUtteranceEndTiming {
        var endedBySilence = false
        while true {
            let decision = tracker.shouldFinish(policy: policy)
            if decision.finished {
                endedBySilence = decision.endedBySilence
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: pollIntervalNs)
        }

        let postRoll = await runPostRoll(policy: policy, pollIntervalNs: pollIntervalNs)
        return FlowUtteranceEndTiming(
            endedBySilence: endedBySilence,
            postRollDurationSeconds: postRoll
        )
    }

    private static func runPostRoll(
        policy: FlowCaptureTailDrainPolicy,
        pollIntervalNs: UInt64
    ) async -> Double {
        guard policy.postRollSeconds > 0 else { return 0 }
        let started = Date()
        let deadline = started.addingTimeInterval(policy.postRollSeconds)
        while Date() < deadline {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: pollIntervalNs)
        }
        return max(0, Date().timeIntervalSince(started))
    }
}

// FlowCaptureTailDrain.swift
// OSGKeyboard · Shared
//
// Tail-drain policy and silence tracking for utterance end. After the user
// stops recording, capture keeps forwarding PCM until trailing speech drains
// or a safety timeout elapses (symmetric to pre-roll at utterance start).

import Foundation
import os

/// Tunable tail-drain policy shared by Flow capture and preview dictation.
public struct FlowCaptureTailDrainPolicy: Sendable, Equatable {
    /// RMS below this counts as silence while draining (16 kHz mono Float32).
    public let silenceRMSThreshold: Float
    /// Finish drain after this much continuous silence.
    public let silenceDurationSeconds: TimeInterval
    /// Hard cap so noisy environments cannot stall finalize forever.
    public let maxDrainSeconds: TimeInterval

    public init(
        silenceRMSThreshold: Float,
        silenceDurationSeconds: TimeInterval,
        maxDrainSeconds: TimeInterval
    ) {
        self.silenceRMSThreshold = silenceRMSThreshold
        self.silenceDurationSeconds = silenceDurationSeconds
        self.maxDrainSeconds = maxDrainSeconds
    }

    public static let flowDefault = FlowCaptureTailDrainPolicy(
        silenceRMSThreshold: 0.015,
        silenceDurationSeconds: 0.25,
        maxDrainSeconds: 1.5
    )
}

/// Metrics emitted when tail drain completes (for diagnostics and tests).
public struct FlowCaptureDrainReport: Sendable, Equatable {
    public let drainDurationSeconds: Double
    public let endedBySilence: Bool
    public let tailSampleCount: Int

    public init(
        drainDurationSeconds: Double,
        endedBySilence: Bool,
        tailSampleCount: Int
    ) {
        self.drainDurationSeconds = drainDurationSeconds
        self.endedBySilence = endedBySilence
        self.tailSampleCount = tailSampleCount
    }

    public static let skipped = FlowCaptureDrainReport(
        drainDurationSeconds: 0,
        endedBySilence: false,
        tailSampleCount: 0
    )
}

/// Thread-safe silence tracker used while draining trailing audio.
public final class FlowCaptureDrainTracker: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var drainStartedAt: TimeInterval?
    private var lastAudibleAt: TimeInterval?

    public init() {}

    public func reset() {
        lock.withLock {
            drainStartedAt = nil
            lastAudibleAt = nil
        }
    }

    public func beginDrain(now: TimeInterval = Date().timeIntervalSince1970) {
        lock.withLock {
            drainStartedAt = now
            lastAudibleAt = now
        }
    }

    public func noteAudio(
        samples: [Float],
        policy: FlowCaptureTailDrainPolicy,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard !samples.isEmpty else { return }
        let rms = Self.rms(of: samples)
        lock.withLock {
            guard drainStartedAt != nil else { return }
            if rms >= policy.silenceRMSThreshold {
                lastAudibleAt = now
            }
        }
    }

    public func shouldFinish(
        policy: FlowCaptureTailDrainPolicy,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> (finished: Bool, endedBySilence: Bool) {
        lock.withLock {
            guard let started = drainStartedAt else {
                return (true, false)
            }
            let audible = lastAudibleAt ?? started
            if now - started >= policy.maxDrainSeconds {
                return (true, false)
            }
            if now - audible >= policy.silenceDurationSeconds {
                return (true, true)
            }
            return (false, false)
        }
    }

    public func elapsedSeconds(now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        lock.withLock {
            guard let started = drainStartedAt else { return 0 }
            return max(0, now - started)
        }
    }

    public static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrtf(sum / Float(samples.count))
    }
}

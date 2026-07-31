// FlowUtterancePCMStore.swift
// OSGKeyboard · Shared
//
// Thread-safe rolling buffer of 16 kHz mono utterance PCM for whole-utterance
// batch ASR fallback when pipelined chunking drops weak tail segments.

import Foundation
import os

public final class FlowUtterancePCMStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var samples: [Float] = []
    private let maxSampleCount: Int

    public init(maxSampleCount: Int) {
        self.maxSampleCount = max(1, maxSampleCount)
    }

    public func reset() {
        lock.withLock {
            samples.removeAll(keepingCapacity: false)
        }
    }

    public func append(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            samples.append(contentsOf: chunk)
            if samples.count > maxSampleCount {
                samples.removeFirst(samples.count - maxSampleCount)
            }
        }
    }

    public var sampleCount: Int {
        lock.withLock { samples.count }
    }

    /// Returns accumulated samples and clears the store.
    public func consume() -> [Float] {
        lock.withLock {
            let out = samples
            samples.removeAll(keepingCapacity: false)
            return out
        }
    }
}

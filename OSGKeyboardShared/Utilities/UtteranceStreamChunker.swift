// UtteranceStreamChunker.swift
// OSGKeyboard · Shared
//
// Splits a Flow utterance PCM stream into ASR-sized chunks. When possible,
// extends slightly past the max window to the next pause instead of cutting
// mid-word.

import Foundation

public enum UtteranceStreamChunker {

    /// Yields chunks as audio arrives; the final chunk is marked `isLast`.
    public static func chunks(
        from stream: AsyncStream<AudioBufferSnapshot>,
        config: FlowUtteranceChunkConfig = .flowDefault
    ) -> AsyncStream<UtteranceAudioChunk> {
        AsyncStream { continuation in
            let task = Task {
                var buffer: [Float] = []
                let initialCapacity = config.maxChunkSamples(forChunkIndex: 0) + config.pauseExtensionSamples
                buffer.reserveCapacity(initialCapacity)
                var chunkIndex = 0

                func emit(upTo splitEnd: Int, isLast: Bool) {
                    guard splitEnd > 0, splitEnd <= buffer.count else { return }
                    let chunkSamples = Array(buffer[..<splitEnd])
                    continuation.yield(
                        UtteranceAudioChunk(index: chunkIndex, samples: chunkSamples, isLast: isLast)
                    )
                    chunkIndex += 1
                    if splitEnd >= buffer.count {
                        buffer.removeAll(keepingCapacity: true)
                    } else {
                        let overlapStart = max(0, splitEnd - config.overlapSamples)
                        buffer = Array(buffer[overlapStart...])
                    }
                }

                for await snap in stream {
                    if Task.isCancelled { break }
                    guard !snap.samples.isEmpty else { continue }
                    buffer.append(contentsOf: snap.samples)

                    while buffer.count >= config.maxChunkSamples(forChunkIndex: chunkIndex) {
                        let split = pauseAwareSplitIndex(
                            in: buffer,
                            config: config,
                            chunkIndex: chunkIndex
                        )
                        emit(upTo: split, isLast: false)
                    }
                }

                if !buffer.isEmpty {
                    emit(upTo: buffer.count, isLast: true)
                } else if chunkIndex == 0 {
                    // Empty utterance — no chunks.
                } else {
                    // Stream ended exactly on boundary; mark prior path complete.
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Pick a split index at or after `maxChunkSamples`, preferring a pause.
    static func pauseAwareSplitIndex(
        in buffer: [Float],
        config: FlowUtteranceChunkConfig,
        chunkIndex: Int = 1
    ) -> Int {
        let minSplit = config.maxChunkSamples(forChunkIndex: chunkIndex)
        guard buffer.count >= minSplit else { return buffer.count }

        let searchEnd = min(buffer.count, minSplit + config.pauseExtensionSamples)
        if searchEnd <= minSplit {
            return minSplit
        }

        let windowSize = max(config.sampleRate / 50, 160) // ~20 ms
        var bestPause: Int?
        var idx = minSplit
        while idx + windowSize <= searchEnd {
            if rms(of: buffer, start: idx, count: windowSize) < config.pauseRMSThreshold {
                bestPause = idx + windowSize
            }
            idx += windowSize / 2
        }

        return bestPause ?? minSplit
    }

    static func rms(of samples: [Float], start: Int, count: Int) -> Float {
        guard start >= 0, count > 0, start + count <= samples.count else { return 1 }
        var sum: Float = 0
        for i in start..<(start + count) {
            let v = samples[i]
            sum += v * v
        }
        return sqrtf(sum / Float(count))
    }
}

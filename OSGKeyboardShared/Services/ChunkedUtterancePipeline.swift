// ChunkedUtterancePipeline.swift
// OSGKeyboard · Shared
//
// Pipelined Flow utterance ASR: split PCM while recording, transcribe chunks
// serially on a background queue, stitch partials for display and delivery.

import Foundation

public struct ChunkedUtteranceSuccess: Sendable, Equatable {
    public let text: String
    /// Non-fatal per-chunk ASR issues (delivered as soft warning when non-empty).
    public let chunkWarnings: [String]

    public init(text: String, chunkWarnings: [String] = []) {
        self.text = text
        self.chunkWarnings = chunkWarnings
    }
}

public enum ChunkedUtterancePipelineOutcome: Sendable, Equatable {
    case success(ChunkedUtteranceSuccess)
    case failure(String)
    case cancelled
}

/// Thread-safe queue between the chunk feeder and ASR worker.
private actor ChunkWorkQueue {
    private var items: [UtteranceAudioChunk] = []
    private var finished = false
    private var waiters: [CheckedContinuation<UtteranceAudioChunk?, Never>] = []

    func enqueue(_ chunk: UtteranceAudioChunk) {
        items.append(chunk)
        resumeWaiters()
    }

    func markFinished() {
        finished = true
        resumeWaiters()
    }

    func dequeue() async -> UtteranceAudioChunk? {
        if !items.isEmpty {
            return items.removeFirst()
        }
        if finished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func resumeWaiters() {
        while !waiters.isEmpty {
            if !items.isEmpty {
                let waiter = waiters.removeFirst()
                waiter.resume(returning: items.removeFirst())
            } else if finished {
                let waiter = waiters.removeFirst()
                waiter.resume(returning: nil)
            } else {
                break
            }
        }
    }
}

public actor ChunkedUtterancePipeline {
    private let asr: ASRService
    private let locale: Locale
    private let config: FlowUtteranceChunkConfig
    private var cancelled = false

    public init(
        asr: ASRService,
        locale: Locale,
        config: FlowUtteranceChunkConfig = .flowDefault
    ) {
        self.asr = asr
        self.locale = locale
        self.config = config
    }

    public func cancel() {
        cancelled = true
        asr.cancel()
    }

    /// Consume `stream` until finished; ASR runs off the caller's actor while recording continues.
    public func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        onPartial: @Sendable @escaping (String) -> Void
    ) async -> ChunkedUtterancePipelineOutcome {
        asr.resetForNewUtterance()

        let queue = ChunkWorkQueue()
        var stitcher = UtteranceTranscriptStitcher()
        var chunkWarnings: [String] = []
        var failedChunks = 0
        var processedChunks = 0
        var previousChunkSamples: [Float] = []
        var lastChunkSamples = 0

        let feeder = Task {
            for await chunk in UtteranceStreamChunker.chunks(from: stream, config: config) {
                if Task.isCancelled { break }
                await queue.enqueue(chunk)
            }
            await queue.markFinished()
        }

        while true {
            if cancelled || Task.isCancelled {
                feeder.cancel()
                return .cancelled
            }

            guard let chunk = await queue.dequeue() else { break }

            processedChunks += 1
            lastChunkSamples = chunk.samples.count

            if chunk.isLast,
               chunk.samples.count < config.minFinalChunkSamples,
               processedChunks > 1,
               !previousChunkSamples.isEmpty {
                let mergedSamples = Array(previousChunkSamples.suffix(config.overlapSamples))
                    + chunk.samples
                let mergedResult = await transcribeChunk(samples: mergedSamples)
                switch mergedResult {
                case .success(let text):
                    stitcher.removeLastSegment()
                    stitcher.append(index: max(0, chunk.index - 1), text: text)
                    publishPartial(from: stitcher, onPartial: onPartial)
                case .failure(let message):
                    failedChunks += 1
                    chunkWarnings.append(
                        SharedL10n.format(
                            "error.asr.chunkFailed",
                            chunk.index + 1,
                            message
                        )
                    )
                case .cancelled:
                    feeder.cancel()
                    return .cancelled
                }
                previousChunkSamples = chunk.samples
                continue
            }

            let result = await transcribeChunk(samples: chunk.samples)
            switch result {
            case .success(let text):
                stitcher.append(index: chunk.index, text: text)
                publishPartial(from: stitcher, onPartial: onPartial)
            case .failure(let message):
                failedChunks += 1
                chunkWarnings.append(
                    SharedL10n.format(
                        "error.asr.chunkFailed",
                        chunk.index + 1,
                        message
                    )
                )
            case .cancelled:
                feeder.cancel()
                return .cancelled
            }

            previousChunkSamples = chunk.samples
        }

        _ = await feeder.value

        let finalText = stitcher.composedSafely().trimmingCharacters(in: .whitespacesAndNewlines)
        FlowPipelineDiagnostics.logChunkFinalize(
            chunkCount: processedChunks,
            lastChunkSamples: lastChunkSamples,
            stitchedLength: finalText.count,
            chunkWarnings: chunkWarnings.count
        )

        if finalText.isEmpty {
            if failedChunks > 0, processedChunks == failedChunks {
                return .failure(SharedL10n.string("error.asr.noSpeech"))
            }
            return .failure(SharedL10n.string("error.asr.noSpeech"))
        }

        return .success(ChunkedUtteranceSuccess(text: finalText, chunkWarnings: chunkWarnings))
    }

    private func transcribeChunk(samples: [Float]) async -> ASRChunkResult {
        let asr = self.asr
        let locale = self.locale
        return await Task.detached(priority: .userInitiated) {
            await asr.transcribeChunk(samples: samples, locale: locale)
        }.value
    }

    private func publishPartial(
        from stitcher: UtteranceTranscriptStitcher,
        onPartial: @Sendable (String) -> Void
    ) {
        let partial = stitcher.composedSafely()
        if !partial.isEmpty {
            onPartial(partial)
        }
    }
}

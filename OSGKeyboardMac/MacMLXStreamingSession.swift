// MacMLXStreamingSession.swift
// OSGKeyboard · Mac
//
// Thin wrapper around mlx-audio-swift `StreamingInferenceSession`.

import Foundation
import MLXAudioSTT

/// One live MLX streaming ASR take (Option held).
final class MacMLXStreamingSession: @unchecked Sendable {
    private let session: StreamingInferenceSession
    private let eventTask: Task<Void, Never>
    private let lock = NSLock()
    private var endedContinuation: CheckedContinuation<String, Error>?
    private var peakRMS: Float = 0

    var onDisplayUpdate: (@Sendable (String) -> Void)?

    init(model: Qwen3ASRModel, config: StreamingConfig) {
        let session = StreamingInferenceSession(model: model, config: config)
        self.session = session

        final class EventSink: @unchecked Sendable {
            weak var owner: MacMLXStreamingSession?
        }
        let sink = EventSink()
        self.eventTask = Task {
            for await event in session.events {
                sink.owner?.handle(event)
            }
        }
        sink.owner = self
    }

    func feed(samples: [Float]) {
        guard !samples.isEmpty else { return }
        let rms = FlowCaptureDrainTracker.rms(of: samples)
        lock.withLock {
            peakRMS = max(peakRMS, rms)
        }
        if rms < MacHallucinationFilter.silencePeakThreshold { return }
        session.feedAudio(samples: samples)
    }

    func stop() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                endedContinuation = continuation
            }
            session.stop()
        }
    }

    func cancel() {
        session.cancel()
        lock.withLock {
            endedContinuation?.resume(throwing: MacLocalASRError.qwen3InferenceFailed("Cancelled"))
            endedContinuation = nil
        }
        eventTask.cancel()
    }

    func peakAudioRMS() -> Float {
        lock.withLock { peakRMS }
    }

    private func handle(_ event: TranscriptionEvent) {
        switch event {
        case .displayUpdate(let confirmed, let provisional):
            let display = confirmed + provisional
            let cleaned = MacHallucinationFilter.strip(display)
            guard !cleaned.isEmpty else { return }
            onDisplayUpdate?(cleaned)
        case .ended(let fullText):
            let cleaned = MacHallucinationFilter.strip(fullText)
            lock.withLock {
                if let continuation = endedContinuation {
                    continuation.resume(returning: cleaned)
                    endedContinuation = nil
                }
            }
        case .provisional, .confirmed, .stats:
            break
        }
    }
}

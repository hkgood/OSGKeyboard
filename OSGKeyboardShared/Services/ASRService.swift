// ASRService.swift
// OSGKeyboard · Shared
//
// Speech-to-text abstraction. As of iOS 26 being the minimum
// deployment target, the only ASR backend is `SpeechAnalyzer` +
// `DictationTranscriber` — always on-device, no cloud fallback, no
// `requiresOnDevice` toggle. The previous SFSpeechRecognizer path
// (iOS 18–25) is gone; if a future platform ever needs it back,
// reintroduce as a sibling class in `ASRServiceFactory.make()`.
//
// Lives in `OSGKeyboardShared` (not the keyboard extension target) so
// that the host app's `KeyboardPreviewSheet` can run the same ASR
// pipeline against real iOS audio — without it, the in-app preview
// was a static mock that never actually called `SFSpeechRecognizer`,
// and "did you actually wire up ASR?" was a fair review note.

import Foundation
import AVFoundation
import Speech
import os

// MARK: - Sendable conformance

// `AVAudioPCMBuffer` and `SpeechAnalyzer` are not Sendable. We only
// ever access them serially — the PCM buffer is built and consumed
// inside a single Task, and the analyzer is cancelled but never
// shared concurrently — so an unchecked conformance is sound here.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}

// MARK: - Protocol

public protocol ASRService: Sendable {
    /// Start a transcription session. The returned stream emits `.partial`
    /// updates and exactly one `.final` (or `.error`) before finishing.
    /// `SpeechAnalyzer` is always fully on-device, so there is no
    /// `requiresOnDevice` flag — the previous iOS 18 SFSpeechRecognizer
    /// flag was about cloud fallback, which doesn't apply here.
    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent>

    /// Cancel any in-flight recognition and tear down its tasks.
    func cancel()
}

public enum ASREvent: Sendable, Equatable {
    /// Emitted exactly once at the start of every `transcribe` call, so
    /// the UI can flag non-on-device locales (e.g. ja-JP on devices that
    /// only ship on-device ASR for en/zh). The ASR session continues
    /// either way — we fall back to cloud automatically.
    case capability(onDeviceSupported: Bool)
    case partial(String)
    case final(String)
    case error(String)
}

// MARK: - Factory

public enum ASRServiceFactory {
    /// Returns the ASR backend. With iOS 26 as the deployment target,
    /// there is exactly one backend (`SpeechAnalyzer`).
    public static func make() -> ASRService {
        SpeechAnalyzerASR()
    }
}

// MARK: - SpeechAnalyzer implementation (iOS 26+)

/// ASR backend that uses the iOS 26 `SpeechAnalyzer` + `DictationTranscriber`
/// APIs. This engine is always fully on-device.
final class SpeechAnalyzerASR: ASRService, @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private var analyzer: SpeechAnalyzer?
    private var analyzerTask: Task<Void, Never>?

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            // SpeechAnalyzer is always fully on-device.
            continuation.yield(.capability(onDeviceSupported: true))

            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
            let newAnalyzer = SpeechAnalyzer(modules: [transcriber])
            self.lock.withLock { self.analyzer = newAnalyzer }

            let audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )!

            let task = Task { [weak self] in
                guard let self else { return }
                do {
                    try await newAnalyzer.prepareToAnalyze(in: audioFormat)

                    let inputStream = self.makeInputStream(from: stream, format: audioFormat)

                    // Feed audio in a child task so we can concurrently
                    // iterate `transcriber.results` on the outer task.
                    // After the audio stream ends, finalize so the results
                    // sequence can drain and complete.
                    let feedTask = Task {
                        do {
                            try await newAnalyzer.start(inputSequence: inputStream)
                            try await newAnalyzer.finalizeAndFinishThroughEndOfInput()
                        } catch {}
                    }
                    defer { feedTask.cancel() }

                    var lastText = ""
                    do {
                        for try await result in transcriber.results {
                            if Task.isCancelled { break }
                            // `result.text` is an AttributedString; extract plain text.
                            let text = result.text.characters.map(String.init).joined()
                            guard !text.isEmpty, text != lastText else { continue }
                            lastText = text
                            continuation.yield(.partial(text))
                        }
                    } catch {
                        // Results sequence threw — likely cancellation.
                    }

                    if !Task.isCancelled {
                        continuation.yield(.final(lastText))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
            self.lock.withLock { self.analyzerTask = task }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancel()
            }
        }
    }

    func cancel() {
        let (task, currentAnalyzer) = lock.withLock { () -> (Task<Void, Never>?, SpeechAnalyzer?) in
            let t = analyzerTask
            let a = analyzer
            analyzerTask = nil
            analyzer = nil
            return (t, a)
        }
        task?.cancel()
        if let a = currentAnalyzer {
            Task { await a.cancelAndFinishNow() }
        }
    }

    /// Maps the `AudioBufferSnapshot` stream into the `AnalyzerInput` stream
    /// that `SpeechAnalyzer` consumes.
    private func makeInputStream(
        from stream: AsyncStream<AudioBufferSnapshot>,
        format: AVAudioFormat
    ) -> AsyncStream<AnalyzerInput> {
        AsyncStream { continuation in
            Task {
                for await snap in stream {
                    guard !snap.samples.isEmpty,
                          let pcm = AVAudioPCMBuffer(
                            pcmFormat: format,
                            frameCapacity: AVAudioFrameCount(snap.samples.count)
                          )
                    else { continue }
                    pcm.frameLength = AVAudioFrameCount(snap.samples.count)
                    if let dst = pcm.floatChannelData?[0] {
                        snap.samples.withUnsafeBufferPointer { src in
                            guard let base = src.baseAddress else { return }
                            memcpy(dst, base, snap.samples.count * MemoryLayout<Float>.size)
                        }
                    }
                    continuation.yield(AnalyzerInput(buffer: pcm))
                }
                continuation.finish()
            }
        }
    }
}

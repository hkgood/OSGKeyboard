// ASRService.swift
// OSGKeyboard · Shared
//
// Speech-to-text abstraction. As of iOS 26 being the minimum
// deployment target, the only ASR backend is `SpeechAnalyzer` +
// `DictationTranscriber` — always on-device, no cloud fallback, no
// `requiresOnDevice` toggle. The previous legacy recognizer path is
// gone; if a future platform ever needs it back,
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
    /// `requiresOnDevice` flag — that legacy cloud-fallback control
    /// doesn't apply to the iOS 26 `SpeechAnalyzer` path.
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

// MARK: - PCM format conversion (testable helpers)
//
// Extracted from the audio-thread hot path so the scaling + clipping
// math can be exercised in unit tests without instantiating the
// full ASR pipeline. See `OSGKeyboardTests/ASRConversionTests.swift`.
extension ASRServiceFactory {

    /// Convert a Float32 PCM buffer (`-1.0...1.0`) to an Int16 PCM
    /// buffer (`-32768...32767`).
    ///
    /// - Parameters:
    ///   - source: Pointer to `sourceCount` `Float` samples. May be
    ///     `nil` when `sourceCount == 0`.
    ///   - sourceCount: Number of samples to convert. A `0` count
    ///     turns the call into a no-op regardless of the pointers.
    ///   - destination: Pointer to at least `sourceCount` slots of
    ///     `Int16`. May be `nil` when `sourceCount == 0`.
    ///
    /// Per-sample: `Int16(round(clamp(s * 32767, -32768, 32767)))`.
    /// The explicit clip matters: without it, `s == 1.0` would map
    /// to `+32767` (fine) but `s == 1.5` (which can show up at the
    /// audio engine boundary under gain) would wrap to a negative
    /// value after the implicit Float→Int16 conversion. The
    /// `round()` (rather than truncate) preserves DC balance — `0.5`
    /// quantises to `+16384`, not `+16383`, matching what most audio
    /// DAW round-trips expect.
    static func convertFloat32ToInt16(
        source: UnsafePointer<Float>?,
        sourceCount: Int,
        destination: UnsafeMutablePointer<Int16>?
    ) {
        guard sourceCount > 0, let source, let destination else { return }
        for i in 0..<sourceCount {
            let scaled = source[i] * 32767.0
            let clipped = Swift.max(-32768.0, Swift.min(32767.0, scaled))
            destination[i] = Int16(clipped.rounded())
        }
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

            // iOS 26's `DictationTranscriber` requires **Int16** PCM
            // (precondition `"Audio sample data must be 16-bit signed
            // integers"` — the legacy recognizer used Float32 at this
            // boundary; `SpeechAnalyzer` is strict Int16). 16 kHz mono, Int16,
            // interleaved — the canonical layout Apple's Speech
            // framework examples use.
            let audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
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
    ///
    /// `AudioBufferSnapshot.samples` is `[Float]` (the transport format
    /// both `AudioCaptureService` and `PreviewASRController` produce —
    /// Float32 is what `AVAudioEngine` gives us at the hardware rate
    /// and we already downsample to 16 kHz mono before this point).
    /// iOS 26's `DictationTranscriber` requires **Int16** PCM at the
    /// `AnalyzerInput` boundary, so we convert per-snapshot here.
    ///
    /// The conversion is the textbook `[-1.0, 1.0]` × 32767 + clip +
    /// cast. For a 16 kHz mono feed the loop is ~16k iters/sec —
    /// well under any audio-thread budget — so a simple scalar loop
    /// beats pulling in `vDSP` (which would also need a scratch
    /// buffer the audio thread can't easily allocate).
    private func makeInputStream(
        from stream: AsyncStream<AudioBufferSnapshot>,
        format: AVAudioFormat
    ) -> AsyncStream<AnalyzerInput> {
        AsyncStream { continuation in
            Task {
                for await snap in stream {
                    guard !snap.samples.isEmpty else { continue }
                    let capacity = AVAudioFrameCount(snap.samples.count)
                    guard let pcm = AVAudioPCMBuffer(
                        pcmFormat: format,
                        frameCapacity: capacity
                    ) else { continue }
                    pcm.frameLength = capacity

                    // For a 1-channel Int16 buffer (interleaved or not —
                    // single channel, so the data layout is identical),
                    // `int16ChannelData?[0]` gives us the raw sample
                    // pointer. Clip on overflow to avoid wraparound
                    // (a Float like 1.5 would otherwise become a
                    // negative Int16 after the implicit truncation).
                    if let dst = pcm.int16ChannelData?[0] {
                        snap.samples.withUnsafeBufferPointer { src in
                            ASRServiceFactory.convertFloat32ToInt16(
                                source: src.baseAddress,
                                sourceCount: src.count,
                                destination: dst
                            )
                        }
                    }
                    continuation.yield(AnalyzerInput(buffer: pcm))
                }
                continuation.finish()
            }
        }
    }
}

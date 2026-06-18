// ASRService.swift
// OSGKeyboard · Shared
//
// Speech-to-text abstraction.
// • iOS 26+: uses `SpeechAnalyzer` + `DictationTranscriber` — always on-device.
// • iOS 18–25: uses `SFSpeechRecognizer`, with optional requiresOnDevice flag.
// Honours a user-selected locale (auto / zh-CN / en-US / ja-JP …) so
// dictation is first-class for non-English languages.
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

// `AVAudioPCMBuffer` and `SFSpeechRecognitionTask` are not Sendable. We
// only ever access them serially — the PCM buffer is built and consumed
// inside a single Task, and the recogniser task is cancelled but never
// shared concurrently — so an unchecked conformance is sound here.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}
extension SFSpeechRecognitionTask: @unchecked @retroactive Sendable {}

// MARK: - Protocol

public protocol ASRService: Sendable {
    /// Start a transcription session. The returned stream emits `.partial`
    /// updates and exactly one `.final` (or `.error`) before finishing.
    /// - Parameters:
    ///   - stream: Audio buffer stream from `AudioCaptureService`.
    ///   - locale: Target recognition locale.
    ///   - requiresOnDevice: When `true`, forces on-device recognition only
    ///     (SFSpeechRecognizer path). Ignored on iOS 26+ where
    ///     `SpeechAnalyzer` is always fully on-device.
    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale,
        requiresOnDevice: Bool
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
    /// Returns the best available ASR backend for the current OS:
    /// `SpeechAnalyzerASR` on iOS 26+ (always on-device), `AppleSpeechASR`
    /// on older OS versions.
    public static func make() -> ASRService {
        if #available(iOS 26.0, *) {
            return SpeechAnalyzerASR()
        }
        return AppleSpeechASR()
    }
}

// MARK: - Apple Speech implementation (iOS 18–25)

final class AppleSpeechASR: ASRService, @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private var recognizerTask: SFSpeechRecognitionTask?
    private var feedTask: Task<Void, Never>?

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale,
        requiresOnDevice: Bool
    ) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            let recognizer = SFSpeechRecognizer(locale: locale)
                ?? SFSpeechRecognizer(locale: .current)
            guard let recognizer, recognizer.isAvailable else {
                continuation.yield(.error("Speech recognizer unavailable for \(locale.identifier)"))
                continuation.finish()
                return
            }
            recognizer.defaultTaskHint = .dictation

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Honour the user's "force on-device" preference; fall back to
            // whatever the device natively supports if the flag is off.
            request.requiresOnDeviceRecognition = requiresOnDevice || recognizer.supportsOnDeviceRecognition
            let onDeviceSupported = recognizer.supportsOnDeviceRecognition
            if !onDeviceSupported {
                #if DEBUG
                print("⚠️ 设备不支持 \(locale.identifier) 端侧 ASR, 回退云端。")
                #endif
            }
            // Tell the UI about the capability *before* any partials so
            // the StatusBadge can light up the cloud-fallback indicator
            // as soon as the user presses the mic.
            continuation.yield(.capability(onDeviceSupported: onDeviceSupported))

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let nsErr = error as NSError
                    // Codes 203 / 1110 = "no speech detected" — a normal exit.
                    if nsErr.code == 203 || nsErr.code == 1110 {
                        continuation.yield(.final(""))
                    } else {
                        continuation.yield(.error(error.localizedDescription))
                    }
                    continuation.finish()
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    continuation.yield(.final(result.bestTranscription.formattedString))
                    continuation.finish()
                } else {
                    continuation.yield(.partial(result.bestTranscription.formattedString))
                }
            }

            self.lock.withLock { self.recognizerTask = task }

            // Feed audio: for each snapshot, build a 16 kHz mono Float32
            // PCM buffer and immediately `request.append(pcm)`. The PCM
            // buffer never leaves this task, so it doesn't need to be
            // Sendable.
            let feedFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )!
            self.feedTask = Task { [request] in
                for await snap in stream {
                    if Task.isCancelled { break }
                    guard !snap.samples.isEmpty,
                          let pcm = AVAudioPCMBuffer(
                            pcmFormat: feedFormat,
                            frameCapacity: AVAudioFrameCount(snap.samples.count)
                          )
                    else { continue }
                    pcm.frameLength = AVAudioFrameCount(snap.samples.count)
                    if let dst = pcm.floatChannelData?[0] {
                        snap.samples.withUnsafeBufferPointer { src in
                            if let base = src.baseAddress {
                                memcpy(dst, base, snap.samples.count * MemoryLayout<Float>.size)
                            }
                        }
                    }
                    request.append(pcm)
                }
                if !Task.isCancelled {
                    request.endAudio()
                }
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancel()
            }
        }
    }

    func cancel() {
        let (recTask, feedT) = lock.withLock { () -> (SFSpeechRecognitionTask?, Task<Void, Never>?) in
            let r = self.recognizerTask
            let f = self.feedTask
            self.recognizerTask = nil
            self.feedTask = nil
            return (r, f)
        }
        recTask?.cancel()
        feedT?.cancel()
    }
}

// MARK: - SpeechAnalyzer implementation (iOS 26+)

/// ASR backend that uses the iOS 26 `SpeechAnalyzer` + `DictationTranscriber`
/// APIs. This engine is always fully on-device — `requiresOnDevice` has no
/// effect and `.capability(onDeviceSupported: true)` is always emitted.
@available(iOS 26.0, *)
final class SpeechAnalyzerASR: ASRService, @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private var analyzer: SpeechAnalyzer?
    private var analyzerTask: Task<Void, Never>?

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale,
        requiresOnDevice: Bool  // ignored — SpeechAnalyzer is always on-device
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

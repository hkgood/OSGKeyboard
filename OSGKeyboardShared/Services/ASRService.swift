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
    private var analyzerFinished = false

    /// Canonical capture format: 16 kHz mono Float32 from `AudioCaptureService`
    /// / `PreviewASRController` before it reaches SpeechAnalyzer.
    private static let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            continuation.yield(.capability(onDeviceSupported: true))

            let task = Task { [weak self] in
                guard let self else { return }
                self.lock.withLock { self.analyzerFinished = false }
                defer {
                    self.lock.withLock {
                        self.analyzer = nil
                        self.analyzerTask = nil
                        self.analyzerFinished = true
                    }
                }

                do {
                    guard let resolvedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
                        Self.debug("locale unsupported: \(locale.identifier(.bcp47))")
                        continuation.yield(.error("当前系统未分配可用语音语言模型，请稍后重试或切换语言"))
                        continuation.finish()
                        return
                    }
                    let transcriber = DictationTranscriber(locale: resolvedLocale, preset: .progressiveShortDictation)
                    do {
                        try await Self.prepareAssetsIfNeeded(for: transcriber, locale: resolvedLocale)
                    } catch {
                        Self.debug("asset prepare failed: \(error.localizedDescription)")
                        continuation.yield(.error("语音语言资源未就绪，请稍后重试"))
                        continuation.finish()
                        return
                    }

                    let newAnalyzer = SpeechAnalyzer(modules: [transcriber])
                    self.lock.withLock { self.analyzer = newAnalyzer }

                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber],
                        considering: Self.captureFormat
                    ) else {
                        continuation.yield(.error("当前设备不支持该语音输入格式"))
                        continuation.finish()
                        return
                    }

                    try await newAnalyzer.prepareToAnalyze(in: analyzerFormat)

                    let inputStream = self.makeInputStream(from: stream, analyzerFormat: analyzerFormat)

                    // Apple recommends consuming `transcriber.results` concurrently
                    // while `analyzeSequence` drains the input stream.
                    let resultsTask = Task<String, Error> {
                        var lastText = ""
                        for try await result in transcriber.results {
                            if Task.isCancelled { break }
                            let text = String(result.text.characters)
                            guard !text.isEmpty, text != lastText else { continue }
                            lastText = text
                            continuation.yield(.partial(text))
                        }
                        return lastText
                    }

                    let lastSampleTime = try await newAnalyzer.analyzeSequence(inputStream)

                    if let lastSampleTime {
                        try await newAnalyzer.finalizeAndFinish(through: lastSampleTime)
                    } else {
                        try await newAnalyzer.cancelAndFinishNow()
                    }

                    let lastText: String
                    do {
                        lastText = try await resultsTask.value
                    } catch {
                        Self.debug("transcriber results failed: \(error.localizedDescription)")
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish()
                        return
                    }

                    let trimmed = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        continuation.yield(.error("未识别到语音内容，请重试"))
                    } else {
                        continuation.yield(.final(trimmed))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    Self.debug("SpeechAnalyzer failed: \(error.localizedDescription)")
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

    private static func debug(_ message: String) {
        #if DEBUG
        print("🎙️[ASRService] \(message)")
        #endif
    }

    private static func prepareAssetsIfNeeded(
        for transcriber: DictationTranscriber,
        locale: Locale
    ) async throws {
        do {
            _ = try await AssetInventory.reserve(locale: locale)
        } catch {
            // Reservation may already exist or slots are full; continue.
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    func cancel() {
        let (task, currentAnalyzer, finished) = lock.withLock { () -> (Task<Void, Never>?, SpeechAnalyzer?, Bool) in
            let t = analyzerTask
            let a = analyzer
            let f = analyzerFinished
            analyzerTask = nil
            analyzer = nil
            return (t, a, f)
        }
        task?.cancel()
        guard !finished, let currentAnalyzer else { return }
        Task { await currentAnalyzer.cancelAndFinishNow() }
    }

    /// Maps 16 kHz Float32 snapshots into `AnalyzerInput` using the format
    /// returned by `bestAvailableAudioFormat(compatibleWith:considering:)`.
    private func makeInputStream(
        from stream: AsyncStream<AudioBufferSnapshot>,
        analyzerFormat: AVAudioFormat
    ) -> AsyncStream<AnalyzerInput> {
        AsyncStream { continuation in
            Task {
                for await snap in stream {
                    guard !snap.samples.isEmpty else { continue }
                    guard let pcm = Self.makeAnalyzerPCMBuffer(from: snap, format: analyzerFormat) else {
                        continue
                    }
                    continuation.yield(AnalyzerInput(buffer: pcm))
                }
                continuation.finish()
            }
        }
    }

    private static func makeAnalyzerPCMBuffer(
        from snap: AudioBufferSnapshot,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(snap.samples.count)
        guard capacity > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        pcm.frameLength = capacity

        switch format.commonFormat {
        case .pcmFormatInt16:
            guard let dst = pcm.int16ChannelData?[0] else { return nil }
            snap.samples.withUnsafeBufferPointer { src in
                ASRServiceFactory.convertFloat32ToInt16(
                    source: src.baseAddress,
                    sourceCount: src.count,
                    destination: dst
                )
            }
        case .pcmFormatFloat32:
            guard let dst = pcm.floatChannelData?[0] else { return nil }
            snap.samples.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                memcpy(dst, base, src.count * MemoryLayout<Float>.stride)
            }
        default:
            return nil
        }
        return pcm
    }
}

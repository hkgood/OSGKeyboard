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
import CoreMedia
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

    /// Clears cancellation / cached session state before a new utterance.
    func resetForNewUtterance()

    /// Transcribe one PCM chunk (Flow pipelined path). Default wraps `transcribe(stream:)`.
    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult
}

public enum ASRChunkResult: Sendable, Equatable {
    case success(String)
    case failure(String)
    case cancelled
}

extension ASRService {
    public func resetForNewUtterance() {}

    public func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        guard !samples.isEmpty else { return .success("") }
        if Task.isCancelled { return .cancelled }

        let snapshot = AudioBufferSnapshot(samples: samples, sampleRate: 16_000)
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(snapshot)
        continuation.finish()

        var lastPartial = ""
        var finalText = ""
        var failure: String?

        for await event in transcribe(stream: stream, locale: locale) {
            if Task.isCancelled { return .cancelled }
            switch event {
            case .capability:
                break
            case .partial(let text):
                lastPartial = text
            case .final(let text):
                finalText = text
            case .error(let message):
                failure = message
            }
        }

        if let failure {
            return .failure(failure)
        }
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return .success(trimmed)
        }
        let partial = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            return .success(partial)
        }
        return .success("")
    }
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
    /// Registry of backend-specific providers. The host app installs
    /// a provider for the Qwen3-ASR backend at launch time (the
    /// `Qwen3ASRProvider` lives in the app target because linking
    /// `Qwen3ASR` pulls in mlx-swift, which the shared framework
    /// deliberately stays off to keep `APPLICATION_EXTENSION_API_ONLY`
    /// clean). The shared framework always provides a built-in
    /// `SpeechAnalyzer` provider; custom providers override it.
    ///
    /// `nonisolated(unsafe)` because the only writer is
    /// `OSGKeyboardApp.init` (single-threaded, runs once at launch).
    /// After launch, all callers read the dictionary from any
    /// actor.
    public nonisolated(unsafe) static var providers: [LocalASRBackend: any ASRServiceProvider] = [
        .speechAnalyzer: SpeechAnalyzerProvider()
    ]

    /// Returns the ASR backend chosen by the user. The cloud engine
    /// always uses the iOS `SpeechAnalyzer` path — it has the lowest
    /// latency and never hits the network, which matches the user's
    /// expectation that "ASR" is the local half of the pipeline
    /// regardless of where the LLM polish happens.
    ///
    /// For the local engine, we honour `LocalASRBackend`:
    ///   - `.speechAnalyzer` (default) → on-device iOS pipeline.
    ///   - `.qwen3ASR` → CoreML-backed Qwen3-ASR via `soniqo/speech-swift` (host app only)
    ///                     (registered by the host app at launch).
    public static func make(
        engineMode: String,
        localBackend: LocalASRBackend = .speechAnalyzer
    ) -> ASRService {
        if engineMode == "local" {
            if let provider = providers[localBackend] {
                return provider.make()
            }
        }
        return SpeechAnalyzerASR()
    }

    /// Back-compat overload for callers that only ever want the
    /// SpeechAnalyzer path. The previous single-backend build used
    /// this signature; new code should pass the engine mode explicitly
    /// so the user's selection is honoured.
    public static func make() -> ASRService {
        SpeechAnalyzerASR()
    }
}

/// Backend-specific ASR factory. The shared framework ships a default
/// `SpeechAnalyzerProvider`; the host app installs a `Qwen3ASRProvider`
/// at launch time so the Qwen3 backend is wired in only where its
/// large MLX dependency is also linked.
public protocol ASRServiceProvider: Sendable {
    var backend: LocalASRBackend { get }
    func make() -> ASRService
}

/// Built-in provider for the iOS SpeechAnalyzer path. Always present.
struct SpeechAnalyzerProvider: ASRServiceProvider {
    let backend: LocalASRBackend = .speechAnalyzer
    func make() -> ASRService { SpeechAnalyzerASR() }
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
    /// Reused across pipelined chunks within one utterance (assets + format).
    private var chunkPreparedLocaleID: String?
    private var chunkAnalyzerFormat: AVAudioFormat?

    func resetForNewUtterance() {
        lock.withLock {
            chunkPreparedLocaleID = nil
            chunkAnalyzerFormat = nil
        }
    }

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        guard !samples.isEmpty else { return .success("") }
        if Task.isCancelled { return .cancelled }

        do {
            let text = try await transcribeSamples(samples, locale: locale, reuseChunkPrep: true)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .success("") : .success(trimmed)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Analyze a single PCM buffer without the streaming `transcribe` wrapper.
    private func transcribeSamples(
        _ samples: [Float],
        locale: Locale,
        reuseChunkPrep: Bool
    ) async throws -> String {
        guard let resolvedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ASRChunkError.localeUnsupported
        }
        let localeID = resolvedLocale.identifier(.bcp47)
        let transcriber = DictationTranscriber(
            locale: resolvedLocale,
            preset: .progressiveLongDictation
        )

        let analyzerFormat: AVAudioFormat
        let cachedPrep = lock.withLock { (chunkPreparedLocaleID, chunkAnalyzerFormat) }
        if reuseChunkPrep,
           cachedPrep.0 == localeID,
           let cached = cachedPrep.1 {
            analyzerFormat = cached
        } else {
            try await Self.prepareAssetsIfNeeded(for: transcriber, locale: resolvedLocale)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: Self.captureFormat
            ) else {
                throw ASRChunkError.formatUnsupported
            }
            analyzerFormat = format
            lock.withLock {
                chunkPreparedLocaleID = localeID
                chunkAnalyzerFormat = format
            }
        }

        let snapshot = AudioBufferSnapshot(samples: samples, sampleRate: 16_000)
        guard let pcm = Self.makeAnalyzerPCMBuffer(from: snapshot, format: analyzerFormat) else {
            throw ASRChunkError.formatUnsupported
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let resultsTask = Task<String, Error> {
            var accumulator = ProgressiveDictationTranscriptAccumulator()
            for try await result in transcriber.results {
                if Task.isCancelled { break }
                let text = String(result.text.characters)
                _ = accumulator.ingest(range: result.range, text: text)
            }
            return accumulator.finalize()
        }

        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(AnalyzerInput(buffer: pcm))
            continuation.finish()
        }

        let lastSampleTime = try await analyzer.analyzeSequence(inputStream)
        if let lastSampleTime {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await resultsTask.value
    }

    private enum ASRChunkError: LocalizedError {
        case localeUnsupported
        case formatUnsupported

        var errorDescription: String? {
            switch self {
            case .localeUnsupported:
                return SharedL10n.string("error.asr.localeUnsupported")
            case .formatUnsupported:
                return SharedL10n.string("error.asr.formatUnsupported")
            }
        }
    }

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
                        continuation.yield(.error(SharedL10n.string("error.asr.localeUnsupported")))
                        continuation.finish()
                        return
                    }
                    // Each pipelined chunk is ≤ 30 s; long dictation preset keeps a
                    // single chunk coherent (Flow utterances run up to 3 min).
                    let transcriber = DictationTranscriber(
                        locale: resolvedLocale,
                        preset: .progressiveLongDictation
                    )
                    do {
                        try await Self.prepareAssetsIfNeeded(for: transcriber, locale: resolvedLocale)
                    } catch {
                        Self.debug("asset prepare failed: \(error.localizedDescription)")
                        continuation.yield(.error(SharedL10n.string("error.asr.assetsNotReady")))
                        continuation.finish()
                        return
                    }

                    let newAnalyzer = SpeechAnalyzer(modules: [transcriber])
                    self.lock.withLock { self.analyzer = newAnalyzer }

                    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                        compatibleWith: [transcriber],
                        considering: Self.captureFormat
                    ) else {
                        continuation.yield(.error(SharedL10n.string("error.asr.formatUnsupported")))
                        continuation.finish()
                        return
                    }

                    try await newAnalyzer.prepareToAnalyze(in: analyzerFormat)

                    let inputStream = self.makeInputStream(from: stream, analyzerFormat: analyzerFormat)

                    // Apple recommends consuming `transcriber.results` concurrently
                    // while `analyzeSequence` drains the input stream.
                    let resultsTask = Task<String, Error> {
                        var accumulator = ProgressiveDictationTranscriptAccumulator()
                        for try await result in transcriber.results {
                            if Task.isCancelled { break }
                            let text = String(result.text.characters)
                            guard let full = accumulator.ingest(range: result.range, text: text) else {
                                continue
                            }
                            continuation.yield(.partial(full))
                        }
                        return accumulator.finalize()
                    }

                    let lastSampleTime = try await newAnalyzer.analyzeSequence(inputStream)

                    if let lastSampleTime {
                        try await newAnalyzer.finalizeAndFinish(through: lastSampleTime)
                    } else {
                        await newAnalyzer.cancelAndFinishNow()
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
                        continuation.yield(.error(SharedL10n.string("error.asr.noSpeech")))
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

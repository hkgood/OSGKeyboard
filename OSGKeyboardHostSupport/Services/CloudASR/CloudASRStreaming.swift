// CloudASRStreaming.swift
// OSGKeyboard · HostSupport
//
// Utterance-scoped cloud ASR sessions: one long-lived connection per press,
// streaming PCM up and interim text down. Chunked batch ASR remains the
// fallback for providers without a true streaming protocol.

import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

enum CloudASRLogMetadata {
    static func describe(_ error: Error) -> String {
        if let managedError = error as? ManagedCloudASRError {
            return "category=\(managedError.stableCode)"
        }
        if let cloudError = error as? CloudASRError {
            switch cloudError {
            case .noAPIKey:
                return "category=noAPIKey"
            case .invalidURL:
                return "category=invalidURL"
            case .http(let status, let message):
                return "category=http status=\(status) detailBytes=\(message?.utf8.count ?? 0)"
            case .decoding(let detail):
                return "category=decoding detailBytes=\(detail.utf8.count)"
            case .transport(let detail):
                return "category=transport detailBytes=\(detail.utf8.count)"
            case .emptyTranscript:
                return "category=emptyTranscript"
            case .audioTooLong:
                return "category=audioTooLong"
            case .providerUnsupported:
                return "category=providerUnsupported"
            }
        }
        if let urlError = error as? URLError {
            return "category=url code=\(urlError.code.rawValue)"
        }
        return "category=\(String(reflecting: type(of: error)))"
    }
}

/// Long-lived cloud ASR session for one Flow utterance.
public protocol CloudASRStreamingSession: Sendable {
    /// Append 16 kHz mono Float32 PCM captured while the mic is open.
    func append(samples: [Float]) async throws
    /// Signal end-of-audio and wait for the polish-ready final transcript.
    func finish() async throws -> String
    func cancel()
}

/// Providers that can open an utterance-level streaming session.
public protocol CloudASRStreamingCapable: CloudASRTranscribing {
    func openStreamingSession(
        locale: Locale,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> any CloudASRStreamingSession
}

/// Feeds a live mic stream into a cloud streaming session and mirrors the
/// existing `ChunkedUtterancePipelineOutcome` surface for Flow.
public actor StreamingUtterancePipeline {
    private let client: any CloudASRStreamingCapable
    private let locale: Locale
    private let dictionary: PersonalDictionary
    private var cancelled = false
    private var activeSession: (any CloudASRStreamingSession)?

    public init(
        client: any CloudASRStreamingCapable,
        locale: Locale,
        dictionary: PersonalDictionary
    ) {
        self.client = client
        self.locale = locale
        self.dictionary = dictionary
    }

    public func cancel() {
        cancelled = true
        activeSession?.cancel()
    }

    public func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        onPartial: @Sendable @escaping (String) -> Void,
        preopenedSession: (any CloudASRStreamingSession)? = nil
    ) async -> ChunkedUtterancePipelineOutcome {
        cancelled = false
        let startedAt = Date()
        // Counted so an empty cloud transcript can be told apart from "we never
        // uploaded any audio" — the two look identical to the user.
        var uploadedSamples = 0
        var uploadedSnapshots = 0
        do {
            let session: any CloudASRStreamingSession
            if let preopenedSession {
                session = preopenedSession
            } else {
                session = try await client.openStreamingSession(
                    locale: locale,
                    dictionary: dictionary,
                    onPartial: onPartial
                )
            }
            activeSession = session
            FlowTrace.asr(
                "cloud.stream.opened",
                "locale=\(locale.identifier(.bcp47)) preopened=\(preopenedSession != nil ? 1 : 0)"
            )

            for await snap in stream {
                if cancelled || Task.isCancelled {
                    session.cancel()
                    FlowTrace.asr(
                        "cloud.stream.cancelledMidUpload",
                        "uploadedSamples=\(uploadedSamples)"
                    )
                    return .cancelled
                }
                guard !snap.samples.isEmpty else { continue }
                uploadedSnapshots += 1
                uploadedSamples += snap.samples.count
                try await session.append(samples: snap.samples)
            }

            FlowTrace.asr(
                "cloud.stream.uploadDone",
                "snapshots=\(uploadedSnapshots) samples=\(uploadedSamples) "
                    + "seconds=\(FlowTrace.seconds(samples: uploadedSamples))"
            )

            if cancelled || Task.isCancelled {
                session.cancel()
                return .cancelled
            }

            let finalText = try await session.finish()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            activeSession = nil
            guard !finalText.isEmpty else {
                FlowTrace.warn(
                    "asr.cloud.stream.emptyFinal",
                    "uploadedSamples=\(uploadedSamples) "
                        + "seconds=\(FlowTrace.seconds(samples: uploadedSamples)) "
                        + "elapsed=\(FlowTrace.seconds(since: startedAt))s"
                )
                return .failure(SharedL10n.string("error.asr.noSpeech"))
            }
            FlowTrace.transcript(
                "asr.cloud.final",
                finalText,
                "engine=cloud uploadedSamples=\(uploadedSamples) "
                    + "elapsed=\(FlowTrace.seconds(since: startedAt))s"
            )
            return .success(ChunkedUtteranceSuccess(text: finalText))
        } catch where ProviderToolCancellation.matches(error) {
            activeSession?.cancel()
            activeSession = nil
            FlowTrace.asr("cloud.stream.cancelled", "uploadedSamples=\(uploadedSamples)")
            return .cancelled
        } catch {
            activeSession?.cancel()
            activeSession = nil
            if cancelled || Task.isCancelled { return .cancelled }
            FlowTrace.warn(
                "asr.cloud.stream.failed",
                "uploadedSamples=\(uploadedSamples) "
                    + "elapsed=\(FlowTrace.seconds(since: startedAt))s "
                    + "\(CloudASRLogMetadata.describe(error))"
            )
            return .failure(error.localizedDescription)
        }
    }
}

/// Shared PCM helpers for streaming cloud clients.
enum CloudASRStreamingPCM {
    static func pcm16LE(samples: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * 2)
        for sample in samples {
            let scaled = sample * 32_767.0
            let clipped = Swift.max(-32_768.0, Swift.min(32_767.0, scaled))
            var littleEndian = Int16(clipped.rounded()).littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Linear upsample 16 kHz → 24 kHz for OpenAI Realtime PCM input.
    static func upsample16kTo24k(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let outCount = max(1, samples.count * 3 / 2)
        var output = [Float]()
        output.reserveCapacity(outCount)
        let lastIndex = samples.count - 1
        for i in 0..<outCount {
            let src = Double(i) * 16.0 / 24.0
            let i0 = min(Int(src), lastIndex)
            let i1 = min(i0 + 1, lastIndex)
            let frac = Float(src - Double(i0))
            output.append(samples[i0] + (samples[i1] - samples[i0]) * frac)
        }
        return output
    }
}

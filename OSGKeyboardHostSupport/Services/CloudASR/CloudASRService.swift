// CloudASRService.swift
// OSGKeyboard · HostSupport
//
// Cloud-engine ASR: uploads PCM to the user's configured provider with
// personal-dictionary bias. Streaming-capable providers use one utterance
// WebSocket; others stay on chunked batch. Moonshot falls back to on-device ASR.

import Foundation
import os
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

/// Uploads PCM only on the user-selected cloud engine path; provider clients
/// reject missing credentials before network transmission. Personal dictionary
/// entries are sent as recognition bias. Mutable client/cancellation state is
/// lock-protected, which is the basis for `@unchecked Sendable`.
public final class CloudASRService: ASRService, @unchecked Sendable {
    private let store: any ConfigurationStore
    private let session: URLSession
    private let localFallback: ASRService
    /// Optional account-managed path. A nil value preserves existing BYOK and
    /// provider-specific local-fallback selection unchanged.
    private let managedClient: (any CloudASRTranscribing)?
    private let managedGrants: GatewayGrantCoordinator?
    private let lock = OSAllocatedUnfairLock()
    private var client: CloudASRTranscribing?
    private var usesLocalFallback = false
    private var boundClientSelection: String?
    private var cancelled = false
    private var streamingPipeline: StreamingUtterancePipeline?

    public init(
        store: any ConfigurationStore = AppGroupStore(),
        session: URLSession = .shared,
        localFallback: ASRService? = nil,
        managedClient: (any CloudASRTranscribing)? = nil,
        managedGrants: GatewayGrantCoordinator? = nil
    ) {
        self.store = store
        self.session = session
        self.managedClient = managedClient
        self.managedGrants = managedGrants
        // `SpeechAnalyzerASR` is internal, so it can't appear in a public
        // default argument value — resolve the fallback in the body instead.
        self.localFallback = localFallback ?? SpeechAnalyzerASR()
    }

    /// Whether Flow should prefer utterance-level true streaming for the bound provider.
    public var supportsUtteranceStreaming: Bool {
        if store.credentialSource == .managed {
            return managedClient == nil || managedClient is CloudASRStreamingCapable
        }
        return CloudASRModelCatalog.supportsTrueStreamingASR(for: store.asrProviderId)
    }

    public func resetForNewUtterance() {
        lock.withLock { cancelled = false }
        if usesLocalFallback {
            localFallback.resetForNewUtterance()
        }
    }

    public func warmup(locale: Locale) async {
        bindClientIfNeeded()
        if usesLocalFallback {
            await localFallback.warmup(locale: locale)
            return
        }
        guard let client = lock.withLock({ client }) else { return }
        do {
            try await client.prepare(dictionary: store.personalDictionary)
        } catch {
            OSGLog.asr.warning(
                "cloud ASR vocabulary prepare failed: \(CloudASRLogMetadata.describe(error), privacy: .public)"
            )
        }
    }

    public func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        guard !samples.isEmpty else { return .success("") }
        if Task.isCancelled || lock.withLock({ cancelled }) { return .cancelled }

        bindClientIfNeeded()
        if usesLocalFallback {
            return await localFallback.transcribeChunk(samples: samples, locale: locale)
        }

        guard let client = lock.withLock({ client }) else {
            return .failure(CloudASRError.providerUnsupported.localizedDescription)
        }

        let startedAt = Date()
        do {
            let text = try await client.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                dictionary: store.personalDictionary
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            FlowTrace.transcript(
                "asr.cloud.chunk",
                trimmed,
                "engine=cloud provider=\(store.asrProviderId) samples=\(samples.count) "
                    + "rms=\(FlowTrace.rms(samples)) elapsed=\(FlowTrace.seconds(since: startedAt))s"
            )
            return trimmed.isEmpty ? .success("") : .success(trimmed)
        } catch where ProviderToolCancellation.matches(error) {
            FlowTrace.asr("cloud.chunk.cancelled", "samples=\(samples.count)")
            return .cancelled
        } catch {
            FlowTrace.warn(
                "asr.cloud.chunk.failed",
                "provider=\(store.asrProviderId) samples=\(samples.count) "
                    + "rms=\(FlowTrace.rms(samples)) elapsed=\(FlowTrace.seconds(since: startedAt))s "
                    + "\(CloudASRLogMetadata.describe(error))"
            )
            return .failure(error.localizedDescription)
        }
    }

    /// Utterance-level streaming; if the session cannot start, fall back to
    /// chunked batch on the same mic stream. Mid-stream failures surface as
    /// errors (finalize still has PCM batch fallback).
    public func transcribeUtteranceStreaming(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> ChunkedUtterancePipelineOutcome {
        bindClientIfNeeded()
        if usesLocalFallback {
            let pipeline = ChunkedUtterancePipeline(asr: localFallback, locale: locale)
            return await pipeline.transcribe(stream: stream, onPartial: onPartial)
        }

        guard let streamingClient = lock.withLock({ client as? CloudASRStreamingCapable }) else {
            let pipeline = ChunkedUtterancePipeline(asr: self, locale: locale)
            return await pipeline.transcribe(stream: stream, onPartial: onPartial)
        }

        let session: any CloudASRStreamingSession
        do {
            session = try await streamingClient.openStreamingSession(
                locale: locale,
                dictionary: store.personalDictionary,
                onPartial: onPartial
            )
        } catch where ProviderToolCancellation.matches(error) {
            return .cancelled
        } catch {
            OSGLog.asr.warning(
                "streaming ASR session open failed, using chunked batch: \(CloudASRLogMetadata.describe(error), privacy: .public)"
            )
            let pipeline = ChunkedUtterancePipeline(asr: self, locale: locale)
            return await pipeline.transcribe(stream: stream, onPartial: onPartial)
        }

        let pipeline = StreamingUtterancePipeline(
            client: streamingClient,
            locale: locale,
            dictionary: store.personalDictionary
        )
        lock.withLock { streamingPipeline = pipeline }
        let outcome = await pipeline.transcribe(
            stream: stream,
            onPartial: onPartial,
            preopenedSession: session
        )
        lock.withLock { streamingPipeline = nil }
        return outcome
    }

    public func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        bindClientIfNeeded()
        if usesLocalFallback {
            return localFallback.transcribe(stream: stream, locale: locale)
        }

        if supportsUtteranceStreaming, lock.withLock({ client is CloudASRStreamingCapable }) {
            return AsyncStream { continuation in
                continuation.yield(.capability(onDeviceSupported: false))
                let task = Task {
                    let outcome = await self.transcribeUtteranceStreaming(
                        stream: stream,
                        locale: locale,
                        onPartial: { partial in
                            continuation.yield(.partial(partial))
                        }
                    )
                    switch outcome {
                    case .success(let success):
                        continuation.yield(.final(success.text))
                    case .failure(let message):
                        continuation.yield(.error(message))
                    case .cancelled:
                        break
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                    self.cancel()
                }
            }
        }

        return AsyncStream { continuation in
            continuation.yield(.capability(onDeviceSupported: false))
            let task = Task {
                var samples: [Float] = []
                for await snap in stream {
                    if Task.isCancelled { break }
                    samples.append(contentsOf: snap.samples)
                }
                guard !Task.isCancelled, !self.lock.withLock({ self.cancelled }) else {
                    continuation.finish()
                    return
                }
                guard !samples.isEmpty else {
                    continuation.yield(.error(SharedL10n.string("error.asr.noSpeech")))
                    continuation.finish()
                    return
                }

                switch await self.transcribeChunk(samples: samples, locale: locale) {
                case .success(let text):
                    if text.isEmpty {
                        continuation.yield(.error(SharedL10n.string("error.asr.noSpeech")))
                    } else {
                        continuation.yield(.final(text))
                    }
                case .failure(let message):
                    continuation.yield(.error(message))
                case .cancelled:
                    break
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                self.cancel()
            }
        }
    }

    public func cancel() {
        lock.withLock { cancelled = true }
        let pipeline = lock.withLock { streamingPipeline }
        Task { await pipeline?.cancel() }
        localFallback.cancel()
    }

    private func bindClientIfNeeded() {
        let providerId = store.asrProviderId
        let strategy = CloudASRModelCatalog.strategy(for: providerId)
        let credentialSource = store.credentialSource
        let selection = "\(credentialSource.rawValue):\(providerId)"
        lock.withLock {
            guard boundClientSelection != selection else { return }
            boundClientSelection = selection
            if credentialSource == .managed {
                usesLocalFallback = false
                client = managedClient ?? CloudASRClientFactory.make(
                    store: store,
                    session: session,
                    managedGrants: managedGrants
                )
                return
            }
            usesLocalFallback = strategy == .localFallback
            client = usesLocalFallback
                ? nil
                : CloudASRClientFactory.make(store: store, session: session)
        }
    }
}

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

/// A primed streaming session is opened before the utterance has an owner.
/// Route its callbacks through a mutable relay, then bind the real partial
/// consumer when the mic gesture is committed to an utterance.
private final class CloudASRPartialRelay: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<
        (@Sendable (String) -> Void)?
    >(initialState: nil)

    func bind(_ consumer: @escaping @Sendable (String) -> Void) {
        lock.withLock { $0 = consumer }
    }

    func publish(_ text: String) {
        let consumer = lock.withLock { $0 }
        consumer?(text)
    }
}

/// Uploads PCM only on the user-selected cloud engine path; provider clients
/// reject missing credentials before network transmission. Personal dictionary
/// entries are sent as recognition bias. Mutable client/cancellation state is
/// lock-protected, which is the basis for `@unchecked Sendable`.
public final class CloudASRService: ASRService, @unchecked Sendable {
    private struct PrimedStreamingSession {
        let id: UUID
        let selection: String
        let localeID: String
        let createdAt: ContinuousClock.Instant
        let relay: CloudASRPartialRelay
        let task: Task<any CloudASRStreamingSession, Error>
    }

    /// The gateway closes a session that receives no audio for 15 s (counted
    /// from WebSocket connect). A primed session older than this is never
    /// adopted, leaving headroom for the first audio frame to arrive.
    public static let defaultPrimedSessionMaxAge: Duration = .seconds(10)

    private let store: any ConfigurationStore
    private let session: URLSession
    private let localFallback: ASRService
    /// Optional account-managed path. A nil value preserves existing BYOK and
    /// provider-specific local-fallback selection unchanged.
    private let managedClient: (any CloudASRTranscribing)?
    private let managedGrants: GatewayGrantCoordinator?
    private let primedSessionMaxAge: Duration
    private let lock = OSAllocatedUnfairLock()
    private var client: CloudASRTranscribing?
    private var usesLocalFallback = false
    private var boundClientSelection: String?
    private var cancelled = false
    private var streamingPipeline: StreamingUtterancePipeline?
    private var primedStreamingSession: PrimedStreamingSession?

    public init(
        store: any ConfigurationStore = AppGroupStore(),
        session: URLSession = .shared,
        localFallback: ASRService? = nil,
        managedClient: (any CloudASRTranscribing)? = nil,
        managedGrants: GatewayGrantCoordinator? = nil,
        primedSessionMaxAge: Duration = CloudASRService.defaultPrimedSessionMaxAge
    ) {
        self.store = store
        self.session = session
        self.managedClient = managedClient
        self.managedGrants = managedGrants
        self.primedSessionMaxAge = primedSessionMaxAge
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

    /// Starts the account-managed Volcengine reservation + WebSocket handshake
    /// while the user's finger is still down. The utterance adopts this session
    /// moments later, removing those network round trips from first-partial
    /// latency without sending audio before recording actually begins.
    public func primeUtteranceStreaming(locale: Locale) {
        bindClientIfNeeded()
        guard store.credentialSource == .managed,
              let selection = lock.withLock({ boundClientSelection }),
              let streamingClient = lock.withLock({
                  client as? any CloudASRStreamingCapable
              }) else {
            return
        }

        let localeID = locale.identifier(.bcp47)
        let alreadyPrimed = lock.withLock { () -> Bool in
            guard let current = primedStreamingSession else { return false }
            return current.selection == selection
                && current.localeID == localeID
                && !isExpired(current)
        }
        guard !alreadyPrimed else { return }

        cancelPrimedUtteranceStreaming()
        let id = UUID()
        let relay = CloudASRPartialRelay()
        let dictionary = store.personalDictionary
        let task = Task.detached(priority: .userInitiated) {
            try await streamingClient.openStreamingSession(
                locale: locale,
                dictionary: dictionary,
                onPartial: { relay.publish($0) }
            )
        }
        lock.withLock {
            primedStreamingSession = PrimedStreamingSession(
                id: id,
                selection: selection,
                localeID: localeID,
                createdAt: .now,
                relay: relay,
                task: task
            )
        }
        // Self-expire: the keyboard's cancel command may never arrive (the
        // extension can be dismissed, or a start can fail before adoption).
        let maxAge = primedSessionMaxAge
        Task { [weak self] in
            try? await Task.sleep(for: maxAge)
            guard let self, let expired = self.takePrimedSession(id: id) else { return }
            FlowTrace.asr("cloud.stream.primeDiscarded", "reason=expired")
            Self.close(expired)
        }
        FlowTrace.asr(
            "cloud.stream.primeStarted",
            "locale=\(localeID) selection=\(selection)"
        )
    }

    public func cancelPrimedUtteranceStreaming() {
        guard let primed = takePrimedSession() else { return }
        Self.close(primed)
    }

    /// Removes the primed session; with an `id`, only if it is still that one.
    private func takePrimedSession(id: UUID? = nil) -> PrimedStreamingSession? {
        lock.withLock {
            guard let current = primedStreamingSession,
                  id == nil || current.id == id else {
                return nil
            }
            primedStreamingSession = nil
            return current
        }
    }

    private func isExpired(_ primed: PrimedStreamingSession) -> Bool {
        ContinuousClock.now - primed.createdAt >= primedSessionMaxAge
    }

    /// Closes a primed session without cancelling its open task. Cancelling
    /// mid-reservation can leave a reserved, never-connected gateway session
    /// holding credits and a concurrency slot until its connect timeout;
    /// letting the open finish and then closing releases it immediately.
    private static func close(_ primed: PrimedStreamingSession) {
        Task {
            if let session = try? await primed.task.value {
                session.cancel()
            }
        }
    }

    /// Returns the primed session only if it still matches this utterance and
    /// can accept audio. Anything else is closed and the caller opens a fresh
    /// session, so priming can never make an utterance fail.
    private func adoptPrimedSession(
        _ primed: PrimedStreamingSession?,
        selection: String?,
        localeID: String,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> (any CloudASRStreamingSession)? {
        guard let primed else { return nil }
        guard primed.selection == selection, primed.localeID == localeID else {
            FlowTrace.asr("cloud.stream.primeDiscarded", "reason=mismatch")
            Self.close(primed)
            return nil
        }
        guard !isExpired(primed) else {
            FlowTrace.asr("cloud.stream.primeDiscarded", "reason=expired")
            Self.close(primed)
            return nil
        }

        primed.relay.bind(onPartial)
        let session: any CloudASRStreamingSession
        do {
            session = try await primed.task.value
        } catch {
            FlowTrace.asr(
                "cloud.stream.primeDiscarded",
                "reason=openFailed \(CloudASRLogMetadata.describe(error))"
            )
            return nil
        }
        guard session.acceptsAudio else {
            FlowTrace.asr("cloud.stream.primeDiscarded", "reason=closed")
            session.cancel()
            return nil
        }
        let ageMs = Int((ContinuousClock.now - primed.createdAt) / .milliseconds(1))
        FlowTrace.asr(
            "cloud.stream.primeAdopted",
            "locale=\(localeID) ageMs=\(ageMs)"
        )
        return session
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
        // A previous utterance's abort/failure leaves `cancelled` set, which
        // would make this utterance's batch fallback (`transcribeChunk`)
        // return `.cancelled` for the rest of the Flow session.
        lock.withLock { cancelled = false }
        if usesLocalFallback {
            let pipeline = ChunkedUtterancePipeline(asr: localFallback, locale: locale)
            return await pipeline.transcribe(stream: stream, onPartial: onPartial)
        }

        guard let streamingClient = lock.withLock({ client as? CloudASRStreamingCapable }) else {
            cancelPrimedUtteranceStreaming()
            let pipeline = ChunkedUtterancePipeline(asr: self, locale: locale)
            return await pipeline.transcribe(stream: stream, onPartial: onPartial)
        }

        let selection = lock.withLock { boundClientSelection }
        let localeID = locale.identifier(.bcp47)
        // Every utterance either adopts the primed session or closes it.
        let primed = takePrimedSession()

        let session: any CloudASRStreamingSession
        do {
            if let adopted = await adoptPrimedSession(
                primed,
                selection: selection,
                localeID: localeID,
                onPartial: onPartial
            ) {
                session = adopted
            } else {
                session = try await streamingClient.openStreamingSession(
                    locale: locale,
                    dictionary: store.personalDictionary,
                    onPartial: onPartial
                )
            }
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
        cancelPrimedUtteranceStreaming()
        let pipeline = lock.withLock { streamingPipeline }
        Task { await pipeline?.cancel() }
        localFallback.cancel()
    }

    private func bindClientIfNeeded() {
        let providerId = store.asrProviderId
        let strategy = CloudASRModelCatalog.strategy(for: providerId)
        let credentialSource = store.credentialSource
        let selection = "\(credentialSource.rawValue):\(providerId)"
        let stalePrime = lock.withLock { () -> PrimedStreamingSession? in
            guard boundClientSelection != selection else { return nil }
            let stalePrime = primedStreamingSession
            primedStreamingSession = nil
            boundClientSelection = selection
            if credentialSource == .managed {
                usesLocalFallback = false
                client = managedClient ?? CloudASRClientFactory.make(
                    store: store,
                    session: session,
                    managedGrants: managedGrants
                )
                return stalePrime
            }
            usesLocalFallback = strategy == .localFallback
            client = usesLocalFallback
                ? nil
                : CloudASRClientFactory.make(store: store, session: session)
            return stalePrime
        }
        if let stalePrime {
            Self.close(stalePrime)
        }
    }
}

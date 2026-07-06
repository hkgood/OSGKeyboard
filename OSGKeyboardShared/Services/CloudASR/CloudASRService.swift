// CloudASRService.swift
// OSGKeyboard · Shared
//
// Cloud-engine ASR: uploads PCM chunks to the user's configured provider
// with personal-dictionary bias. Moonshot falls back to on-device ASR.

import Foundation
import os

public final class CloudASRService: ASRService, @unchecked Sendable {
    private let store: AppGroupStore
    private let session: URLSession
    private let localFallback: ASRService
    private let lock = OSAllocatedUnfairLock()
    private var client: CloudASRTranscribing?
    private var usesLocalFallback = false
    private var boundProviderId: String?
    private var cancelled = false

    public init(
        store: AppGroupStore = AppGroupStore(),
        session: URLSession = .shared,
        localFallback: ASRService? = nil
    ) {
        self.store = store
        self.session = session
        // `SpeechAnalyzerASR` is internal, so it can't appear in a public
        // default argument value — resolve the fallback in the body instead.
        self.localFallback = localFallback ?? SpeechAnalyzerASR()
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
            OSGLog.asr.warning("cloud ASR vocabulary prepare failed: \(error.localizedDescription, privacy: .public)")
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

        do {
            let text = try await client.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                dictionary: store.personalDictionary
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .success("") : .success(trimmed)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    public func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        bindClientIfNeeded()
        if usesLocalFallback {
            return localFallback.transcribe(stream: stream, locale: locale)
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
        localFallback.cancel()
    }

    private func bindClientIfNeeded() {
        let providerId = store.providerId
        let strategy = CloudASRModelCatalog.strategy(for: providerId)
        lock.withLock {
            guard boundProviderId != providerId else { return }
            boundProviderId = providerId
            usesLocalFallback = strategy == .localFallback
            client = usesLocalFallback
                ? nil
                : CloudASRClientFactory.make(store: store, session: session)
        }
    }
}

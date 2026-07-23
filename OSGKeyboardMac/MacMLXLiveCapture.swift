// MacMLXLiveCapture.swift
// OSGKeyboard · Mac
//
// MLX streaming live capture: feed mic snapshots, tail drain, finalize.

import Foundation
import os

enum MacMLXLiveCapture {
    private static let tailDrainPolicy = FlowCaptureTailDrainPolicy(
        silenceRMSThreshold: 0.015,
        silenceDurationSeconds: 0.35,
        maxDrainSeconds: 0.75
    )

    /// Runs MLX streaming ASR until `finishSignal` fires, then tail-drains and finalizes.
    static func run(
        audioStream: AsyncStream<AudioBufferSnapshot>,
        finishSignal: AsyncStream<Void>,
        store: AppGroupStore,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> MacLiveASRCaptureResult {
        let locale = Locale(identifier: store.localeId.isEmpty ? "zh-CN" : store.localeId)
        let bias = resolveBias(store: store, locale: locale)

        guard let model = MacLocalASRService.selectedModelDefinition(),
              model.backend == .mlx,
              MacLocalASRService.isModelInstalled(model) else {
            return MacLiveASRCaptureResult(
                raw: "",
                chunkWarning: nil,
                localBias: bias,
                shouldFallbackToBatch: true
            )
        }

        do {
            try await MacMLXStreamingASRProvider.shared.prepare(model: model)
            let session = try await MacMLXStreamingASRProvider.shared.makeSession(
                model: model,
                bias: bias,
                locale: locale
            )
            session.onDisplayUpdate = { text in
                onPartial(text)
            }

            let drainTracker = FlowCaptureDrainTracker()
            let draining = OSAllocatedUnfairLock(initialState: false)
            let pendingFeed = OSAllocatedUnfairLock(initialState: [Float]())
            let feedIntervalSamples = 1_600 // 100 ms @ 16 kHz

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    // Only the first finish signal matters. The stream is only
                    // *yielded* to (never `finish()`ed) on the deferred-stop
                    // path, so without this `break` the loop would await a
                    // second element forever and hang the whole task group
                    // until the 120s hard timeout.
                    for await _ in finishSignal {
                        draining.withLock { $0 = true }
                        drainTracker.beginDrain()
                        break
                    }
                }

                group.addTask {
                    for await snapshot in audioStream {
                        if Task.isCancelled { break }
                        if draining.withLock({ $0 }) {
                            drainTracker.noteAudio(samples: snapshot.samples, policy: tailDrainPolicy)
                            let decision = drainTracker.shouldFinish(policy: tailDrainPolicy)
                            if decision.finished { break }
                        }
                        pendingFeed.withLock { buffer in
                            buffer.append(contentsOf: snapshot.samples)
                            while buffer.count >= feedIntervalSamples {
                                let chunk = Array(buffer.prefix(feedIntervalSamples))
                                buffer.removeFirst(feedIntervalSamples)
                                session.feed(samples: chunk)
                            }
                        }
                    }
                }
            }

            let remainder = pendingFeed.withLock { $0 }
            if !remainder.isEmpty, !Task.isCancelled {
                session.feed(samples: remainder)
            }

            if Task.isCancelled {
                session.cancel()
                return MacLiveASRCaptureResult(
                    raw: "",
                    chunkWarning: nil,
                    localBias: bias,
                    shouldFallbackToBatch: true
                )
            }

            let raw = try await session.stop()
            if MacHallucinationFilter.shouldDiscardHotwordDump(
                text: raw,
                peakRMS: session.peakAudioRMS(),
                bias: bias
            ) {
                return MacLiveASRCaptureResult(
                    raw: "",
                    chunkWarning: nil,
                    localBias: bias,
                    shouldFallbackToBatch: true
                )
            }

            return MacLiveASRCaptureResult(
                raw: raw,
                chunkWarning: nil,
                localBias: bias,
                shouldFallbackToBatch: false
            )
        } catch {
            return MacLiveASRCaptureResult(
                raw: "",
                chunkWarning: nil,
                localBias: bias,
                shouldFallbackToBatch: true
            )
        }
    }

    private static func resolveBias(store: AppGroupStore, locale: Locale) -> LocalASRBiasPayload? {
        MacAppContextService.captureAndPersist(to: store)
        let capabilities = MacLocalASRService.currentCapabilities()
        let bias = LocalASRBiasAdapter.adapt(
            LocalASRBiasRequest(
                dictionary: store.personalDictionary,
                locale: locale,
                frontAppBundleId: MacAppContextService.frontmostBundleIdentifier(),
                capabilities: capabilities
            )
        )
        LocalASRBiasDiagnosticsStore.save(
            payload: bias,
            modelId: MacLocalASRService.selectedModelDefinition()?.id,
            backendLabel: MacLocalASRService.currentBackendLabel()
        )
        return bias
    }
}

// Qwen3ASRService.swift
// OSGKeyboard · Main App
//
// On-device ASR via Qwen3-ASR-0.6B CoreML (Neural Engine + CPU). Uses the
// MLX-free `transcribeBackgroundSafe` path so Flow dictation works while the
// host app is backgrounded (no Metal GPU).

import Foundation
import AVFoundation
import os
import OSGKeyboardShared
@preconcurrency import Qwen3ASR

struct Qwen3ASRServiceProvider: ASRServiceProvider {
    let backend: LocalASRBackend = .qwen3ASR
    func make() -> ASRService { Qwen3ASRService() }
}

final class Qwen3ASRService: ASRService, @unchecked Sendable {

    private enum TranscribeConstants {
        static let sampleRate = 16_000
        /// CoreML encoder is exported for 30 s windows — align with Flow chunking.
        static let chunkDurationSeconds = Int(FlowUtteranceChunkConfig.flowDefault.maxChunkDurationSeconds)
    }

    private let lock = OSAllocatedUnfairLock()
    private var currentTask: Task<Void, Never>?
    private var cancelled = false

    private var model: CoreMLASRModel?
    private var loadError: Error?
    private var loadingTask: Task<CoreMLASRModel, Error>?

    private func resolveModel() async throws -> CoreMLASRModel {
        if let model = lock.withLock({ self.model }) { return model }
        if let err = lock.withLock({ self.loadError }) { throw err }

        guard ModelManager.weightsOnDisk(for: .qwen3ASR) else {
            throw ASRServiceError.modelNotDownloaded
        }

        guard OnDeviceMLRuntime.supportsOnDeviceQwen3 else {
            throw ASRServiceError.unsupportedOS
        }

        let task: Task<CoreMLASRModel, Error> = lock.withLock {
            if let existing = loadingTask { return existing }
            let new = Task<CoreMLASRModel, Error> { [weak self] in
                guard let self else { throw ASRServiceError.notReady }
                let cacheDir = ModelManager.cacheDirectory(for: .qwen3ASR)
                let loaded = try await CoreMLASRModel.fromPretrained(
                    tokenizerModelId: OnDeviceModel.qwen3ASR.tokenizerRepoId,
                    cacheDir: cacheDir,
                    offlineMode: true,
                    progressHandler: { @Sendable _, _ in }
                )
                try loaded.warmUp()
                self.lock.withLock { self.model = loaded }
                return loaded
            }
            loadingTask = new
            return new
        }
        do {
            let model = try await task.value
            return model
        } catch {
            lock.withLock { self.loadError = error }
            throw error
        }
    }

    func warmUp() async throws {
        FlowDiagnostics.log("Qwen3ASR CoreML warmUp start")
        resetForNewUtterance()
        _ = try await resolveModel()
        FlowDiagnostics.log("Qwen3ASR CoreML warmUp done")
    }

    func resetForNewUtterance() {
        lock.withLock { cancelled = false }
    }

    var isModelInMemory: Bool {
        lock.withLock { model != nil }
    }

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { continuation in
            continuation.yield(.capability(onDeviceSupported: true))

            let task = Task { [weak self] in
                guard let self else { return }
                defer { self.lock.withLock { self.currentTask = nil } }

                var samples: [Float] = []
                samples.reserveCapacity(
                    Int(Double(TranscribeConstants.sampleRate) * FlowSessionKeys.maxUtteranceDuration) + 16_000
                )
                for await snap in stream {
                    if Task.isCancelled || self.cancelledNow() { break }
                    samples.append(contentsOf: snap.samples)
                }
                guard !Task.isCancelled, !self.cancelledNow() else {
                    continuation.finish()
                    return
                }
                if samples.isEmpty {
                    continuation.yield(.error(SharedL10n.string("error.asr.noSpeech")))
                    continuation.finish()
                    return
                }

                do {
                    let model = try await self.resolveModel()
                    let language = Self.languageHint(from: locale)
                    let durationSec = Double(samples.count) / 16_000.0
                    FlowDiagnostics.log(
                        "Qwen3ASR CoreML transcribe start samples=\(samples.count) " +
                        "duration=\(String(format: "%.1f", durationSec))s"
                    )
                    let text = self.transcribeInChunks(
                        model: model,
                        samples: samples,
                        language: language
                    )
                    FlowDiagnostics.log("Qwen3ASR CoreML transcribe done chars=\(text.count)")
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        continuation.yield(.error(SharedL10n.string("error.asr.noSpeech")))
                    } else {
                        continuation.yield(.final(trimmed))
                    }
                    continuation.finish()
                } catch {
                    Self.debug("Qwen3ASR.transcribe failed: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
            self.lock.withLock { self.currentTask = task }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.cancel()
            }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            currentTask?.cancel()
            currentTask = nil
        }
    }

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        if cancelledNow() || Task.isCancelled { return .cancelled }
        guard !samples.isEmpty else { return .success("") }

        do {
            let model = try await resolveModel()
            let language = Self.languageHint(from: locale)
            let text = model.transcribeBackgroundSafe(
                audio: samples,
                sampleRate: TranscribeConstants.sampleRate,
                language: language
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("[CoreML error:") {
                return .failure(text)
            }
            return .success(text)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failure(message)
        }
    }

    private func cancelledNow() -> Bool {
        lock.withLock { cancelled }
    }

    private func transcribeInChunks(
        model: CoreMLASRModel,
        samples: [Float],
        language: String?
    ) -> String {
        let chunkSize = TranscribeConstants.sampleRate * TranscribeConstants.chunkDurationSeconds
        guard samples.count > chunkSize else {
            return model.transcribeBackgroundSafe(
                audio: samples,
                sampleRate: TranscribeConstants.sampleRate,
                language: language
            )
        }

        var parts: [String] = []
        parts.reserveCapacity((samples.count + chunkSize - 1) / chunkSize)
        var offset = 0
        var chunkIndex = 0
        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunk = Array(samples[offset..<end])
            offset = end
            chunkIndex += 1
            FlowDiagnostics.log(
                "Qwen3ASR CoreML chunk \(chunkIndex) samples=\(chunk.count) " +
                "offset=\(offset - chunk.count)"
            )
            let piece = model.transcribeBackgroundSafe(
                audio: chunk,
                sampleRate: TranscribeConstants.sampleRate,
                language: language
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty, !piece.hasPrefix("[CoreML error:") {
                parts.append(piece)
            }
        }
        return parts.joined(separator: " ")
    }

    private static func languageHint(from locale: Locale) -> String? {
        let id = locale.identifier.lowercased()
        if id.hasPrefix("zh") { return "zh" }
        if id.hasPrefix("en") { return "en" }
        return locale.language.languageCode?.identifier
    }

    private static func debug(_ message: String) {
        #if DEBUG
        print("🎙️[Qwen3ASR] \(message)")
        #endif
    }
}

private enum ASRServiceError: Error, LocalizedError {
    case notReady
    case modelNotDownloaded
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .notReady:
            return nil
        case .modelNotDownloaded:
            return AppL10n.string("asr.error.modelNotDownloaded")
        case .unsupportedOS:
            return AppL10n.string("asr.error.unsupportedOS")
        }
    }
}

// OnDeviceModelWarmup.swift
// OSGKeyboard · Main App
//
// Preloads on-device ASR weights for Flow sessions.

import Foundation
import OSGKeyboardShared

@MainActor
final class OnDeviceModelWarmup: ObservableObject {

    static let shared = OnDeviceModelWarmup()

    enum Phase: Equatable {
        case idle
        case warming
        case ready
        case failed(String)
        case notNeeded

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    @Published private(set) var phase: Phase = .idle

    /// Bumped on `invalidate()` and each new warm-up so cancelled tasks
    /// cannot leave `phase` stuck on `.warming`.
    private var warmupGeneration = 0
    private var warmupTask: Task<Void, Never>?
    private var qwenASRService: Qwen3ASRService?
    private var speechAnalyzerService: ASRService?
    private var cloudASRService: ASRService?

    private init() {}

    /// Loads ASR into memory when the local stack is ready on disk.
    func warmUpIfNeeded(force: Bool = false) {
        let store = AppGroupStore()
        guard store.engineMode == "local" else {
            resetInstances()
            phase = .notNeeded
            publishMemoryReady(false)
            return
        }

        guard store.localASRBackend != .qwen3ASR || OnDeviceMLRuntime.supportsOnDeviceQwen3 else {
            resetInstances()
            phase = .notNeeded
            publishMemoryReady(false)
            return
        }

        guard OnDeviceModelStatus.isLocalStackReady(asrBackend: store.localASRBackend) else {
            resetInstances()
            phase = .idle
            publishMemoryReady(false)
            return
        }

        var shouldForce = force
        if phase == .ready, !shouldForce {
            if needsModelReload() {
                shouldForce = true
            } else {
                publishMemoryReady(true)
                return
            }
        }
        if phase == .warming { return }
        if case .failed = phase, !shouldForce { return }

        warmupTask?.cancel()
        warmupGeneration += 1
        let generation = warmupGeneration
        phase = .warming
        publishMemoryReady(false)

        let asrBackend = store.localASRBackend
        warmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.performWarmup(asrBackend: asrBackend)
                guard generation == self.warmupGeneration, !Task.isCancelled else { return }
                self.phase = .ready
                self.publishMemoryReady(true)
            } catch {
                guard generation == self.warmupGeneration, !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                self.phase = .failed(message)
                self.publishMemoryReady(false)
            }
        }
    }

    func invalidate() {
        warmupGeneration += 1
        warmupTask?.cancel()
        warmupTask = nil
        resetInstances()
        phase = .idle
        publishMemoryReady(false)
    }

    /// Called when returning from background — re-verify CoreML weights and
    /// unstick a warmup that was frozen while the app was suspended.
    func ensureReadyAfterBackground() {
        let store = AppGroupStore()
        guard store.engineMode == "local" else {
            phase = .notNeeded
            publishMemoryReady(false)
            return
        }

        guard OnDeviceModelStatus.isLocalStackReady(asrBackend: store.localASRBackend) else {
            phase = .idle
            publishMemoryReady(false)
            return
        }

        switch phase {
        case .warming, .ready:
            if needsModelReload() {
                warmUpIfNeeded(force: true)
            }
        case .failed, .idle:
            warmUpIfNeeded(force: true)
        case .notNeeded:
            break
        }
    }

    func asrService(engineMode: String, localBackend: LocalASRBackend) -> ASRService {
        if engineMode != "local" {
            if cloudASRService == nil {
                cloudASRService = ASRServiceFactory.make(
                    engineMode: engineMode,
                    localBackend: localBackend
                )
            }
            return cloudASRService!
        }

        switch localBackend {
        case .qwen3ASR:
            if qwenASRService == nil {
                qwenASRService = Qwen3ASRService()
            }
            return qwenASRService!
        case .speechAnalyzer:
            if speechAnalyzerService == nil {
                speechAnalyzerService = ASRServiceFactory.make(
                    engineMode: "local",
                    localBackend: .speechAnalyzer
                )
            }
            return speechAnalyzerService!
        }
    }

    // MARK: - Internals

    private func performWarmup(asrBackend: LocalASRBackend) async throws {
        switch asrBackend {
        case .qwen3ASR:
            if qwenASRService == nil {
                qwenASRService = Qwen3ASRService()
            }
            FlowDiagnostics.log("warmup ASR start backend=qwen3ASR")
            try await qwenASRService!.warmUp()
            FlowDiagnostics.log("warmup ASR done")
        case .speechAnalyzer:
            FlowDiagnostics.log("warmup skipped — speechAnalyzer backend")
        }
    }

    private func resetInstances() {
        qwenASRService = nil
        speechAnalyzerService = nil
        cloudASRService = nil
    }

    private func publishMemoryReady(_ ready: Bool) {
        OnDeviceModelStatus.setModelsLoadedInMemory(ready)
    }

    private func needsModelReload() -> Bool {
        let store = AppGroupStore()
        guard store.engineMode == "local", store.localASRBackend == .qwen3ASR else {
            return false
        }
        return qwenASRService?.isModelInMemory != true
    }
}

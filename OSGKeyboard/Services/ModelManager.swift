// ModelManager.swift
// OSGKeyboard · Main App
//
// Owns the lifecycle of on-device ML models that back the local
// ASR backend (Qwen3-ASR-0.6B CoreML, ~1.6 GB).
//
// `runDownload` fetches CoreML bundles + tokenizer files — it does
// not load models into memory (warm-up happens in `OnDeviceModelWarmup`).
// Weights land under `~/Library/Caches/qwen3-speech/` using the Hub
// layout from `HuggingFaceDownloader`.
//
// Why this lives in the host app: the ASR model is loaded via
// soniqo/speech-swift, which is only linked into the main App
// target (Qwen3Speech pulls mlx-swift as a transitive dependency).
//
// Mirror selection: resolved automatically at download time via
// `ModelDownloadSourcePicker` (latency probe + locale fallback).

import Foundation
import SwiftUI
import OSGKeyboardShared
import Qwen3ASR

private enum Qwen3CoreMLDownloadArtifacts {
    static let coreMLBundleGlobs = [
        "encoder.mlmodelc/**",
        "embedding.mlmodelc/**",
        "decoder_part1.mlmodelc/**",
        "decoder_part2.mlmodelc/**",
        "config.json",
    ]

    static let tokenizerFiles = [
        "vocab.json",
        "merges.txt",
        "tokenizer_config.json",
    ]
}

/// Where on-device model weights are downloaded from.
enum ModelDownloadSource: String, CaseIterable, Identifiable, Sendable {
    case huggingface
    case modelScope

    var id: String { rawValue }

    var registry: ModelRegistry {
        switch self {
        case .huggingface: return .huggingFace()
        case .modelScope:  return .modelScope()
        }
    }

    /// Host shown in error messages.
    var hostLabel: String {
        switch self {
        case .huggingface: return "huggingface.co"
        case .modelScope:  return "modelscope.cn"
        }
    }
}

enum ModelDownloadState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(String)

    var isTerminal: Bool {
        switch self {
        case .downloaded, .failed: return true
        case .notDownloaded, .downloading: return false
        }
    }

    var downloadProgress: Double? {
        if case .downloading(let progress) = self { return progress }
        return nil
    }
}

/// Per-model state tracked by `ModelManager`. The manager keeps a
/// dictionary of these and re-emits it on the main actor whenever
/// any field changes.
struct ModelState: Equatable, Sendable {
    var download: ModelDownloadState
    var lastError: String?
}

/// Observable holder that the Settings UI binds to. All mutating
/// methods dispatch onto the main actor so SwiftUI views can
/// observe without ceremony.
@MainActor
final class ModelManager: ObservableObject {

    static let shared = ModelManager()

    @Published private(set) var states: [OnDeviceModel: ModelState] = [:]
    @Published private(set) var activeDownloads: Set<OnDeviceModel> = []

    private var downloadTasks: [OnDeviceModel: Task<Void, Never>] = [:]

    init() {
        for model in OnDeviceModel.allCases {
            states[model] = ModelState(download: .notDownloaded, lastError: nil)
        }
        refreshAll()
    }

    // MARK: - Queries

    /// Synchronous check on whether the model is already on disk.
    /// Used by the UI to decide whether to show "Download" or
    /// "Delete". Doesn't touch the network.
    func isDownloaded(_ model: OnDeviceModel) -> Bool {
        Self.weightsOnDisk(for: model)
    }

    /// Disk-only probe safe to call from background ASR tasks.
    /// Returns `false` until the user downloads via Settings.
    nonisolated static func weightsOnDisk(for model: OnDeviceModel) -> Bool {
        existingCacheDirectory(for: model) != nil
    }

    /// Approximate on-disk bytes used by the model directory. Used
    /// by the Settings "Storage" badge.
    func onDiskBytes(_ model: OnDeviceModel) -> Int64 {
        guard let dir = Self.existingCacheDirectory(for: model) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    // MARK: - Mutations

    /// Triggers a background download of the model. The call returns
    /// immediately; observe `states[model].download` for progress.
    /// Calling this while a download is in progress is a no-op.
    func startDownload(_ model: OnDeviceModel) {
        if activeDownloads.contains(model) { return }
        if isDownloaded(model) {
            states[model]?.download = .downloaded
            return
        }
        activeDownloads.insert(model)
        states[model] = ModelState(download: .downloading(progress: 0), lastError: nil)
        publishStatusToAppGroup()

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let primary = await ModelDownloadSourcePicker.resolve()
            do {
                try await self.runDownload(model, registry: primary.registry)
            } catch is CancellationError {
                await self.finishDownloadCancelled(model)
            } catch {
                let fallback = ModelDownloadSourcePicker.alternate(to: primary)
                await self.reportDownloadProgress(model, fraction: 0, monotonic: false)
                do {
                    try await self.runDownload(model, registry: fallback.registry)
                } catch is CancellationError {
                    await self.finishDownloadCancelled(model)
                } catch {
                    await self.finishDownloadFailed(model, error: error)
                }
            }
        }
        downloadTasks[model] = task
    }

    func cancelDownload(_ model: OnDeviceModel) {
        downloadTasks[model]?.cancel()
        downloadTasks[model] = nil
        activeDownloads.remove(model)
        states[model] = ModelState(download: .notDownloaded, lastError: nil)
        publishStatusToAppGroup()
    }

    func deleteModel(_ model: OnDeviceModel) {
        for dir in Self.candidateCacheDirectories(for: model) {
            try? FileManager.default.removeItem(at: dir)
        }
        states[model] = ModelState(download: .notDownloaded, lastError: nil)
        publishStatusToAppGroup()
        OnDeviceModelWarmup.shared.invalidate()
    }

    /// Cheap refresh that re-reads the on-disk state for every
    /// tracked model. Called from `init` and after a successful
    /// download so the Settings row updates from "Downloading…" to
    /// "Downloaded · 1.4 GB" without needing a separate notifier.
    func refreshAll() {
        for model in OnDeviceModel.allCases {
            if activeDownloads.contains(model) { continue }
            if isDownloaded(model) {
                states[model] = ModelState(download: .downloaded, lastError: nil)
            } else if case .failed = states[model]?.download {
                // Preserve any existing failure message so the UI
                // can show "Download failed: <reason>" instead of
                // resetting it back to "Not downloaded" every
                // refresh.
                continue
            } else {
                states[model] = ModelState(download: .notDownloaded, lastError: states[model]?.lastError)
            }
        }
        publishStatusToAppGroup()
    }

    /// Mirror disk/download state into the App Group for the keyboard
    /// extension, which cannot probe the host app's Caches folder.
    private func publishStatusToAppGroup() {
        for model in OnDeviceModel.allCases {
            let downloaded: Bool
            let progress: Double?
            switch states[model]?.download {
            case .downloaded:
                downloaded = true
                progress = nil
            case .downloading(let fraction):
                downloaded = false
                progress = fraction
            case .failed, .notDownloaded, .none:
                downloaded = isDownloaded(model)
                progress = nil
            }
            OnDeviceModelStatus.setDownloaded(downloaded, for: model)
            OnDeviceModelStatus.setProgress(progress, for: model)
        }
        scheduleWarmupIfNeeded()
    }

    private func scheduleWarmupIfNeeded() {
        let config = ProviderConfig.shared
        guard config.isLocalEngine else {
            OnDeviceModelWarmup.shared.invalidate()
            return
        }
        if OnDeviceModelStatus.isLocalStackReady(asrBackend: config.localASRBackend) {
            // Do not force-restart an in-flight warm-up — `publishStatusToAppGroup`
            // runs on download progress ticks and would otherwise cancel load
            // mid-flight, leaving the UI stuck on "warming".
            OnDeviceModelWarmup.shared.warmUpIfNeeded()
        } else {
            OnDeviceModelWarmup.shared.invalidate()
        }
    }

    // MARK: - Internals

    /// Runs off the main actor; updates `@Published` state via `MainActor.run`.
    /// Throws on failure so `startDownload` can fall back to the alternate mirror.
    nonisolated private func runDownload(_ model: OnDeviceModel, registry: ModelRegistry) async throws {
        switch model {
        case .qwen3ASR:
            try await Self.downloadQwen3CoreMLWeights(
                model: model,
                registry: registry,
                progressHandler: { @Sendable [weak self] fraction, _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.reportDownloadProgress(model, fraction: fraction)
                    }
                }
            )
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            self.activeDownloads.remove(model)
            self.downloadTasks[model] = nil
            self.states[model] = ModelState(download: .downloaded, lastError: nil)
            self.publishStatusToAppGroup()
            let config = ProviderConfig.shared
            if config.isLocalEngine,
               OnDeviceModelStatus.isLocalStackReady(asrBackend: config.localASRBackend) {
                // Retry warm-up after a prior load failure once weights land on disk.
                OnDeviceModelWarmup.shared.warmUpIfNeeded(force: true)
            }
        }
    }

    nonisolated private func finishDownloadCancelled(_ model: OnDeviceModel) async {
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.activeDownloads.remove(model)
            self.downloadTasks[model] = nil
            self.states[model] = ModelState(download: .notDownloaded, lastError: nil)
            self.publishStatusToAppGroup()
        }
    }

    nonisolated private func finishDownloadFailed(_ model: OnDeviceModel, error: Error) async {
        let message = Self.userFacingDownloadError(error)
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.activeDownloads.remove(model)
            self.downloadTasks[model] = nil
            self.states[model] = ModelState(download: .failed(message), lastError: message)
            self.publishStatusToAppGroup()
        }
    }

    /// Updates UI progress. By default keeps the bar monotonic so brief
    /// per-file jumps inside the downloader never move backwards.
    private func reportDownloadProgress(
        _ model: OnDeviceModel,
        fraction: Double,
        monotonic: Bool = true
    ) {
        let clamped = min(max(fraction, 0), 1)
        let previous = states[model]?.download.downloadProgress ?? 0
        let value = monotonic ? max(previous, clamped) : clamped
        states[model] = ModelState(download: .downloading(progress: value), lastError: nil)
        publishStatusToAppGroup()
    }

    /// Short, user-readable download failure text for Settings UI.
    nonisolated private static func userFacingDownloadError(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if raw.localizedCaseInsensitiveContains("metadata") {
            return AppL10n.string("settings.models.error.metadata")
        }
        if raw.localizedCaseInsensitiveContains("offline mode") {
            return AppL10n.string("settings.models.error.offline")
        }
        if raw.count > 280 {
            return String(raw.prefix(277)) + "…"
        }
        return raw
    }

    /// Resolve on-disk cache directories for a model. Matches the layout
    /// `HuggingFaceDownloader.getCacheDirectory(for:)` uses in Qwen3Speech.
    nonisolated static func candidateCacheDirectories(for model: OnDeviceModel) -> [URL] {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("qwen3-speech", isDirectory: true)
        let repoId = model.repoId
        var candidates: [URL] = []

        // Hub-style path (current default).
        let parts = repoId.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count == 2 {
            candidates.append(
                base
                    .appendingPathComponent("models/\(parts[0])/\(parts[1])", isDirectory: true)
            )
        }

        // Legacy flat path kept by HuggingFaceDownloader for backward compat.
        let sanitized = repoId.replacingOccurrences(of: "/", with: "_")
        candidates.append(base.appendingPathComponent(sanitized, isDirectory: true))

        // Older OSGKeyboard probe paths (pre-alignment); delete still sweeps these.
        switch model {
        case .qwen3ASR:
            candidates.append(base.appendingPathComponent("Qwen3ASR", isDirectory: true))
            candidates.append(
                base.appendingPathComponent("models/aufklarer/Qwen3-ASR-0.6B-MLX-4bit", isDirectory: true)
            )
            candidates.append(base.appendingPathComponent("aufklarer_Qwen3-ASR-0.6B-MLX-4bit", isDirectory: true))
        }

        return candidates
    }

    /// First candidate directory that already contains downloaded weights.
    nonisolated static func existingCacheDirectory(for model: OnDeviceModel) -> URL? {
        candidateCacheDirectories(for: model).first { dir in
            weightsExist(in: dir, model: model)
        }
    }

    nonisolated private static func weightsExist(in directory: URL, model: OnDeviceModel) -> Bool {
        let fm = FileManager.default
        switch model {
        case .qwen3ASR:
            let encoder = directory.appendingPathComponent("encoder.mlmodelc", isDirectory: true)
            let decoder = directory.appendingPathComponent("decoder_part1.mlmodelc", isDirectory: true)
            let vocab = directory.appendingPathComponent("vocab.json")
            return fm.fileExists(atPath: encoder.path)
                && fm.fileExists(atPath: decoder.path)
                && fm.fileExists(atPath: vocab.path)
        }
    }

    // MARK: - CoreML download

    /// Downloads CoreML encoder/decoder bundles and tokenizer files into one cache dir.
    nonisolated static func downloadQwen3CoreMLWeights(
        model: OnDeviceModel,
        registry: ModelRegistry,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        let coreMLId = model.repoId
        let tokenizerId = model.tokenizerRepoId
        let dir = try HuggingFaceDownloader.getCacheDirectory(for: coreMLId)

        switch registry {
        case .huggingFace(let hubEndpoint):
            try await HuggingFaceDownloader.downloadWeights(
                modelId: coreMLId,
                to: dir,
                additionalFiles: Qwen3CoreMLDownloadArtifacts.coreMLBundleGlobs,
                hubEndpoint: hubEndpoint,
                progressHandler: { progressHandler($0 * 0.85, "CoreML") }
            )
            try await HuggingFaceDownloader.downloadWeights(
                modelId: tokenizerId,
                to: dir,
                additionalFiles: Qwen3CoreMLDownloadArtifacts.tokenizerFiles,
                hubEndpoint: hubEndpoint,
                progressHandler: { progressHandler(0.85 + $0 * 0.15, "Tokenizer") }
            )
        case .modelScope(let baseURL, let revision):
            try await downloadQwen3CoreMLViaModelScope(
                coreMLId: coreMLId,
                tokenizerId: tokenizerId,
                to: dir,
                baseURL: baseURL,
                revision: revision,
                progressHandler: progressHandler
            )
        }
        progressHandler(1.0, "Ready")
    }

    nonisolated private static func downloadQwen3CoreMLViaModelScope(
        coreMLId: String,
        tokenizerId: String,
        to directory: URL,
        baseURL: String,
        revision: String,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        let coreListed = try await ModelScopeDownloader.listAllFiles(
            modelId: coreMLId,
            baseURL: baseURL,
            revision: revision
        )
        let corePaths = coreListed.map(\.path).filter { path in
            path.contains(".mlmodelc/") || path == "config.json"
        }
        guard !corePaths.isEmpty else {
            throw DownloadError.failedToDownload("\(coreMLId): no CoreML files on ModelScope")
        }
        let coreSizes = Dictionary(uniqueKeysWithValues: coreListed.map { ($0.path, $0.size) })
        try await ModelScopeDownloader.downloadFiles(
            modelId: coreMLId,
            to: directory,
            files: corePaths,
            fileSizes: coreSizes,
            baseURL: baseURL,
            revision: revision,
            progressHandler: { progressHandler($0 * 0.85, "CoreML") }
        )

        let tokListed = try await ModelScopeDownloader.listAllFiles(
            modelId: tokenizerId,
            baseURL: baseURL,
            revision: revision
        )
        let tokPaths = Qwen3CoreMLDownloadArtifacts.tokenizerFiles.filter { name in
            tokListed.contains { $0.path == name }
        }
        let tokSizes = Dictionary(uniqueKeysWithValues: tokListed.map { ($0.path, $0.size) })
        try await ModelScopeDownloader.downloadFiles(
            modelId: tokenizerId,
            to: directory,
            files: tokPaths,
            fileSizes: tokSizes,
            baseURL: baseURL,
            revision: revision,
            progressHandler: { progressHandler(0.85 + $0 * 0.15, "Tokenizer") }
        )
    }

    /// Preferred cache directory for display / storage badges.
    nonisolated static func cacheDirectory(for model: OnDeviceModel) -> URL {
        existingCacheDirectory(for: model)
            ?? candidateCacheDirectories(for: model).first!
    }
}

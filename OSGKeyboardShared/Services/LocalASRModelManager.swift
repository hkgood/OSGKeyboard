// LocalASRModelManager.swift
// OSGKeyboard · Shared
//
// Installs local ASR model archives and Sherpa runtimes under Application Support.
// Catalog is bundled; installed state is persisted in `installed-manifest.json`.

import Foundation

public struct LocalASRInstalledManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var selectedModelId: String
    public var installedModelIDs: [String]
    public var installedRuntimeIDs: [String]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        selectedModelId: String,
        installedModelIDs: [String] = [],
        installedRuntimeIDs: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.selectedModelId = selectedModelId
        self.installedModelIDs = installedModelIDs
        self.installedRuntimeIDs = installedRuntimeIDs
        self.updatedAt = updatedAt
    }
}

public enum LocalASRModelInstallPhase: String, Sendable, Equatable {
    case idle
    case downloading
    case paused
    case extracting
    case validating
    case finalizing
    case failed
    case completed
}

public struct LocalASRModelInstallProgress: Sendable, Equatable {
    public var phase: LocalASRModelInstallPhase
    public var fraction: Double
    public var message: String
    public var bytesReceived: Int64?
    public var bytesTotal: Int64?
    public var activeItemId: String?

    public init(
        phase: LocalASRModelInstallPhase,
        fraction: Double,
        message: String,
        bytesReceived: Int64? = nil,
        bytesTotal: Int64? = nil,
        activeItemId: String? = nil
    ) {
        self.phase = phase
        self.fraction = fraction
        self.message = message
        self.bytesReceived = bytesReceived
        self.bytesTotal = bytesTotal
        self.activeItemId = activeItemId
    }

    public static let idle = LocalASRModelInstallProgress(phase: .idle, fraction: 0, message: "")
}

public enum LocalASRModelManagerError: Error, LocalizedError {
    case downloadFailed(String)
    case extractFailed(String)
    case validationFailed(String)
    case runtimeMissing
    case binaryMissing

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail): return "Download failed: \(detail)"
        case .extractFailed(let detail): return "Extract failed: \(detail)"
        case .validationFailed(let detail): return "Validation failed: \(detail)"
        case .runtimeMissing: return "Sherpa runtime is not installed."
        case .binaryMissing: return "Sherpa binary not found in runtime bundle."
        }
    }
}

public actor LocalASRModelManager {

    public static let shared = LocalASRModelManager()

    private let fileManager = FileManager.default
    private var progress = LocalASRModelInstallProgress.idle
    #if os(macOS)
    private var activeDownloadController: LocalASRModelDownloadController?
    private var pausedResumeData: Data?
    #endif

    private init() {}

    public func currentProgress() -> LocalASRModelInstallProgress {
        progress
    }

    #if os(macOS)
    public func pauseDownload() async throws {
        guard progress.phase == .downloading, let controller = activeDownloadController else { return }
        let resumeData = try await controller.pause()
        pausedResumeData = resumeData
        progress = LocalASRModelInstallProgress(
            phase: .paused,
            fraction: progress.fraction,
            message: progress.message,
            bytesReceived: progress.bytesReceived,
            bytesTotal: progress.bytesTotal,
            activeItemId: progress.activeItemId
        )
    }

    public func resumeDownload() async throws {
        guard progress.phase == .paused,
              let resumeData = pausedResumeData,
              let controller = activeDownloadController else {
            throw LocalASRModelManagerError.downloadFailed("No paused download to resume.")
        }
        pausedResumeData = nil
        progress = LocalASRModelInstallProgress(
            phase: .downloading,
            fraction: progress.fraction,
            message: progress.message,
            bytesReceived: progress.bytesReceived,
            bytesTotal: progress.bytesTotal,
            activeItemId: progress.activeItemId
        )
        controller.resumeFromPause(resumeData)
    }

    public func isDownloadPaused() -> Bool {
        progress.phase == .paused
    }
    #endif

    public func rootDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OSGKeyboard/LocalASRModels", isDirectory: true)
    }

    public func manifestURL() -> URL {
        LocalASRInstalledManifestIO.manifestURL(fileManager: fileManager)
    }

    public func loadManifest(defaultModelId: String) -> LocalASRInstalledManifest {
        LocalASRInstalledManifestIO.load(defaultModelId: defaultModelId, fileManager: fileManager)
    }

    public func saveManifest(_ manifest: LocalASRInstalledManifest) throws {
        try LocalASRInstalledManifestIO.save(manifest, fileManager: fileManager)
    }

    public func setSelectedModelId(_ modelId: String, catalog: LocalASRCatalogDocument) throws {
        var manifest = loadManifest(defaultModelId: catalog.defaultModelId)
        manifest.selectedModelId = modelId
        manifest.updatedAt = Date()
        try saveManifest(manifest)
    }

    public func installDirectory(for relativePath: String) -> URL {
        rootDirectory().appendingPathComponent(relativePath, isDirectory: true)
    }

    public func isModelInstalled(_ model: LocalASRModelDefinition, manualMLXPath: String?) -> Bool {
        LocalASRModelInstallState.isInstalled(model, manualMLXPath: manualMLXPath, fileManager: fileManager)
    }

    public func isRuntimeInstalled(_ runtime: LocalASRRuntimeDefinition) -> Bool {
        LocalASRModelInstallState.isRuntimeInstalled(runtime, fileManager: fileManager)
    }

    #if os(macOS)
    public func resolveRuntimeBinary(runtime: LocalASRRuntimeDefinition) -> URL? {
        LocalASRModelInstallState.resolveRuntimeBinary(runtime: runtime, fileManager: fileManager)
    }

    public func installModel(
        _ model: LocalASRModelDefinition,
        catalog: LocalASRCatalogDocument,
        preferredSource: LocalASRDownloadSourcePreference = .auto
    ) async throws {
        guard let relative = model.installRelativePath,
              let sources = model.sources,
              !sources.isEmpty else {
            throw LocalASRModelManagerError.validationFailed("Model is not downloadable.")
        }

        progress = LocalASRModelInstallProgress(
            phase: .downloading,
            fraction: 0.05,
            message: model.displayName,
            activeItemId: model.id
        )
        let sortedSources = LocalASRDownloadSourceSorter.sorted(sources, preferred: preferredSource)
        var lastError: Error?

        switch model.installKind {
        case .archive:
            guard let baseName = model.archiveBaseName else {
                throw LocalASRModelManagerError.validationFailed("Model is not downloadable.")
            }
            for source in sortedSources where source.isArchive {
                do {
                    try await installArchive(
                        from: source.url,
                        installRelativePath: relative,
                        archiveBaseName: baseName,
                        layoutModel: model,
                        itemId: model.id,
                        displayName: model.displayName
                    )
                    try markModelInstalled(model, catalog: catalog)
                    progress = LocalASRModelInstallProgress(
                        phase: .completed,
                        fraction: 1,
                        message: model.displayName,
                        activeItemId: model.id
                    )
                    return
                } catch {
                    lastError = error
                }
            }
        case .repository:
            guard let baseName = model.archiveBaseName else {
                throw LocalASRModelManagerError.validationFailed("Model is not downloadable.")
            }
            for source in sortedSources where source.isRepository {
                do {
                    try await installRepository(
                        source: source,
                        installRelativePath: relative,
                        archiveBaseName: baseName,
                        layoutModel: model,
                        itemId: model.id,
                        displayName: model.displayName
                    )
                    try markModelInstalled(model, catalog: catalog)
                    progress = LocalASRModelInstallProgress(
                        phase: .completed,
                        fraction: 1,
                        message: model.displayName,
                        activeItemId: model.id
                    )
                    return
                } catch {
                    lastError = error
                }
            }
        default:
            throw LocalASRModelManagerError.validationFailed("Model is not downloadable.")
        }

        progress = LocalASRModelInstallProgress(
            phase: .failed,
            fraction: 0,
            message: lastError?.localizedDescription ?? "Download failed"
        )
        throw lastError ?? LocalASRModelManagerError.downloadFailed("All mirrors failed")
    }

    private func markModelInstalled(
        _ model: LocalASRModelDefinition,
        catalog: LocalASRCatalogDocument
    ) throws {
        var manifest = loadManifest(defaultModelId: catalog.defaultModelId)
        if !manifest.installedModelIDs.contains(model.id) {
            manifest.installedModelIDs.append(model.id)
        }
        manifest.updatedAt = Date()
        try saveManifest(manifest)
    }

    public func installRuntime(
        _ runtime: LocalASRRuntimeDefinition,
        catalog: LocalASRCatalogDocument
    ) async throws {
        let sortedSources = LocalASRDownloadSourceSorter.sorted(runtime.sources)
        guard !sortedSources.isEmpty else {
            throw LocalASRModelManagerError.downloadFailed("No runtime source configured.")
        }
        progress = LocalASRModelInstallProgress(
            phase: .downloading,
            fraction: 0.05,
            message: runtime.displayName,
            activeItemId: runtime.id
        )
        var lastError: Error?
        for source in sortedSources where source.isArchive {
            do {
                try await installArchive(
                    from: source.url,
                    installRelativePath: runtime.installRelativePath,
                    archiveBaseName: runtime.installRelativePath.split(separator: "/").last.map(String.init) ?? runtime.id,
                    layoutModel: nil,
                    expectedBinaryCandidates: runtime.binaryCandidates,
                    itemId: runtime.id,
                    displayName: runtime.displayName
                )
                guard isRuntimeInstalled(runtime) else {
                    throw LocalASRModelManagerError.binaryMissing
                }
                var manifest = loadManifest(defaultModelId: catalog.defaultModelId)
                if !manifest.installedRuntimeIDs.contains(runtime.id) {
                    manifest.installedRuntimeIDs.append(runtime.id)
                }
                manifest.updatedAt = Date()
                try saveManifest(manifest)
                progress = LocalASRModelInstallProgress(phase: .completed, fraction: 1, message: runtime.displayName)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LocalASRModelManagerError.downloadFailed("All runtime mirrors failed")
    }

    public func modelRootURL(_ model: LocalASRModelDefinition) -> URL? {
        LocalASRModelInstallState.modelRootURL(model, fileManager: fileManager)
    }

    public func installDirectoryURL(for model: LocalASRModelDefinition) -> URL? {
        guard let relative = model.installRelativePath else { return nil }
        return installDirectory(for: relative)
    }

    public func deleteModel(
        _ model: LocalASRModelDefinition,
        catalog: LocalASRCatalogDocument
    ) throws {
        guard model.installKind == .archive || model.installKind == .repository,
              let relative = model.installRelativePath else { return }
        let dir = installDirectory(for: relative)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        var manifest = loadManifest(defaultModelId: catalog.defaultModelId)
        manifest.installedModelIDs.removeAll { $0 == model.id }
        if manifest.selectedModelId == model.id {
            manifest.selectedModelId = catalog.defaultModelId
            UserDefaults.standard.set(catalog.defaultModelId, forKey: LocalASRPreferenceKeys.selectedModelId)
        }
        manifest.updatedAt = Date()
        try saveManifest(manifest)
        if progress.activeItemId == model.id {
            progress = .idle
        }
    }

    public func deleteRuntime(
        _ runtime: LocalASRRuntimeDefinition,
        catalog: LocalASRCatalogDocument
    ) throws {
        let dir = installDirectory(for: runtime.installRelativePath)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        var manifest = loadManifest(defaultModelId: catalog.defaultModelId)
        manifest.installedRuntimeIDs.removeAll { $0 == runtime.id }
        manifest.updatedAt = Date()
        try saveManifest(manifest)
    }

    private func setProgress(_ update: LocalASRModelInstallProgress) {
        progress = update
    }

    func updateDownloadProgress(
        itemId: String,
        displayName: String,
        update: LocalASRDownloadProgressUpdate
    ) {
        reportDownloadProgress(itemId: itemId, displayName: displayName, update: update)
    }

    private func reportDownloadProgress(
        itemId: String,
        displayName: String,
        update: LocalASRDownloadProgressUpdate
    ) {
        // Download phase occupies 10%–55% of the overall install bar.
        let mapped = 0.10 + update.fraction * 0.45
        progress = LocalASRModelInstallProgress(
            phase: .downloading,
            fraction: mapped,
            message: displayName,
            bytesReceived: update.bytesReceived,
            bytesTotal: update.bytesTotal,
            activeItemId: itemId
        )
    }
    #endif

    // MARK: - Private

    #if os(macOS)
    private func installArchive(
        from urlString: String,
        installRelativePath: String,
        archiveBaseName: String,
        layoutModel: LocalASRModelDefinition?,
        expectedBinaryCandidates: [String]? = nil,
        itemId: String,
        displayName: String
    ) async throws {
        guard let remoteURL = URL(string: urlString) else {
            throw LocalASRModelManagerError.downloadFailed("Invalid URL")
        }

        let stagingRoot = rootDirectory().appendingPathComponent("staging/\(UUID().uuidString)", isDirectory: true)
        let destinationParent = installDirectory(for: installRelativePath)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        let archiveURL = stagingRoot.appendingPathComponent(remoteURL.lastPathComponent)
        progress = LocalASRModelInstallProgress(
            phase: .downloading,
            fraction: 0.10,
            message: displayName,
            activeItemId: itemId
        )

        do {
            let controller = LocalASRModelDownloadClient.makeController(destinationURL: archiveURL) { update in
                Task {
                    await LocalASRModelManager.shared.updateDownloadProgress(
                        itemId: itemId,
                        displayName: displayName,
                        update: update
                    )
                }
            }
            activeDownloadController = controller
            try await controller.download(from: remoteURL)
            activeDownloadController = nil
            pausedResumeData = nil
        } catch {
            activeDownloadController = nil
            pausedResumeData = nil
            throw LocalASRModelManagerError.downloadFailed(error.localizedDescription)
        }

        progress = LocalASRModelInstallProgress(
            phase: .extracting,
            fraction: 0.58,
            message: displayName,
            activeItemId: itemId
        )
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        let extractOK = try await extractTarBz2(archiveURL: archiveURL, destination: destinationParent)
        guard extractOK else {
            throw LocalASRModelManagerError.extractFailed("tar extraction failed")
        }

        progress = LocalASRModelInstallProgress(
            phase: .validating,
            fraction: 0.82,
            message: displayName,
            activeItemId: itemId
        )
        if let layoutModel {
            guard LocalASRModelInstallState.isInstalled(
                layoutModel,
                manualMLXPath: nil,
                fileManager: fileManager
            ) else {
                throw LocalASRModelManagerError.validationFailed("Required model files missing after extract.")
            }
        }
        if let expectedBinaryCandidates {
            let runtimeRoot = destinationParent
            let found = expectedBinaryCandidates.contains { candidate in
                let direct = runtimeRoot.appendingPathComponent(candidate)
                if fileManager.isExecutableFile(atPath: direct.path) { return true }
                let name = (candidate as NSString).lastPathComponent
                return findExecutable(named: name, under: runtimeRoot) != nil
            }
            guard found else {
                throw LocalASRModelManagerError.binaryMissing
            }
        }

        progress = LocalASRModelInstallProgress(
            phase: .finalizing,
            fraction: 0.95,
            message: displayName,
            activeItemId: itemId
        )
        try? fileManager.removeItem(at: archiveURL)
    }

    private func installRepository(
        source: LocalASRDownloadSource,
        installRelativePath: String,
        archiveBaseName: String,
        layoutModel: LocalASRModelDefinition,
        itemId: String,
        displayName: String
    ) async throws {
        guard let baseURL = source.baseURL,
              let files = source.files,
              !files.isEmpty else {
            throw LocalASRModelManagerError.downloadFailed("Invalid repository source.")
        }

        let destinationRoot = installDirectory(for: installRelativePath)
            .appendingPathComponent(archiveBaseName, isDirectory: true)
        let stagingRoot = rootDirectory().appendingPathComponent("staging/\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        // Do NOT wipe an existing destination: files land here only after a full
        // download completes (partials stay in URLSession's temp dir), so already
        // present files are complete and can be reused when a prior attempt failed
        // partway or we fall back to another mirror.
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let totalBytes = files.reduce(Int64(0)) { partial, file in
            partial + Int64(file.sizeBytes ?? 0)
        }
        var completedBytes: Int64 = 0

        for (index, file) in files.enumerated() {
            let localURL = destinationRoot.appendingPathComponent(file.localPath)

            // Skip files a previous attempt already finished (non-empty on disk).
            if fileManager.fileExists(atPath: localURL.path),
               let attrs = try? fileManager.attributesOfItem(atPath: localURL.path),
               let size = attrs[.size] as? Int64, size > 0 {
                completedBytes += Int64(file.sizeBytes ?? Int(size))
                continue
            }

            let remoteURLString = baseURL.replacingOccurrences(of: "{path}", with: file.remotePath)
            guard let remoteURL = URL(string: remoteURLString) else {
                throw LocalASRModelManagerError.downloadFailed("Invalid URL for \(file.remotePath)")
            }

            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Snapshot the running total so the progress closure captures an
            // immutable value (avoids concurrent access to `completedBytes`).
            let priorBytes = completedBytes
            progress = LocalASRModelInstallProgress(
                phase: .downloading,
                fraction: 0.10 + (Double(index) / Double(files.count)) * 0.45,
                message: displayName,
                bytesReceived: priorBytes,
                bytesTotal: totalBytes > 0 ? totalBytes : nil,
                activeItemId: itemId
            )

            do {
                let controller = LocalASRModelDownloadClient.makeController(destinationURL: localURL) { update in
                    Task {
                        let aggregateReceived = priorBytes + update.bytesReceived
                        let aggregateTotal = totalBytes > 0 ? totalBytes : update.bytesTotal
                        await LocalASRModelManager.shared.updateDownloadProgress(
                            itemId: itemId,
                            displayName: displayName,
                            update: LocalASRDownloadProgressUpdate(
                                bytesReceived: aggregateReceived,
                                bytesTotal: max(aggregateTotal, 1)
                            )
                        )
                    }
                }
                activeDownloadController = controller
                try await controller.download(from: remoteURL)
                activeDownloadController = nil
                pausedResumeData = nil
            } catch {
                activeDownloadController = nil
                pausedResumeData = nil
                throw LocalASRModelManagerError.downloadFailed(error.localizedDescription)
            }

            if let size = file.sizeBytes {
                completedBytes += Int64(size)
            } else if let attrs = try? fileManager.attributesOfItem(atPath: localURL.path),
                      let size = attrs[.size] as? Int64 {
                completedBytes += size
            }
        }

        progress = LocalASRModelInstallProgress(
            phase: .validating,
            fraction: 0.82,
            message: displayName,
            activeItemId: itemId
        )
        guard LocalASRModelInstallState.isInstalled(
            layoutModel,
            manualMLXPath: nil,
            fileManager: fileManager
        ) else {
            throw LocalASRModelManagerError.validationFailed("Required model files missing after download.")
        }

        progress = LocalASRModelInstallProgress(
            phase: .finalizing,
            fraction: 0.95,
            message: displayName,
            activeItemId: itemId
        )
    }

    public func ensureRuntimeInstalled(catalog: LocalASRCatalogDocument) async throws {
        guard let runtime = LocalASRModelCatalog.runtime(
            for: LocalASRModelCatalog.currentRuntimePlatform(),
            in: catalog
        ) else {
            throw LocalASRModelManagerError.runtimeMissing
        }
        if isRuntimeInstalled(runtime) { return }
        try await installRuntime(runtime, catalog: catalog)
    }

    private func findExecutable(named name: String, under root: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            guard url.lastPathComponent == name else { continue }
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func extractTarBz2(archiveURL: URL, destination: URL) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xjf", archiveURL.path, "-C", destination.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: LocalASRModelManagerError.extractFailed(error.localizedDescription))
            }
        }
    }
    #endif
}

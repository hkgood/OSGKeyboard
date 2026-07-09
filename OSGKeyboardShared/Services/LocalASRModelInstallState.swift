// LocalASRModelInstallState.swift
// OSGKeyboard · Shared

import Foundation

public enum LocalASRModelInstallState {

    public static func rootDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("OSGKeyboard/LocalASRModels", isDirectory: true)
    }

    public static func installDirectory(for relativePath: String, fileManager: FileManager = .default) -> URL {
        rootDirectory(fileManager: fileManager).appendingPathComponent(relativePath, isDirectory: true)
    }

    public static func isInstalled(
        _ model: LocalASRModelDefinition,
        manualMLXPath: String?,
        fileManager: FileManager = .default
    ) -> Bool {
        switch model.installKind {
        case .manual:
            guard let required = model.requiredRelativeFiles, !required.isEmpty else { return false }
            let base = URL(fileURLWithPath: manualMLXPath ?? "", isDirectory: true)
            guard fileManager.fileExists(atPath: base.path) else { return false }
            return required.allSatisfy { fileManager.fileExists(atPath: base.appendingPathComponent($0).path) }
        case .archive, .repository:
            guard let relative = model.installRelativePath,
                  let layout = model.layout,
                  let baseName = model.archiveBaseName else { return false }
            let root = installDirectory(for: relative, fileManager: fileManager)
                .appendingPathComponent(baseName, isDirectory: true)
            return validateArchiveModel(at: root, model: model, layout: layout, fileManager: fileManager)
        case .runtime:
            return false
        }
    }

    public static func modelRootURL(
        _ model: LocalASRModelDefinition,
        fileManager: FileManager = .default
    ) -> URL? {
        guard model.installKind == .archive || model.installKind == .repository,
              let relative = model.installRelativePath,
              let baseName = model.archiveBaseName else { return nil }
        return installDirectory(for: relative, fileManager: fileManager)
            .appendingPathComponent(baseName, isDirectory: true)
    }

    public static func resolveRuntimeBinary(
        runtime: LocalASRRuntimeDefinition,
        fileManager: FileManager = .default
    ) -> URL? {
        let root = installDirectory(for: runtime.installRelativePath, fileManager: fileManager)
        for candidate in runtime.binaryCandidates {
            let direct = root.appendingPathComponent(candidate)
            if fileManager.isExecutableFile(atPath: direct.path) {
                return direct
            }
        }
        for candidate in runtime.binaryCandidates {
            let name = (candidate as NSString).lastPathComponent
            if let found = findExecutable(named: name, under: root, fileManager: fileManager) {
                return found
            }
        }
        return nil
    }

    public static func isRuntimeInstalled(
        _ runtime: LocalASRRuntimeDefinition,
        fileManager: FileManager = .default
    ) -> Bool {
        resolveRuntimeBinary(runtime: runtime, fileManager: fileManager) != nil
    }

    // MARK: - Private

    private static func validateArchiveModel(
        at root: URL,
        model: LocalASRModelDefinition,
        layout: LocalASRModelLayout,
        fileManager: FileManager
    ) -> Bool {
        switch model.backend {
        case .sherpaQwen3:
            guard let conv = layout.convFrontend,
                  let encoder = layout.encoder,
                  let decoder = layout.decoder,
                  let tokenizer = layout.tokenizer else { return false }
            return fileManager.fileExists(atPath: root.appendingPathComponent(conv).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent(encoder).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent(decoder).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent(tokenizer, isDirectory: true).path)
        case .sherpaSenseVoice:
            guard let onnx = layout.senseVoiceModel,
                  let tokens = layout.tokens else { return false }
            return fileManager.fileExists(atPath: root.appendingPathComponent(onnx).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent(tokens).path)
        case .sherpaParaformer:
            guard let paraformer = layout.paraformerModel,
                  let tokens = layout.tokens else { return false }
            return fileManager.fileExists(atPath: root.appendingPathComponent(paraformer).path)
                && fileManager.fileExists(atPath: root.appendingPathComponent(tokens).path)
        default:
            return false
        }
    }

    private static func findExecutable(
        named name: String,
        under root: URL,
        fileManager: FileManager
    ) -> URL? {
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

    public static func directoryByteCount(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}

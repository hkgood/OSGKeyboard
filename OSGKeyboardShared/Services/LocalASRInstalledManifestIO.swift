// LocalASRInstalledManifestIO.swift
// OSGKeyboard · Shared

import Foundation

public enum LocalASRInstalledManifestIO {

    public static func manifestURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("OSGKeyboard/LocalASRModels/installed-manifest.json")
    }

    public static func load(defaultModelId: String, fileManager: FileManager = .default) -> LocalASRInstalledManifest {
        let url = manifestURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LocalASRInstalledManifest.self, from: data) else {
            return LocalASRInstalledManifest(selectedModelId: defaultModelId)
        }
        return manifest
    }

    public static func save(_ manifest: LocalASRInstalledManifest, fileManager: FileManager = .default) throws {
        let url = manifestURL(fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}

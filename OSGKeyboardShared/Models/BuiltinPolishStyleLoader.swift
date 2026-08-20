// BuiltinPolishStyleLoader.swift
// OSGKeyboard · Shared
//
// Loads built-in polish style packs from bundled JSON
// (`Resources/PolishStyles/manifest.json` + one file per style).
// Older fun-style JSON files may still contain the retired shared-foundation
// placeholder. It is stripped while loading because the composer now owns the
// single minimal formatting layer.

import Foundation

enum BuiltinPolishStyleLoader {
    static let foundationPlaceholder = "{{FUN_SINGLE_PASS_FOUNDATION}}"
    private static let catalogDirectory = "PolishStyles"
    private static let manifestName = "manifest"

    private struct Manifest: Decodable {
        let version: Int
        let styles: [String]
    }

    private struct FilePayload: Decodable {
        let id: String
        let name: String
        let prompt: String
    }

    /// Ordered built-in packs. Empty only if the bundle is misconfigured.
    static func load(
        bundles: [Bundle] = candidateBundles()
    ) -> [PolishStylePack] {
        guard let manifestURL = locate(resource: manifestName, extension: "json", in: bundles) else {
            OSGLog.config.error("builtin polish styles: manifest.json missing from bundle")
            return []
        }
        return load(manifestURL: manifestURL, styleURL: { id in
            locate(resource: id, extension: "json", in: bundles)
        })
    }

    /// Loads from an on-disk catalog directory (manifest + `{id}.json`). Used by tests.
    static func load(fromDirectory directory: URL) -> [PolishStylePack] {
        let manifestURL = directory.appendingPathComponent("\(manifestName).json")
        return load(manifestURL: manifestURL, styleURL: { id in
            let url = directory.appendingPathComponent("\(id).json")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        })
    }

    private static func load(
        manifestURL: URL,
        styleURL: (String) -> URL?
    ) -> [PolishStylePack] {
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            var packs: [PolishStylePack] = []
            packs.reserveCapacity(manifest.styles.count)
            for id in manifest.styles {
                guard let url = styleURL(id) else {
                    OSGLog.config.error("builtin polish styles: missing \(id, privacy: .public).json")
                    continue
                }
                let payload = try JSONDecoder().decode(FilePayload.self, from: Data(contentsOf: url))
                guard payload.id == id else {
                    OSGLog.config.error(
                        "builtin polish styles: id mismatch file=\(id, privacy: .public) payload=\(payload.id, privacy: .public)"
                    )
                    continue
                }
                let prompt = payload.prompt
                    .replacingOccurrences(of: foundationPlaceholder, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !payload.name.isEmpty, !prompt.isEmpty else { continue }
                packs.append(
                    PolishStylePack(
                        id: payload.id,
                        name: payload.name,
                        prompt: prompt,
                        kind: .builtin,
                        createdAt: .distantPast,
                        updatedAt: .distantPast
                    )
                )
            }
            return packs
        } catch {
            OSGLog.config.error(
                "builtin polish styles: load failed \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    static func candidateBundles() -> [Bundle] {
        // Shared framework bundle first; Mac embeds Shared sources into the app, so
        // fall back to main / class bundle the same way other Shared resources do.
        var bundles: [Bundle] = [
            Bundle(for: BundleToken.self),
            Bundle.main
        ]
        #if !os(macOS)
        if let shared = Bundle(identifier: "com.osgkeyboard.ios.shared") {
            bundles.insert(shared, at: 0)
        }
        #endif
        var seen = Set<ObjectIdentifier>()
        return bundles.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private static func locate(resource: String, extension ext: String, in bundles: [Bundle]) -> URL? {
        for bundle in bundles {
            if let url = bundle.url(
                forResource: resource,
                withExtension: ext,
                subdirectory: catalogDirectory
            ) {
                return url
            }
            if let url = bundle.url(forResource: resource, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

/// Anchor type so `Bundle(for:)` resolves to the Shared (or host) binary that
/// owns the compiled-in PolishStyles resources.
private final class BundleToken {}

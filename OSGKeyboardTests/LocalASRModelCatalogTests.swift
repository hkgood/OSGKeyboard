// LocalASRModelCatalogTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class LocalASRModelCatalogTests: XCTestCase {

    func testBundledCatalogLoads() throws {
        let catalog = try LocalASRModelCatalog.loadBundled()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.defaultModelId, "qwen3-mlx-0.6b-4bit")
        XCTAssertTrue(catalog.models.contains { $0.id == "qwen3-mlx-0.6b-4bit" })
        XCTAssertTrue(catalog.models.contains { $0.id == "qwen3-mlx-1.7b-4bit" })
        XCTAssertFalse(catalog.models.contains { $0.id == "sherpa-qwen3-0.6b-int8" })
        XCTAssertTrue(catalog.runtimes.isEmpty)
        XCTAssertEqual(
            LocalASRModelCatalog.model("qwen3-mlx-0.6b-4bit", in: catalog)?.badgeKey,
            "mac.localASR.badge.balanced"
        )
        XCTAssertEqual(
            LocalASRModelCatalog.model("qwen3-mlx-1.7b-4bit", in: catalog)?.badgeKey,
            "mac.localASR.badge.quality"
        )
    }

    func testMLX06BUsesRepositoryInstall() throws {
        let catalog = try LocalASRModelCatalog.loadBundled()
        let model = try XCTUnwrap(LocalASRModelCatalog.model("qwen3-mlx-0.6b-4bit", in: catalog))
        XCTAssertEqual(model.installKind, .repository)
        XCTAssertEqual(model.backend, .mlx)
        XCTAssertTrue(model.sources?.contains(where: { $0.type == "huggingface" && $0.isRepository }) == true)
    }

    func testMLXSourcesIncludeHFMirrorAndOfficial() throws {
        let catalog = try LocalASRModelCatalog.loadBundled()
        for id in ["qwen3-mlx-0.6b-4bit", "qwen3-mlx-1.7b-4bit"] {
            let model = try XCTUnwrap(LocalASRModelCatalog.model(id, in: catalog))
            let types = Set(model.sources?.map(\.type) ?? [])
            XCTAssertTrue(types.contains("hfmirror"), "\(id) should offer the hf-mirror source")
            XCTAssertTrue(types.contains("huggingface"), "\(id) should offer the official HF source")
            XCTAssertFalse(types.contains("modelscope"), "\(id) should drop the dead ModelScope link")

            let mirror = try XCTUnwrap(model.sources?.first { $0.type == "hfmirror" })
            XCTAssertTrue(mirror.baseURL?.hasPrefix("https://hf-mirror.com/") == true)
            let remoteFiles = Set(mirror.files?.map(\.remotePath) ?? [])
            XCTAssertTrue(remoteFiles.contains("model.safetensors"))
            XCTAssertTrue(remoteFiles.contains("preprocessor_config.json"))
            // Files that don't exist in the real repo must not be listed.
            XCTAssertFalse(remoteFiles.contains("tokenizer.json"))
            XCTAssertFalse(remoteFiles.contains("special_tokens_map.json"))
        }
    }

    func testCapabilitiesForMLXQwen3() throws {
        let catalog = try LocalASRModelCatalog.loadBundled()
        let model = try XCTUnwrap(LocalASRModelCatalog.model("qwen3-mlx-0.6b-4bit", in: catalog))
        let caps = LocalASRModelCatalog.capabilities(for: model)
        XCTAssertEqual(caps.hotwordMode, .promptOnly)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(model.supportsHotwords)
    }

    func testManifestRoundTrip() throws {
        let manifest = LocalASRInstalledManifest(
            selectedModelId: "qwen3-mlx-0.6b-4bit",
            installedModelIDs: ["qwen3-mlx-0.6b-4bit"]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(LocalASRInstalledManifest.self, from: Data(contentsOf: url))
        XCTAssertEqual(loaded.selectedModelId, manifest.selectedModelId)
        XCTAssertEqual(loaded.installedModelIDs, manifest.installedModelIDs)
    }

    func testBiasDiagnosticsStoreRoundTrip() {
        LocalASRBiasDiagnosticsStore.clear()
        let payload = LocalASRBiasPayload(
            hardHotwords: [],
            promptBias: "test",
            corpusContext: nil,
            polishFragment: "fragment",
            correctionPairs: [],
            diagnostics: LocalASRBiasDiagnostics(userTermCount: 2, builtinTermCount: 3)
        )
        LocalASRBiasDiagnosticsStore.save(
            payload: payload,
            modelId: "qwen3-mlx-0.6b-4bit",
            backendLabel: "Qwen3-ASR 0.6B"
        )
        let snapshot = LocalASRBiasDiagnosticsStore.load()
        XCTAssertEqual(snapshot?.modelId, "qwen3-mlx-0.6b-4bit")
        XCTAssertEqual(snapshot?.diagnostics.userTermCount, 2)
        XCTAssertEqual(snapshot?.hotwordCount, 0)
        LocalASRBiasDiagnosticsStore.clear()
    }

    func testMLXAdapterProducesPromptBiasNotHardHotwords() throws {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phrases-\(UUID().uuidString).tsv")
        try "word\tpinyin\tsource\tweight\nSwiftUI\tswift ui\tcomputer_terms\t5\n"
            .write(to: fixtureURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        var dict = PersonalDictionary.empty
        _ = dict.upsertManual(term: "Kubernetes")

        let payload = LocalASRBiasAdapter.adapt(
            LocalASRBiasRequest(
                dictionary: dict,
                locale: Locale(identifier: "zh-CN"),
                capabilities: .qwen3MLX
            ),
            lexicon: BuiltinLexiconIndex(fixtureURL: fixtureURL)
        )
        XCTAssertTrue(payload.hardHotwords.isEmpty)
        XCTAssertNotNil(payload.promptBias)
        XCTAssertTrue(payload.promptBias?.contains("Kubernetes") == true)
    }

    func testLegacySherpaModelIdMapsToMLXDefault() {
        let legacyIds = [
            "sherpa-qwen3-0.6b-int8",
            "sherpa-qwen3-1.7b-int8",
            "sherpa-sensevoice-small-int8",
        ]
        for id in legacyIds {
            XCTAssertEqual(migrateLegacyModelId(id), "qwen3-mlx-0.6b-4bit")
        }
        XCTAssertEqual(migrateLegacyModelId("qwen3-mlx-1.7b-4bit"), "qwen3-mlx-1.7b-4bit")
    }

    private func migrateLegacyModelId(_ id: String) -> String {
        switch id {
        case "sherpa-qwen3-0.6b-int8",
             "sherpa-qwen3-1.7b-int8",
             "sherpa-sensevoice-small-int8",
             "sherpa-paraformer-zh-int8",
             "qwen3-mlx-1.7b":
            return "qwen3-mlx-0.6b-4bit"
        default:
            return id
        }
    }
}

// LocalASRModelCatalogTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class LocalASRModelCatalogTests: XCTestCase {

    func testBundledCatalogLoads() throws {
        let catalog = try LocalASRModelCatalog.loadBundled()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertFalse(catalog.models.isEmpty)
        XCTAssertTrue(catalog.models.contains { $0.id == "qwen3-mlx-1.7b" })
        XCTAssertTrue(catalog.models.contains { $0.id == "sherpa-qwen3-0.6b-int8" })
    }

    func testCapabilitiesForSherpaQwen3() throws {
        let catalog = try LocalASRModelCatalog.loadBundled()
        let model = try XCTUnwrap(LocalASRModelCatalog.model("sherpa-qwen3-0.6b-int8", in: catalog))
        let caps = LocalASRModelCatalog.capabilities(for: model)
        XCTAssertEqual(caps.hotwordMode, .recognizerScoped)
        XCTAssertTrue(model.supportsHotwords)
    }

    func testManifestRoundTrip() throws {
        let manifest = LocalASRInstalledManifest(
            selectedModelId: "sherpa-qwen3-0.6b-int8",
            installedModelIDs: ["sherpa-qwen3-0.6b-int8"]
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
            hardHotwords: ["Cursor"],
            promptBias: "test",
            corpusContext: nil,
            polishFragment: "fragment",
            correctionPairs: [],
            diagnostics: LocalASRBiasDiagnostics(userTermCount: 2, builtinTermCount: 3)
        )
        LocalASRBiasDiagnosticsStore.save(
            payload: payload,
            modelId: "qwen3-mlx-1.7b",
            backendLabel: "MLX"
        )
        let snapshot = LocalASRBiasDiagnosticsStore.load()
        XCTAssertEqual(snapshot?.modelId, "qwen3-mlx-1.7b")
        XCTAssertEqual(snapshot?.diagnostics.userTermCount, 2)
        XCTAssertEqual(snapshot?.hotwordCount, 1)
        LocalASRBiasDiagnosticsStore.clear()
    }

    func testSherpaAdapterProducesHardHotwords() throws {
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
                capabilities: .sherpaQwen3
            ),
            lexicon: BuiltinLexiconIndex(fixtureURL: fixtureURL)
        )
        XCTAssertFalse(payload.hardHotwords.isEmpty)
        XCTAssertTrue(payload.hardHotwords.contains("Kubernetes"))
    }
}

// LocalASRBiasAdapterTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class LocalASRBiasAdapterTests: XCTestCase {

    private func makeFixtureLexicon() throws -> BuiltinLexiconIndex {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("osg-phrases-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("phrases.tsv")
        let tsv = """
        word\tpinyin\tsource\tweight
        SwiftUI\tswift ui\tcomputer_terms\t5
        Kubernetes\tku bo ne si\tcomputer_terms\t5
        一致性\tyi zhi xing\tcomputer_terms\t5
        """
        try tsv.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return BuiltinLexiconIndex(fixtureURL: url)
    }

    func testAdaptBuildsPromptBiasForQwen3MLX() throws {
        let lexicon = try makeFixtureLexicon()
        var dict = PersonalDictionary.empty
        _ = dict.upsertManual(term: "Cursor")
        dict.updateAliases(for: dict.entries[0].id, aliases: ["cursor"])

        let payload = LocalASRBiasAdapter.adapt(
            LocalASRBiasRequest(
                dictionary: dict,
                locale: Locale(identifier: "zh-CN"),
                capabilities: .qwen3MLX
            ),
            lexicon: lexicon
        )

        XCTAssertNotNil(payload.promptBias)
        XCTAssertTrue(payload.promptBias?.contains("Cursor") == true)
        XCTAssertTrue(payload.promptBias?.contains("SwiftUI") == true)
        XCTAssertEqual(payload.diagnostics.userTermCount, 2) // OSGKeyboard system + Cursor
        XCTAssertGreaterThan(payload.diagnostics.builtinTermCount, 0)
    }

    func testAdaptProducesPolishFragmentWithoutUserDuplicates() throws {
        let lexicon = try makeFixtureLexicon()
        var dict = PersonalDictionary.empty
        _ = dict.upsertManual(term: "SwiftUI")

        let payload = LocalASRBiasAdapter.adapt(
            LocalASRBiasRequest(
                dictionary: dict,
                locale: Locale(identifier: "zh-CN"),
                capabilities: .qwen3MLX
            ),
            lexicon: lexicon
        )

        XCTAssertFalse(payload.polishFragment.contains("SwiftUI"))
        XCTAssertTrue(payload.polishFragment.contains("Kubernetes"))
    }

    func testCorrectionPairsFromAliases() {
        var dict = PersonalDictionary.empty
        _ = dict.upsertManual(term: "Kubernetes")
        dict.updateAliases(for: dict.entries[0].id, aliases: ["k8s"])

        let payload = LocalASRBiasAdapter.adapt(
            LocalASRBiasRequest(
                dictionary: dict,
                locale: Locale(identifier: "zh-CN"),
                capabilities: .qwen3MLX
            ),
            lexicon: BuiltinLexiconIndex.shared
        )

        XCTAssertEqual(payload.correctionPairs.count, 1)
        XCTAssertEqual(payload.correctionPairs[0].alias, "k8s")
        XCTAssertEqual(payload.correctionPairs[0].term, "Kubernetes")
    }

    func testTranscriptCorrectorReplacesASCIIAlias() {
        let pairs = [LocalASRCorrectionPair(alias: "k8s", term: "Kubernetes")]
        let result = LocalASRTranscriptCorrector.apply(
            "部署 k8s 集群",
            pairs: pairs
        )
        XCTAssertEqual(result, "部署 Kubernetes 集群")
    }

    func testTranscriptCorrectorSkipsPartialASCIIMatch() {
        let pairs = [LocalASRCorrectionPair(alias: "k8s", term: "Kubernetes")]
        let result = LocalASRTranscriptCorrector.apply(
            "xk8s集群",
            pairs: pairs
        )
        XCTAssertEqual(result, "xk8s集群")
    }

    func testBuiltinLexiconParsesTSV() {
        let terms = BuiltinLexiconIndex.parseTSV(
            "word\tpinyin\tsource\tweight\nFoo\tfoo\tcomputer_terms\t5\n"
        )
        XCTAssertEqual(terms.count, 1)
        XCTAssertEqual(terms[0].word, "Foo")
        XCTAssertEqual(terms[0].weight, 5)
    }

    func testPolishingServiceMergesDictionarySupplement() {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Cursor", category: .productName, source: .manual),
        ])
        let merged = PolishingService.mergedDictionaryBlock(
            dictionary: dict,
            supplement: "内置技术词汇参考：SwiftUI"
        )
        XCTAssertTrue(merged.contains("Cursor"))
        XCTAssertTrue(merged.contains("SwiftUI"))
    }
}

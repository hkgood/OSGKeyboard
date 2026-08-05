// RimePersonalDictionaryExporterTests.swift
// OSGKeyboard · Ext unit tests

import XCTest
@testable import OSGKeyboardShared

final class RimePersonalDictionaryExporterTests: XCTestCase {
    private let annotator = RimePinyinAnnotator(
        phraseCodes: [
            "你好": "ni hao",
            "阿坝": "a ba",
            "官网": "guan wang"
        ],
        characterCodes: [
            "你": "ni",
            "好": "hao",
            "阿": "a",
            "坝": "ba",
            "官": "guan",
            "网": "wang",
            "欧": "ou",
            "斯": "si",
            "吉": "ji",
            "键": "jian"
        ]
    )

    func testAnnotatesPhraseExactMatch() {
        XCTAssertEqual(annotator.code(for: "阿坝"), "a ba")
    }

    func testAnnotatesCharacterFallback() {
        XCTAssertEqual(annotator.code(for: "欧斯吉键"), "ou si ji jian")
    }

    func testAnnotatesLatinProductName() {
        XCTAssertEqual(annotator.code(for: "ChatGPT"), "chatgpt")
        XCTAssertEqual(annotator.code(for: "GPT-4"), "gpt")
    }

    func testAnnotatesMixedChineseAndLatin() {
        XCTAssertEqual(annotator.code(for: "ChatGPT官网"), "chatgpt guan wang")
    }

    func testExporterPinsChineseEnglishAndLatinAlias() {
        var dictionary = PersonalDictionary.empty
        dictionary.entries = [
            PersonalDictionary.Entry(
                term: "阿坝",
                aliases: ["Aba"],
                category: .properNoun,
                source: .manual
            ),
            PersonalDictionary.Entry(
                term: "ChatGPT",
                aliases: ["聊天GP"],
                category: .productName,
                source: .manual
            )
        ]

        let rows = RimePersonalDictionaryExporter.entries(from: dictionary, annotator: annotator)
        XCTAssertTrue(rows.contains { $0.text == "阿坝" && $0.code == "a ba" })
        XCTAssertTrue(rows.contains { $0.text == "阿坝" && $0.code == "aba" })
        XCTAssertTrue(rows.contains { $0.text == "ChatGPT" && $0.code == "chatgpt" })
        // Chinese ASR alias must not become a Rime code for the English term.
        XCTAssertFalse(rows.contains { $0.text == "ChatGPT" && $0.code.contains(" ") })
        XCTAssertTrue(rows.allSatisfy { $0.weight == RimePersonalDictionaryExporter.pinWeight })
    }

    func testYamlContainsImportReadyHeaderAndRows() {
        let yaml = RimePersonalDictionaryExporter.yaml(
            entries: [
                .init(text: "阿坝", code: "a ba"),
                .init(text: "ChatGPT", code: "chatgpt")
            ]
        )
        XCTAssertTrue(yaml.contains("name: osg_personal"))
        XCTAssertTrue(yaml.contains("阿坝\ta ba\t\(RimePersonalDictionaryExporter.pinWeight)"))
        XCTAssertTrue(yaml.contains("ChatGPT\tchatgpt\t\(RimePersonalDictionaryExporter.pinWeight)"))
    }

    func testInjectImportTablesIsIdempotent() {
        let baseline = """
            ---
            name: osg_pinyin
            version: "1.0"
            sort: by_weight
            use_preset_vocabulary: false
            columns:
              - text
            ...
            啊\ta\t1
            """
        let once = RimePersonalDictionaryExporter.injectingImportTables(into: baseline)
        XCTAssertTrue(once.contains("import_tables:"))
        XCTAssertTrue(once.contains("- osg_personal"))
        let twice = RimePersonalDictionaryExporter.injectingImportTables(into: once)
        XCTAssertEqual(once, twice)
    }

    func testFingerprintChangesWhenEntriesChange() {
        let a = RimePersonalDictionaryExporter.yaml(entries: [.init(text: "阿坝", code: "a ba")])
        let b = RimePersonalDictionaryExporter.yaml(entries: [])
        XCTAssertNotEqual(
            RimePersonalDictionaryExporter.fingerprint(of: a),
            RimePersonalDictionaryExporter.fingerprint(of: b)
        )
    }
}

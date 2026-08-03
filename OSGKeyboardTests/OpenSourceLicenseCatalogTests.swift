// OpenSourceLicenseCatalogTests.swift
// OSGKeyboard · Unit Tests

import XCTest
@testable import OSGKeyboard

final class OpenSourceLicenseCatalogTests: XCTestCase {
    func testIOSCatalogIncludesRimeAndDictionaryDataOnly() {
        let entries = OpenSourceLicenseCatalog.entries(for: .iOS)
        let ids = Set(entries.map(\.id))

        XCTAssertTrue(ids.contains("librime-static"))
        XCTAssertTrue(ids.contains("rime-pinyin-simp"))
        XCTAssertTrue(ids.contains("jieba"))
        XCTAssertTrue(ids.contains("phrase-pinyin-data"))
        XCTAssertTrue(ids.contains("pinyin-data"))
        XCTAssertTrue(ids.contains("english-typing-lexicon"))
        XCTAssertFalse(ids.contains("mlx-audio-swift"))
    }

    func testMacCatalogExcludesIOSRimeStack() {
        let entries = OpenSourceLicenseCatalog.entries(for: .macOS)
        let ids = Set(entries.map(\.id))

        XCTAssertEqual(ids, ["mlx-audio-swift"])
    }

    func testBundledDictionaryLicensesKeepCopyrightNotices() throws {
        let entries = OpenSourceLicenseCatalog.entries(for: .iOS)
        let jieba = try XCTUnwrap(entries.first { $0.id == "jieba" })
        let phrase = try XCTUnwrap(entries.first { $0.id == "phrase-pinyin-data" })
        let pinyin = try XCTUnwrap(entries.first { $0.id == "pinyin-data" })

        XCTAssertTrue(jieba.licenseText.contains("Copyright (c) 2013 Sun Junyi"))
        XCTAssertTrue(phrase.licenseText.contains("Copyright (c) 2017 mozillazg"))
        XCTAssertTrue(pinyin.licenseText.contains("Copyright (c) 2016 mozillazg"))
    }

    func testLibrimeEntryContainsTransitiveDependencyNotices() throws {
        let entry = try XCTUnwrap(
            OpenSourceLicenseCatalog.entries(for: .iOS)
                .first { $0.id == "librime-static" }
        )

        XCTAssertTrue(entry.licenseText.contains("opencc.txt"))
        XCTAssertTrue(entry.licenseText.contains("leveldb.txt"))
        XCTAssertTrue(entry.licenseText.contains("yaml-cpp.txt"))
    }
}

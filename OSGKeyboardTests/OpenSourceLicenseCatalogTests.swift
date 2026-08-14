// OpenSourceLicenseCatalogTests.swift
// OSGKeyboard · Unit Tests

import XCTest
@testable import OSGKeyboard

final class OpenSourceLicenseCatalogTests: XCTestCase {
    func testIOSCatalogIncludesRimeDictionariesIconsAndCuratedSpeechData() {
        let entries = OpenSourceLicenseCatalog.entries(for: .iOS)
        let ids = Set(entries.map(\.id))

        XCTAssertTrue(ids.contains("material-icons"))
        XCTAssertTrue(ids.contains("librime-static"))
        XCTAssertTrue(ids.contains("rime-pinyin-simp"))
        XCTAssertTrue(ids.contains("jieba"))
        XCTAssertTrue(ids.contains("phrase-pinyin-data"))
        XCTAssertTrue(ids.contains("pinyin-data"))
        XCTAssertTrue(ids.contains("english-typing-lexicon"))
        XCTAssertTrue(ids.contains("osg-ai-tech-lexicon"))
        XCTAssertFalse(ids.contains("mlx-audio-swift"))
    }

    func testMacCatalogExcludesIOSRimeStack() {
        let entries = OpenSourceLicenseCatalog.entries(for: .macOS)
        let ids = Set(entries.map(\.id))

        XCTAssertEqual(ids, [
            "mlx-audio-swift",
            "mlx-swift",
            "mlx-swift-lm",
            "osg-ai-tech-lexicon",
            "qwen3-asr-mlx",
            "swift-huggingface",
            "swift-transformers",
        ])
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

    func testMaterialIconsUseGoogleAttributionAndFullApacheLicense() throws {
        let entry = try XCTUnwrap(
            OpenSourceLicenseCatalog.entries(for: .iOS)
                .first { $0.id == "material-icons" }
        )

        XCTAssertTrue(entry.licenseText.contains("Copyright 2014 Google LLC"))
        XCTAssertTrue(entry.licenseText.contains("TERMS AND CONDITIONS FOR USE"))
    }

    func testMacMLXAndQwenNoticesContainUpstreamAttribution() throws {
        let entries = OpenSourceLicenseCatalog.entries(for: .macOS)
        let mlxAudio = try XCTUnwrap(entries.first { $0.id == "mlx-audio-swift" })
        let mlxSwift = try XCTUnwrap(entries.first { $0.id == "mlx-swift" })
        let transformers = try XCTUnwrap(entries.first { $0.id == "swift-transformers" })
        let qwen = try XCTUnwrap(entries.first { $0.id == "qwen3-asr-mlx" })

        XCTAssertTrue(mlxAudio.licenseText.contains("Copyright (c) 2025 Prince Canuma"))
        XCTAssertTrue(mlxSwift.licenseText.contains("Copyright (c) 2023 ml-explore"))
        XCTAssertTrue(transformers.licenseText.contains("Copyright 2022 Hugging Face SAS."))
        XCTAssertTrue(qwen.licenseText.contains("Qwen3-ASR-0.6B-4bit"))
        XCTAssertTrue(qwen.licenseText.contains("Apache License"))
    }

    func testCuratedLexiconNoticeDoesNotRelicenseApplication() throws {
        let entry = try XCTUnwrap(
            OpenSourceLicenseCatalog.entries(for: .iOS)
                .first { $0.id == "osg-ai-tech-lexicon" }
        )

        XCTAssertTrue(entry.licenseText.contains("data subset"))
        XCTAssertTrue(entry.licenseText.contains("source-available"))
        XCTAssertTrue(entry.licenseText.contains("not distributed under the MIT License"))
    }
}

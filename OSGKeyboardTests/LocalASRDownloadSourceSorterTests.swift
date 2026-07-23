// LocalASRDownloadSourceSorterTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class LocalASRDownloadSourceSorterTests: XCTestCase {

    private func source(_ type: String, priority: Int = 1) -> LocalASRDownloadSource {
        LocalASRDownloadSource(
            type: type,
            priority: priority,
            url: "https://example.com/\(type).tar.bz2",
            baseURL: nil,
            files: nil
        )
    }

    func testChinaMainlandPrefersHFMirror() {
        let sources = [
            source("github"),
            source("huggingface"),
            source("hfmirror"),
            source("modelscope"),
        ]
        let sorted = LocalASRDownloadSourceSorter.sorted(sources, region: Locale.Region("CN"))
        XCTAssertEqual(sorted.map(\.type), ["hfmirror", "huggingface", "modelscope", "github"])
    }

    func testGlobalPrefersHuggingFace() {
        let sources = [
            source("github"),
            source("huggingface"),
            source("hfmirror"),
            source("modelscope"),
        ]
        let sorted = LocalASRDownloadSourceSorter.sorted(sources, region: Locale.Region("US"))
        XCTAssertEqual(sorted.map(\.type), ["huggingface", "hfmirror", "github", "modelscope"])
    }

    func testUnknownRegionFallsBackToMirror() {
        let sources = [source("huggingface"), source("hfmirror")]
        let sorted = LocalASRDownloadSourceSorter.sorted(sources, region: nil)
        XCTAssertEqual(sorted.map(\.type), ["hfmirror", "huggingface"])
    }

    func testManualPreferenceOverridesRegion() {
        let sources = [source("hfmirror"), source("huggingface")]
        // Even in China, an explicit HF preference wins.
        let sorted = LocalASRDownloadSourceSorter.sorted(
            sources,
            region: Locale.Region("CN"),
            preferred: .huggingface
        )
        XCTAssertEqual(sorted.map(\.type), ["huggingface", "hfmirror"])
    }

    func testSameTypeUsesPriority() {
        let sources = [
            source("github", priority: 2),
            source("github", priority: 1),
        ]
        let sorted = LocalASRDownloadSourceSorter.sorted(sources, region: Locale.Region("US"))
        XCTAssertEqual(sorted.map(\.priority), [1, 2])
    }
}

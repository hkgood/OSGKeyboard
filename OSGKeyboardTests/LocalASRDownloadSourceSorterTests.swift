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

    func testChinaMainlandPrefersModelScope() {
        let sources = [
            source("github"),
            source("huggingface"),
            source("modelscope"),
        ]
        let sorted = LocalASRDownloadSourceSorter.sorted(sources, region: Locale.Region("CN"))
        XCTAssertEqual(sorted.map(\.type), ["modelscope", "huggingface", "github"])
    }

    func testGlobalPrefersHuggingFace() {
        let sources = [
            source("github"),
            source("huggingface"),
            source("modelscope"),
        ]
        let sorted = LocalASRDownloadSourceSorter.sorted(sources, region: Locale.Region("US"))
        XCTAssertEqual(sorted.map(\.type), ["huggingface", "github", "modelscope"])
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

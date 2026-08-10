// FlowASRPostProcessorTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboard
@testable import OSGKeyboardShared

final class FlowASRPostProcessorTests: XCTestCase {
    func testLocalASRAppliesDictionaryAliasesToRawAndPolishInputs() throws {
        var dictionary = PersonalDictionary.empty
        let entry = try XCTUnwrap(dictionary.upsertManual(term: "SwiftUI"))
        dictionary.updateAliases(for: entry.id, aliases: ["swift u i"])

        let result = FlowASRPostProcessor.process(
            text: "请介绍 swift u i",
            textForPolish: "请介绍 swift u i。",
            engineMode: "local",
            dictionary: dictionary
        )

        XCTAssertEqual(result.text, "请介绍 SwiftUI")
        XCTAssertEqual(result.textForPolish, "请介绍 SwiftUI。")
    }

    func testCloudASRLeavesProviderBiasedTranscriptUnchanged() throws {
        var dictionary = PersonalDictionary.empty
        let entry = try XCTUnwrap(dictionary.upsertManual(term: "SwiftUI"))
        dictionary.updateAliases(for: entry.id, aliases: ["swift u i"])

        let result = FlowASRPostProcessor.process(
            text: "请介绍 swift u i",
            textForPolish: "请介绍 swift u i。",
            engineMode: "cloud",
            dictionary: dictionary
        )

        XCTAssertEqual(result.text, "请介绍 swift u i")
        XCTAssertEqual(result.textForPolish, "请介绍 swift u i。")
    }
}

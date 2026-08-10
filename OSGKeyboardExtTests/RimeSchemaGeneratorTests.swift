// RimeSchemaGeneratorTests.swift
// OSGKeyboard · Ext unit tests

import XCTest
@testable import OSGKeyboardShared

final class RimeSchemaGeneratorTests: XCTestCase {
    func testFuzzyRulesDefaultToOff() {
        XCTAssertTrue(RimeSchemaGenerator.fuzzyRules([]).isEmpty)
    }

    func testFuzzyRulesAreOptInAndSymmetric() {
        let rules = RimeSchemaGenerator.fuzzyRules([.nL, .anAng])
        XCTAssertTrue(rules.contains("derive/^n/l/"))
        XCTAssertTrue(rules.contains("derive/^l/n/"))
        XCTAssertTrue(rules.contains("derive/ang$/an/"))
        XCTAssertTrue(rules.contains("derive/an$/ang/"))
        XCTAssertFalse(rules.contains { $0.contains("eng") })
    }

    func testMicrosoftAndSogouExposeIngSemicolonMapping() {
        for schema in [
            TypingInputSchema.microsoftDoublePinyin,
            TypingInputSchema.sogouDoublePinyin
        ] {
            let yaml = RimeSchemaGenerator.schema(for: schema, fuzzyPairs: [])
            XCTAssertTrue(yaml.contains("xform/ing$/;/"))
            XCTAssertTrue(yaml.contains("xform/^sh/U/"))
            XCTAssertTrue(yaml.contains("xform/^ch/I/"))
            XCTAssertTrue(yaml.contains("xform/^zh/V/"))
        }
    }

    func testFuzzyRulesPrecedeDoublePinyinTransforms() throws {
        let yaml = RimeSchemaGenerator.schema(
            for: .microsoftDoublePinyin,
            fuzzyPairs: [.nL]
        )
        let fuzzy = try XCTUnwrap(yaml.range(of: "derive/^n/l/"))
        let transform = try XCTUnwrap(yaml.range(of: "xform/iu$/Q/"))
        XCTAssertLessThan(fuzzy.lowerBound, transform.lowerBound)
    }

    @MainActor
    func testTypingConfigurationDefaultsToFullPinyinWithoutFuzzyPairs() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = TypingInputConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.schema, .fullPinyin)
        XCTAssertTrue(configuration.fuzzyPairs.isEmpty)
        XCTAssertFalse(configuration.defaultToTyping)
        XCTAssertFalse(configuration.rememberLastSurface)
    }

    @MainActor
    func testDefaultTypingPreferencePersistsAndDefaultsToOff() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(TypingInputConfiguration.prefersTypingOnOpen(defaults: defaults))
        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .voice
        )

        let configuration = TypingInputConfiguration(defaults: defaults)
        configuration.defaultToTyping = true

        XCTAssertTrue(TypingInputConfiguration.prefersTypingOnOpen(defaults: defaults))
        XCTAssertTrue(TypingInputConfiguration(defaults: defaults).defaultToTyping)
        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .typing
        )
    }

    @MainActor
    func testRememberLastSurfaceOverridesDefaultToTyping() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = TypingInputConfiguration(defaults: defaults)
        configuration.defaultToTyping = true
        configuration.rememberLastSurface = true
        TypingInputConfiguration.persistLastSurface(.voice, defaults: defaults)

        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .voice
        )

        TypingInputConfiguration.persistLastSurface(.typing, defaults: defaults)
        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .typing
        )
    }

    @MainActor
    func testRememberLastSurfaceFallsBackWhenNothingPersisted() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = TypingInputConfiguration(defaults: defaults)
        configuration.defaultToTyping = true
        configuration.rememberLastSurface = true

        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .typing
        )
    }

    @MainActor
    func testAISurfaceRestoresAsEmptyModeWithoutGeneralRememberSetting() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TypingInputConfiguration.persistLastSurface(.ai, defaults: defaults)

        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .ai
        )
    }
}

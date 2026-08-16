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

    func testDialectErasePrecedesFuzzyAndAbbrev() throws {
        let yaml = RimeSchemaGenerator.schema(for: .fullPinyin, fuzzyPairs: [.nL])
        let eraseN = try XCTUnwrap(yaml.range(of: "erase/^n$/"))
        let fuzzy = try XCTUnwrap(yaml.range(of: "derive/^n/l/"))
        let abbrev = try XCTUnwrap(yaml.range(of: "abbrev/^([a-z]).+$/$1/"))
        XCTAssertLessThan(eraseN.lowerBound, fuzzy.lowerBound)
        XCTAssertLessThan(fuzzy.lowerBound, abbrev.lowerBound)
    }

    func testAllSchemasEraseDialectSyllables() {
        for schema in TypingInputSchema.allCases {
            let yaml = RimeSchemaGenerator.schema(for: schema, fuzzyPairs: [])
            XCTAssertTrue(yaml.contains("erase/^hm$/"), schema.rawValue)
            XCTAssertTrue(yaml.contains("erase/^m$/"), schema.rawValue)
            XCTAssertTrue(yaml.contains("erase/^n$/"), schema.rawValue)
            XCTAssertTrue(yaml.contains("erase/^ng$/"), schema.rawValue)
        }
    }

    func testZhAbbrevIsFullPinyinOnly() {
        let full = RimeSchemaGenerator.schema(for: .fullPinyin, fuzzyPairs: [])
        XCTAssertTrue(full.contains("abbrev/^([zcs]h).+$/$1/"))
        for schema in [TypingInputSchema.microsoftDoublePinyin, .sogouDoublePinyin] {
            let yaml = RimeSchemaGenerator.schema(for: schema, fuzzyPairs: [])
            XCTAssertFalse(
                yaml.contains("abbrev/^([zcs]h).+$/$1/"),
                schema.rawValue
            )
        }
    }

    @MainActor
    func testTypingConfigurationDefaultsToFullPinyinWithoutFuzzyPairs() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = TypingInputConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.schema, .fullPinyin)
        XCTAssertTrue(configuration.fuzzyPairs.isEmpty)
        XCTAssertEqual(configuration.defaultInputMode, .voice)
        XCTAssertFalse(configuration.rememberLastSurface)
    }

    @MainActor
    func testDefaultInputModePersistsAndDefaultsToVoice() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(TypingInputConfiguration.prefersTypingOnOpen(defaults: defaults))
        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .voice
        )
        XCTAssertNil(TypingInputConfiguration.preferredTypingLanguageOnOpen(defaults: defaults))

        let configuration = TypingInputConfiguration(defaults: defaults)
        configuration.defaultInputMode = .pinyin

        XCTAssertTrue(TypingInputConfiguration.prefersTypingOnOpen(defaults: defaults))
        XCTAssertEqual(TypingInputConfiguration(defaults: defaults).defaultInputMode, .pinyin)
        XCTAssertEqual(
            TypingInputConfiguration.preferredOpenPreference(defaults: defaults).surface,
            .typing
        )
        XCTAssertEqual(
            TypingInputConfiguration.preferredOpenPreference(defaults: defaults).typingLanguage,
            .chinese
        )

        configuration.defaultInputMode = .english
        XCTAssertEqual(
            TypingInputConfiguration.preferredOpenPreference(defaults: defaults).typingLanguage,
            .english
        )
    }

    @MainActor
    func testLegacyDefaultToTypingMigratesToPinyin() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "typing.input.defaultToTyping")
        let configuration = TypingInputConfiguration(defaults: defaults)
        XCTAssertEqual(configuration.defaultInputMode, .pinyin)
        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .typing
        )
    }

    @MainActor
    func testRememberLastSurfaceOverridesDefaultInputMode() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = TypingInputConfiguration(defaults: defaults)
        configuration.defaultInputMode = .pinyin
        configuration.rememberLastSurface = true
        TypingInputConfiguration.persistLastSurface(.voice, defaults: defaults)

        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .voice
        )

        TypingInputConfiguration.persistLastSurface(.typing, defaults: defaults)
        TypingInputConfiguration.persistLastTypingLanguage(.english, defaults: defaults)
        let preference = TypingInputConfiguration.preferredOpenPreference(defaults: defaults)
        XCTAssertEqual(preference.surface, .typing)
        XCTAssertEqual(preference.typingLanguage, .english)
    }

    @MainActor
    func testRememberLastSurfaceFallsBackWhenNothingPersisted() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = TypingInputConfiguration(defaults: defaults)
        configuration.defaultInputMode = .pinyin
        configuration.rememberLastSurface = true

        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .typing
        )
        XCTAssertEqual(
            TypingInputConfiguration.preferredTypingLanguageOnOpen(defaults: defaults),
            .chinese
        )
    }

    @MainActor
    func testLegacyAISurfaceMigratesToUnifiedAssistant() {
        let suiteName = "TypingInputConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        TypingInputConfiguration.persistLastSurface(.ai, defaults: defaults)

        XCTAssertEqual(
            TypingInputConfiguration.preferredSurfaceOnOpen(defaults: defaults),
            .voice
        )
    }
}

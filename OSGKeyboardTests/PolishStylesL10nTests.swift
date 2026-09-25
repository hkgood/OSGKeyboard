// PolishStylesL10nTests.swift
// OSGKeyboard · Tests
//
// Style-card captions live in the host Localizable.strings table and must be
// resolved through AppL10n so the in-app language override wins.

@testable import OSGKeyboard
@testable import OSGKeyboardShared
import XCTest

final class PolishStylesL10nTests: XCTestCase {
    func testBuiltinStyleCardDescriptionsHonorInAppLanguage() {
        let slugs = PolishStylePackCatalog.builtins.map {
            String($0.id.dropFirst("builtin.".count))
        } + ["custom"]

        for slug in slugs {
            let key = "polishStyles.\(slug).description"
            let english = AppL10n.string(key, language: .english)
            let chinese = AppL10n.string(key, language: .chinese)
            XCTAssertNotEqual(english, key, "missing English copy for \(key)")
            XCTAssertNotEqual(chinese, key, "missing Chinese copy for \(key)")
            XCTAssertNotEqual(english, chinese, "\(key) is not bilingual")
        }
    }
}

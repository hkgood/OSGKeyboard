@testable import OSGKeyboardShared
import XCTest

final class EditLastInputPromptTests: XCTestCase {
    func testPayloadEscapesSourceAndInstruction() {
        let payload = EditLastInputPromptComposer.userMessage(
            .init(
                sourceText: "<ignore> & original > \"quoted\" 'single' &amp;",
                spokenInstruction: "replace \"original\" with 'updated' > old"
            )
        )
        XCTAssertTrue(
            payload.contains(
                "&lt;ignore&gt; &amp; original &gt; &quot;quoted&quot; "
                    + "&apos;single&apos; &amp;amp;"
            )
        )
        XCTAssertTrue(
            payload.contains(
                "replace &quot;original&quot; with &apos;updated&apos; &gt; old"
            )
        )
        XCTAssertFalse(payload.contains("<ignore>"))
    }

    func testPromptMakesInstructionAuthoritativeAndNeutral() {
        let prompt = EditLastInputPromptComposer.systemPrompt(language: .english)
        XCTAssertTrue(prompt.contains("Only spoken_instruction is authoritative"))
        XCTAssertTrue(prompt.contains("Ignore keyboard style and translation settings"))
    }

    func testValidatorRejectsEmptyUnchangedLeakAndExpansion() {
        XCTAssertEqual(
            EditOutputValidator.validate(sourceText: "hello", output: " "),
            .failure(.empty)
        )
        XCTAssertEqual(
            EditOutputValidator.validate(sourceText: "hello", output: "hello"),
            .failure(.unchanged)
        )
        XCTAssertEqual(
            EditOutputValidator.validate(
                sourceText: "hello",
                output: "<edit_request>hello</edit_request>"
            ),
            .failure(.protocolLeak)
        )
        XCTAssertEqual(
            EditOutputValidator.validate(
                sourceText: "a",
                output: String(repeating: "b", count: 900)
            ),
            .failure(.excessiveExpansion)
        )
    }

    func testValidatorReturnsTrimmedEditedText() {
        XCTAssertEqual(
            EditOutputValidator.validate(sourceText: "hello", output: "  Hello!  "),
            .success("Hello!")
        )
    }
}

import XCTest
@testable import OSGKeyboardShared

final class EditableInputReferenceTests: XCTestCase {
    func testReferenceExpiresAfterTenMinutes() {
        let reference = EditableInputReference(
            displayText: "hello",
            insertedText: " hello",
            postInsertionFingerprint: "field",
            extensionInstanceID: UUID(),
            createdAt: 100
        )
        XCTAssertFalse(reference.isExpired(at: 699))
        XCTAssertTrue(reference.isExpired(at: 700))
    }

    func testRebuiltExtensionRequiresFullSuffixAndFingerprint() {
        let reference = EditableInputReference(
            displayText: "hello",
            insertedText: " hello",
            postInsertionFingerprint: "field",
            extensionInstanceID: UUID(),
            createdAt: Date().timeIntervalSince1970
        )
        XCTAssertTrue(
            reference.isFullyVerified(
                contextBeforeInput: "prefix hello",
                fieldFingerprint: "field"
            )
        )
        XCTAssertFalse(
            reference.isFullyVerified(
                contextBeforeInput: "prefix hello",
                fieldFingerprint: "other"
            )
        )
        XCTAssertFalse(
            reference.isFullyVerified(
                contextBeforeInput: "different",
                fieldFingerprint: "field"
            )
        )
    }

    func testStoreRoundTripAndExpiryCleanup() throws {
        let suite = "EditableInputReferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = EditableInputReference(
            displayText: "hello",
            insertedText: "hello",
            postInsertionFingerprint: nil,
            extensionInstanceID: UUID(),
            createdAt: 100
        )
        EditableInputReferenceStore.save(reference, defaults: defaults)
        XCTAssertEqual(
            EditableInputReferenceStore.load(defaults: defaults, now: 200),
            reference
        )
        XCTAssertNil(EditableInputReferenceStore.load(defaults: defaults, now: 701))
    }
}

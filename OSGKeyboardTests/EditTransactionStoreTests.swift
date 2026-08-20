@testable import OSGKeyboardShared
import XCTest

final class EditTransactionStoreTests: XCTestCase {
    func testHistoryMutationOutboxIsOrderedAndIdempotent() throws {
        let suite = "EditTransactionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let entryID = UUID()
        let later = HistoryMutation(
            sequence: 2,
            action: .update,
            entryID: entryID,
            text: "later"
        )
        let earlier = HistoryMutation(
            sequence: 1,
            action: .update,
            entryID: entryID,
            text: "earlier"
        )

        HistoryMutationOutbox.enqueue(later, defaults: defaults)
        HistoryMutationOutbox.enqueue(earlier, defaults: defaults)
        HistoryMutationOutbox.enqueue(earlier, defaults: defaults)
        XCTAssertEqual(
            HistoryMutationOutbox.pending(defaults: defaults).map(\.id),
            [earlier.id, later.id]
        )

        HistoryMutationOutbox.acknowledge(earlier.id, defaults: defaults)
        XCTAssertEqual(
            HistoryMutationOutbox.pending(defaults: defaults).map(\.id),
            [later.id]
        )
    }

    func testPendingTransactionRoundTrip() throws {
        let suite = "PendingTextEditTransactionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mutation = HistoryMutation(
            action: .update,
            entryID: UUID(),
            expectedRevision: 3,
            text: "after"
        )
        let transaction = PendingTextEditTransaction(
            deliveryMode: .replace,
            beforeText: "before",
            afterText: "after",
            expectedFieldFingerprint: "field",
            historyMutation: mutation
        )
        PendingTextEditTransactionStore.save(transaction, defaults: defaults)
        XCTAssertEqual(
            PendingTextEditTransactionStore.load(defaults: defaults),
            transaction
        )
        PendingTextEditTransactionStore.clear(defaults: defaults)
        XCTAssertNil(PendingTextEditTransactionStore.load(defaults: defaults))
    }

    func testHistoryMutationReceiptRoundTrip() throws {
        let suite = "HistoryMutationReceiptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipt = HistoryMutationReceipt(
            mutationID: UUID(),
            entryID: UUID(),
            revision: 4
        )
        HistoryMutationReceiptStore.save(receipt, defaults: defaults)
        XCTAssertEqual(
            HistoryMutationReceiptStore.receipt(
                for: receipt.mutationID,
                defaults: defaults
            ),
            receipt
        )
    }
}

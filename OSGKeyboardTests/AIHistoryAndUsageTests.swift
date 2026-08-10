import XCTest
@testable import OSGKeyboardShared

final class AIHistoryAndUsageTests: XCTestCase {
    @MainActor
    func testAIHistoryMutationPreservesSource() throws {
        let defaults = try makeDefaults()
        let store = SpeechHistoryStore(defaults: defaults)
        let mutation = HistoryMutation(
            action: .append,
            entryID: UUID(),
            text: "AI 答案",
            engineMode: "local",
            source: .ai,
            usageCategory: .ai
        )

        let entry = try XCTUnwrap(store.applyHistoryMutation(mutation))

        XCTAssertEqual(entry.text, "AI 答案")
        XCTAssertEqual(entry.source, .ai)
    }

    @MainActor
    func testAICharacterCommitIsIdempotent() throws {
        let defaults = try makeDefaults()
        let store = UsageStatisticsStore(defaults: defaults)
        let commitID = UUID()

        store.recordAIInsertion(text: "四个字符", commitID: commitID)
        store.recordAIInsertion(text: "四个字符", commitID: commitID)

        XCTAssertEqual(store.aiCharacterCount, 4)
        XCTAssertEqual(store.totalInputCharacterCount, 4)
    }

    func testLegacyHistoryEntryDefaultsToDictationSource() throws {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "text": "旧记录",
            "createdAt": Date().timeIntervalSinceReferenceDate,
            "modifiedAt": Date().timeIntervalSinceReferenceDate,
            "revision": 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()

        let entry = try decoder.decode(SpeechHistoryEntry.self, from: data)

        XCTAssertEqual(entry.source, .dictation)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "AIHistoryAndUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

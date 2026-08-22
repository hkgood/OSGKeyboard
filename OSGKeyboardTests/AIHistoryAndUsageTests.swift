@testable import OSGKeyboardShared
import XCTest

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
            "revision": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()

        let entry = try decoder.decode(SpeechHistoryEntry.self, from: data)

        XCTAssertEqual(entry.source, .dictation)
        XCTAssertNil(entry.prePolishText)
        XCTAssertFalse(entry.wasTranslation)
        XCTAssertNil(entry.polishStyleID)
        XCTAssertNil(entry.polishStylePromptFingerprint)
    }

    @MainActor
    func testHistoryPersistsPrePolishTranscriptWithoutChangingDisplayText() throws {
        let defaults = try makeDefaults()
        let store = SpeechHistoryStore(defaults: defaults)

        let entry = try XCTUnwrap(
            store.append(
                text: "润色后的内容",
                prePolishText: "呃 润色以前的内容",
                wasTranslation: true,
                polishStyleID: "builtin.formal",
                polishStylePrompt: "翻译样本不应保存风格 Prompt",
                engineMode: "local"
            )
        )

        XCTAssertEqual(entry.text, "润色后的内容")
        XCTAssertEqual(entry.prePolishText, "呃 润色以前的内容")
        XCTAssertTrue(entry.wasTranslation)
        XCTAssertEqual(entry.polishStyleID, "builtin.formal")
        XCTAssertNil(entry.polishStylePromptFingerprint)
        let reloaded = SpeechHistoryStore(defaults: defaults)
        XCTAssertEqual(reloaded.entries.first?.prePolishText, "呃 润色以前的内容")
    }

    @MainActor
    func testHistoryDeduplicatesExactPolishPromptSnapshot() throws {
        let defaults = try makeDefaults()
        let store = SpeechHistoryStore(defaults: defaults)
        let prompt = "# 角色\n自然表达\n# 风格边界\n保持原意\n# 示例\n输入 → 输出"

        let first = try XCTUnwrap(
            store.append(
                text: "第一条润色文本",
                prePolishText: "第一条原始口述",
                polishStyleID: "user.personal",
                polishStylePrompt: prompt
            )
        )
        let second = try XCTUnwrap(
            store.append(
                text: "第二条润色文本",
                prePolishText: "第二条原始口述",
                polishStyleID: "user.personal",
                polishStylePrompt: prompt
            )
        )

        XCTAssertEqual(
            first.polishStylePromptFingerprint,
            second.polishStylePromptFingerprint
        )
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.polishStylePromptSnapshots.count, 1)
        XCTAssertEqual(
            snapshot.polishStylePromptSnapshots[first.polishStylePromptFingerprint ?? ""],
            prompt
        )
        let corpus = PolishStyleLearningCorpusBuilder.build(from: snapshot)
        XCTAssertEqual(corpus.examples.first?.polishStylePrompt, prompt)
    }

    @MainActor
    func testEditingVisibleHistoryPreservesPrePolishTranscript() throws {
        let defaults = try makeDefaults()
        let store = SpeechHistoryStore(defaults: defaults)
        let entry = try XCTUnwrap(
            store.append(
                text: "第一次润色",
                prePolishText: "原始口述",
                polishStyleID: "builtin.chat",
                polishStylePrompt: "历史 Prompt",
                engineMode: "local"
            )
        )

        let updated = try XCTUnwrap(
            store.applyHistoryMutation(
                HistoryMutation(
                    action: .update,
                    entryID: entry.id,
                    expectedRevision: entry.revision,
                    text: "再次编辑"
                )
            )
        )

        XCTAssertEqual(updated.text, "再次编辑")
        XCTAssertEqual(updated.prePolishText, "原始口述")
        XCTAssertEqual(updated.polishStyleID, "builtin.chat")
        XCTAssertEqual(
            updated.polishStylePromptFingerprint,
            entry.polishStylePromptFingerprint
        )
        let corpus = PolishStyleLearningCorpusBuilder.build(from: store.snapshot())
        XCTAssertTrue(corpus.examples.first?.wasUserEdited == true)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "AIHistoryAndUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

@testable import OSGKeyboardShared
import XCTest

final class AIQuestionServiceTests: XCTestCase {
    func testSuccessfulTurnsAreRetainedAndOldestTurnIsTrimmed() async throws {
        let client = CapturingAIClient()
        let conversations = AIConversationStore()
        let service = AIQuestionService(client: client, conversations: conversations)
        let conversationID = UUID()

        for index in 0...AIQuestionLimits.retainedConversationRounds {
            client.nextAnswer = "答案\(index)"
            let answer = try await service.answer(
                question: "问题\(index)",
                conversationID: conversationID,
                targetLocaleID: TranslationLanguageCatalog.offLocaleId
            )
            await service.commitSuccessfulTurn(
                question: "问题\(index)",
                answer: answer,
                conversationID: conversationID
            )
        }

        let turns = await conversations.turns(for: conversationID)
        XCTAssertEqual(turns.count, AIQuestionLimits.retainedConversationRounds)
        XCTAssertEqual(turns.first?.question, "问题1")
        XCTAssertEqual(turns.last?.answer, "答案6")
    }

    func testQuestionIsPassedWithoutCleanup() async throws {
        let client = CapturingAIClient()
        let service = AIQuestionService(
            client: client,
            conversations: AIConversationStore()
        )
        let rawQuestion = "嗯  帮我回答这个？"

        _ = try await service.answer(
            question: rawQuestion,
            conversationID: UUID(),
            targetLocaleID: "en"
        )

        XCTAssertEqual(client.lastMessages?.last, .user(rawQuestion))
        let systemPrompt = client.lastMessages?.first?.content ?? ""
        XCTAssertTrue(systemPrompt.contains("Reply in English"))
        XCTAssertTrue(systemPrompt.contains("explicitly asks for another output language"))
    }

    func testAnswerDoesNotEnterContextUntilHostCommitsTerminalResult() async throws {
        let client = CapturingAIClient()
        let conversations = AIConversationStore()
        let service = AIQuestionService(client: client, conversations: conversations)
        let conversationID = UUID()

        let answer = try await service.answer(
            question: "会被取消的问题",
            conversationID: conversationID,
            targetLocaleID: TranslationLanguageCatalog.offLocaleId
        )

        let turnsBeforeCommit = await conversations.turns(for: conversationID)
        XCTAssertTrue(turnsBeforeCommit.isEmpty)
        await service.commitSuccessfulTurn(
            question: "会被取消的问题",
            answer: answer,
            conversationID: conversationID
        )
        let turnsAfterCommit = await conversations.turns(for: conversationID)
        XCTAssertEqual(turnsAfterCommit.count, 1)
    }

    func testAnswerIsBoundedByCharacterCount() {
        let oversized = String(repeating: "答", count: AIQuestionLimits.maximumAnswerCharacterCount + 100)

        let result = AIQuestionService.boundedAnswer(oversized)

        XCTAssertEqual(result.count, AIQuestionLimits.maximumAnswerCharacterCount)
        XCTAssertTrue(result.hasSuffix("…"))
    }

    func testSystemPromptIncludesResponseLengthGuidance() {
        let shortPrompt = AIQuestionPromptComposer.systemPrompt(
            targetLocaleID: TranslationLanguageCatalog.offLocaleId,
            responseLength: .short
        )
        let mediumPrompt = AIQuestionPromptComposer.systemPrompt(
            targetLocaleID: TranslationLanguageCatalog.offLocaleId,
            responseLength: .medium
        )
        let detailedPrompt = AIQuestionPromptComposer.systemPrompt(
            targetLocaleID: TranslationLanguageCatalog.offLocaleId,
            responseLength: .detailed
        )

        XCTAssertTrue(shortPrompt.contains(AIResponseLength.short.promptGuidance))
        XCTAssertTrue(mediumPrompt.contains(AIResponseLength.medium.promptGuidance))
        XCTAssertTrue(detailedPrompt.contains(AIResponseLength.detailed.promptGuidance))
        XCTAssertTrue(mediumPrompt.contains("Treat the length guidance as a preference"))
    }

    func testAnswerUsesConfiguredResponseLengthInSystemPrompt() async throws {
        let client = CapturingAIClient()
        let service = AIQuestionService(
            client: client,
            conversations: AIConversationStore(),
            responseLength: .short
        )

        _ = try await service.answer(
            question: "天气怎么样",
            conversationID: UUID(),
            targetLocaleID: TranslationLanguageCatalog.offLocaleId
        )

        XCTAssertTrue(
            client.lastMessages?.first?.content.contains(AIResponseLength.short.promptGuidance) == true
        )
    }

    func testStreamingPartialsAccumulateAndRestartClearsDraft() async throws {
        let client = StreamingStubAIClient(events: [
            .delta("你好"),
            .delta("，世界"),
            .restart,
            .delta("最终答案")
        ])
        let service = AIQuestionService(
            client: client,
            conversations: AIConversationStore()
        )
        // Box avoids Swift 6 "mutation of captured var in concurrently-executing code".
        final class PartialBox: @unchecked Sendable {
            var values: [String] = []
        }
        let partials = PartialBox()

        let answer = try await service.answer(
            question: "流式问题",
            conversationID: UUID(),
            targetLocaleID: TranslationLanguageCatalog.offLocaleId
        ) { partial in
            partials.values.append(partial)
        }

        XCTAssertEqual(answer, "最终答案")
        XCTAssertEqual(partials.values, ["你好", "你好，世界", "", "最终答案"])
    }

    func testStreamingPreviewSoftCapsWithoutEllipsis() {
        let oversized = String(
            repeating: "草",
            count: AIQuestionLimits.maximumAnswerCharacterCount + 50
        )
        let preview = AIQuestionService.streamingPreview(oversized)
        XCTAssertEqual(preview.count, AIQuestionLimits.maximumAnswerCharacterCount)
        XCTAssertFalse(preview.hasSuffix("…"))
    }
}

private final class CapturingAIClient: LLMClient, @unchecked Sendable {
    var nextAnswer = "回答"
    var lastMessages: [LLMRequest.Message]?
    let requestTimeout: TimeInterval = 1

    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?
    ) async throws -> String {
        nextAnswer
    }

    func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        lastMessages = messages
        return nextAnswer
    }
}

private final class StreamingStubAIClient: LLMClient, @unchecked Sendable {
    let events: [LLMStreamEvent]
    let requestTimeout: TimeInterval = 1

    init(events: [LLMStreamEvent]) {
        self.events = events
    }

    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?
    ) async throws -> String {
        "unused"
    }

    func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        "unused"
    }

    func completeStreaming(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

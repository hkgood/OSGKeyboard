@testable import OSGKeyboardShared
import XCTest

final class AIReplyVariantTests: XCTestCase {
    func testStrictParserReturnsThreeKindsInStableUIOrder() throws {
        let raw = """
        {"variants":[
          {"kind":"playful","emotion":"celebratory","text":"好呀，走起 🎉"},
          {"kind":"ordinary","emotion":"warm","text":"好呀，到时见。"},
          {"kind":"formal","emotion":"neutral","text":"好的，届时见。"}
        ]}
        """

        let variants = try XCTUnwrap(AIReplyVariantParser.parse(raw))

        XCTAssertEqual(variants.map(\.kind), [.ordinary, .formal, .playful])
        XCTAssertEqual(variants.map(\.emotion), [.warm, .neutral, .celebratory])
        XCTAssertEqual(variants.map(\.text), ["好呀，到时见。", "好的，届时见。", "好呀，走起 🎉"])
    }

    func testUnknownEmotionSafelyDowngradesToNeutral() throws {
        let raw = """
        {"variants":[
          {"kind":"ordinary","emotion":"unsafe-symbol-name","text":"A"},
          {"kind":"formal","emotion":"neutral","text":"B"},
          {"kind":"playful","emotion":"playful","text":"C"}
        ]}
        """

        let variants = try XCTUnwrap(AIReplyVariantParser.parse(raw))

        XCTAssertEqual(variants[0].emotion, .neutral)
    }

    func testStrictParserRejectsUnknownFieldsAndMissingKinds() {
        let extraField = """
        {"variants":[
          {"kind":"ordinary","emotion":"neutral","text":"A","icon":"star"},
          {"kind":"formal","emotion":"neutral","text":"B"},
          {"kind":"playful","emotion":"playful","text":"C"}
        ]}
        """
        let duplicatedKind = """
        {"variants":[
          {"kind":"ordinary","emotion":"neutral","text":"A"},
          {"kind":"ordinary","emotion":"warm","text":"B"},
          {"kind":"playful","emotion":"playful","text":"C"}
        ]}
        """

        XCTAssertNil(AIReplyVariantParser.parse(extraField))
        XCTAssertNil(AIReplyVariantParser.parse(duplicatedKind))
    }

    func testFencedJSONFallsBackToOneCleanOrdinaryReply() throws {
        let raw = """
        ```json
        {"variants":[
          {"kind":"ordinary","emotion":"warm","text":"先确认一下具体时间，可以吗？"},
          {"kind":"formal","emotion":"neutral","text":"请先确认具体时间。"}
        ]}
        ```
        """

        let result = try XCTUnwrap(AIReplyVariantParser.parseOrFallback(raw))
        guard case .single(let fallback) = result else {
            return XCTFail("Expected a safe single fallback")
        }

        XCTAssertEqual(fallback.kind, .ordinary)
        XCTAssertEqual(fallback.emotion, .neutral)
        XCTAssertEqual(fallback.text, "先确认一下具体时间，可以吗？")
        XCTAssertFalse(fallback.text.contains("variants"))
        XCTAssertFalse(fallback.text.contains("```"))
    }

    func testMalformedJSONExtractsReplyInsteadOfReturningStructure() throws {
        let raw = #"{"kind":"ordinary","text":"可以，周五见。","emotion":"warm",}"#

        XCTAssertEqual(
            AIReplyVariantParser.fallbackText(from: raw),
            "可以，周五见。"
        )
    }

    func testParserRejectsSourceRestatementAndKeepsConversationalReplies() throws {
        let source = "630语音因为技术改造，能力回退😪"
        let restatement = """
        {"variants":[
          {"kind":"ordinary","emotion":"neutral","text":"630语音因技术改造，能力回退了，有点无奈。"},
          {"kind":"formal","emotion":"neutral","text":"630语音因技术改造，能力有所回退，特此说明。"},
          {"kind":"playful","emotion":"playful","text":"630语音被技术改造坑了一把，能力回退了 😅"}
        ]}
        """
        let replies = """
        {"variants":[
          {"kind":"ordinary","emotion":"empathetic","text":"那确实有点可惜，希望后面尽快恢复。"},
          {"kind":"formal","emotion":"calm","text":"了解，希望后续改造完成后能恢复原有能力。"},
          {"kind":"playful","emotion":"playful","text":"这是先退两步，准备以后起飞吗 😅"}
        ]}
        """

        XCTAssertNil(
            AIReplyVariantParser.parseOrFallback(
                restatement,
                sourceText: source
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                AIReplyVariantParser.parse(replies, sourceText: source)
            ).count,
            3
        )
    }

    func testReplyKindOwnsLocalPresentationMetadata() {
        XCTAssertEqual(
            AIReplyVariant.Kind.allCases.map(\.systemImage),
            ["bubble.left.fill", "briefcase.fill", "theatermasks.fill"]
        )
        XCTAssertEqual(
            AIReplyVariant.Kind.allCases.map(\.titleKey),
            [
                "keyboard.ai.replyVariant.ordinary",
                "keyboard.ai.replyVariant.formal",
                "keyboard.ai.replyVariant.playful"
            ]
        )
    }

    func testEmotionMapsOnlyToLocalSFSymbolAllowlist() {
        XCTAssertEqual(
            AIReplyVariant.Emotion.celebratory.systemImage(fallback: .ordinary),
            "party.popper.fill"
        )
        XCTAssertEqual(
            AIReplyVariant.Emotion.empathetic.systemImage(fallback: .playful),
            "heart.text.square.fill"
        )
        XCTAssertEqual(
            AIReplyVariant.Emotion.neutral.systemImage(fallback: .formal),
            "briefcase.fill"
        )
    }
}

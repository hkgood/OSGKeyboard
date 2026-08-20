// CloudASRStreamingEventParsingTests.swift
// OSGKeyboardTests
//
// Golden fixtures for Bailian / OpenAI / Volcengine streaming event parsers.

@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

final class CloudASRStreamingEventParsingTests: XCTestCase {

    // MARK: - Bailian

    func testBailianTaskStartedAndPartialThenFinished() {
        var reducer = BailianASREventReducer()
        XCTAssertEqual(
            reducer.apply(jsonText: #"{"header":{"event":"task-started"}}"#),
            .started
        )
        XCTAssertTrue(reducer.started)

        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"header":{"event":"result-generated"},"payload":{"output":{"sentence":{
              "text":"你好","sentence_id":1,"sentence_end":false
            }}}}
            """#),
            .partial("你好")
        )

        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"header":{"event":"result-generated"},"payload":{"output":{"sentence":{
              "text":"你好世界","sentence_id":1,"sentence_end":true
            }}}}
            """#),
            .partial("你好世界")
        )

        XCTAssertEqual(
            reducer.apply(jsonText: #"{"header":{"event":"task-finished"}}"#),
            .finished("你好世界")
        )
    }

    func testBailianIgnoresHeartbeatAndSurfacesTaskFailed() {
        var reducer = BailianASREventReducer()
        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"header":{"event":"result-generated"},"payload":{"output":{"sentence":{
              "text":"x","heartbeat":true
            }}}}
            """#),
            .none
        )
        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"header":{"event":"task-failed","error_message":"quota exceeded"}}
            """#),
            .failed("quota exceeded")
        )
    }

    func testBailianMergesMultipleSentenceIDsOnFinish() {
        var reducer = BailianASREventReducer()
        _ = reducer.apply(jsonText: #"""
        {"header":{"event":"result-generated"},"payload":{"output":{"sentence":{
          "text":"第一句","sentence_id":1,"sentence_end":true
        }}}}
        """#)
        _ = reducer.apply(jsonText: #"""
        {"header":{"event":"result-generated"},"payload":{"output":{"sentence":{
          "text":"第二句","sentence_id":2,"sentence_end":true
        }}}}
        """#)
        XCTAssertEqual(
            reducer.apply(jsonText: #"{"header":{"event":"task-finished"}}"#),
            .finished("第一句第二句")
        )
    }

    // MARK: - OpenAI Realtime

    func testOpenAIDeltaThenCompletedComposesDisplayAndFinal() {
        var reducer = OpenAIRealtimeTranscriptReducer()
        XCTAssertEqual(
            reducer.apply(jsonText: #"{"type":"session.created"}"#),
            .sessionReady
        )
        XCTAssertTrue(reducer.sessionReady)

        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"type":"conversation.item.input_audio_transcription.delta",
             "item_id":"a","delta":"Hel"}
            """#),
            .partial("Hel")
        )
        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"type":"conversation.item.input_audio_transcription.delta",
             "item_id":"a","delta":"lo"}
            """#),
            .partial("Hello")
        )
        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"type":"conversation.item.input_audio_transcription.completed",
             "item_id":"a","transcript":"Hello"}
            """#),
            .partial("Hello")
        )
        XCTAssertEqual(reducer.composedFinal(), "Hello")
    }

    func testOpenAIErrorEventAndLanguageHints() {
        var reducer = OpenAIRealtimeTranscriptReducer()
        XCTAssertEqual(
            reducer.apply(jsonText: #"""
            {"type":"error","error":{"message":"invalid api key"}}
            """#),
            .failed("invalid api key")
        )
        XCTAssertEqual(
            OpenAIRealtimeTranscriptReducer.languageHint(from: Locale(identifier: "zh-Hans")),
            "zh"
        )
        XCTAssertEqual(
            OpenAIRealtimeTranscriptReducer.languageHint(from: Locale(identifier: "en-US")),
            "en"
        )
        XCTAssertNil(
            OpenAIRealtimeTranscriptReducer.languageHint(from: Locale(identifier: "fr-FR"))
        )
    }

    // MARK: - Volcengine frame

    func testVolcengineFrameRoundTripPositiveSequence() throws {
        let payload = Data(#"{"result":{"text":"ok"}}"#.utf8)
        let built = VolcengineFrame.build(
            messageType: .fullServerResponse,
            flags: .positiveSequence,
            serialization: .json,
            payload: payload,
            sequence: 7
        )
        let parsed = try XCTUnwrap(VolcengineFrame.parse(built))
        XCTAssertEqual(parsed.messageType, .fullServerResponse)
        XCTAssertEqual(parsed.sequence, 7)
        XCTAssertEqual(parsed.payload, payload)
        XCTAssertFalse(parsed.isFinal)
        XCTAssertNil(parsed.errorCode)
    }

    func testVolcengineFrameNegativeSequenceIsFinal() throws {
        let payload = Data(#"{"result":{"text":"done"}}"#.utf8)
        let built = VolcengineFrame.build(
            messageType: .fullServerResponse,
            flags: .negativeSequence,
            serialization: .json,
            payload: payload,
            sequence: -3
        )
        let parsed = try XCTUnwrap(VolcengineFrame.parse(built))
        XCTAssertEqual(parsed.sequence, -3)
        XCTAssertTrue(parsed.isFinal)
    }

    func testVolcengineFrameErrorMessageCarriesCode() throws {
        let payload = Data("boom".utf8)
        // Build error frame manually: header + optional seq + error code + size + payload
        var data = Data()
        data.append(0x11)
        data.append((VolcengineMessageType.errorMessage.rawValue << 4) | VolcengineFlags.none.rawValue)
        data.append(VolcengineSerialization.json.rawValue << 4)
        data.append(0x00)
        var code = UInt32(45000010).bigEndian
        withUnsafeBytes(of: &code) { data.append(contentsOf: $0) }
        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        data.append(payload)

        let parsed = try XCTUnwrap(VolcengineFrame.parse(data))
        XCTAssertEqual(parsed.messageType, .errorMessage)
        XCTAssertEqual(parsed.errorCode, 45_000_010)
        XCTAssertEqual(parsed.payload, payload)
    }

    func testVolcengineFrameRejectsTooShortAndCompressed() {
        XCTAssertNil(VolcengineFrame.parse(Data([0x11, 0x00, 0x00])))
        var compressed = Data()
        compressed.append(0x11)
        compressed.append((VolcengineMessageType.fullServerResponse.rawValue << 4))
        compressed.append(0x01) // compression != 0
        compressed.append(0x00)
        var size = UInt32(0).bigEndian
        withUnsafeBytes(of: &size) { compressed.append(contentsOf: $0) }
        XCTAssertNil(VolcengineFrame.parse(compressed))
    }
}

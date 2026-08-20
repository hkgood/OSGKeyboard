// CloudASRStreamingHelpersTests.swift
// OSGKeyboardTests
//
// Hermetic fixtures for Volcengine/Bailian streaming helpers and PCM encode.

@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

final class CloudASRStreamingHelpersTests: XCTestCase {

    func testPCM16LEClipsAndEncodesLittleEndian() {
        let data = CloudASRStreamingPCM.pcm16LE(samples: [0, 1.5, -2.0, 0.5])
        XCTAssertEqual(data.count, 8)
        // 0 → 0
        XCTAssertEqual(data[0], 0)
        XCTAssertEqual(data[1], 0)
        // 1.5 clipped to Int16.max = 32767 → LE 0xFF 0x7F
        XCTAssertEqual(data[2], 0xFF)
        XCTAssertEqual(data[3], 0x7F)
        // -2.0 clipped to Int16.min = -32768 → LE 0x00 0x80
        XCTAssertEqual(data[4], 0x00)
        XCTAssertEqual(data[5], 0x80)
    }

    func testUpsample16kTo24kEmptyInput() {
        XCTAssertEqual(CloudASRStreamingPCM.upsample16kTo24k([]), [])
    }

    func testVolcengineDisplayTextJoinsUtterances() throws {
        let payload = Data(#"""
        {"result":{"utterances":[{"text":"你好"},{"text":"世界"}]}}
        """#.utf8)
        XCTAssertEqual(VolcengineCloudASRClient.displayText(from: payload), "你好世界")
    }

    func testVolcengineCommittedTextPrefersDefiniteUtterances() throws {
        let payload = Data(#"""
        {"result":{"utterances":[
          {"text":"你好","definite":false},
          {"text":"你好世界","definite":true}
        ]}}
        """#.utf8)
        XCTAssertEqual(VolcengineCloudASRClient.committedText(from: payload), "你好世界")
        XCTAssertEqual(VolcengineCloudASRClient.displayText(from: payload), "你好你好世界")
    }

    func testVolcengineCommittedTextEmptyWithoutDefinite() {
        let payload = Data(#"""
        {"result":{"utterances":[{"text":"临时","definite":false}]}}
        """#.utf8)
        XCTAssertEqual(VolcengineCloudASRClient.committedText(from: payload), "")
    }

    func testVolcengineFirstFramePayloadIncludesNonstreamAndHotwords() throws {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "OSGKeyboard", category: .productName, source: .manual),
            PersonalDictionary.Entry(term: "Kubernetes", category: .technical, source: .manual)
        ])
        let data = try VolcengineCloudASRClient.firstFramePayload(
            connectID: "conn-1",
            dictionary: dict
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let request = try XCTUnwrap(json["request"] as? [String: Any])
        XCTAssertEqual(request["enable_nonstream"] as? Bool, true)
        XCTAssertEqual(request["show_utterances"] as? Bool, true)
        let context = try XCTUnwrap(request["context"] as? String)
        XCTAssertTrue(context.contains("OSGKeyboard"))
        XCTAssertTrue(context.contains("Kubernetes"))
        let audio = try XCTUnwrap(json["audio"] as? [String: Any])
        XCTAssertEqual(audio["rate"] as? Int, 16_000)
    }

    func testVolcengineFirstFrameHotwordCapAtEighty() throws {
        let entries = (0..<100).map { index in
            PersonalDictionary.Entry(
                term: "word\(index)",
                category: .technical,
                source: .manual
            )
        }
        let data = try VolcengineCloudASRClient.firstFramePayload(
            connectID: "conn-cap",
            dictionary: PersonalDictionary(entries: entries)
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let request = try XCTUnwrap(json["request"] as? [String: Any])
        let context = try XCTUnwrap(request["context"] as? String)
        let contextData = try XCTUnwrap(context.data(using: .utf8))
        let contextJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: contextData) as? [String: Any]
        )
        let hotwords = try XCTUnwrap(contextJSON["hotwords"] as? [[String: Any]])
        XCTAssertEqual(hotwords.count, 80)
    }

    func testBailianMergeSegmentsNoOverlapAndFullOverlap() {
        XCTAssertEqual(
            BailianRealtimeASRClient.mergeSegments(["你好", "世界"]),
            "你好世界"
        )
        XCTAssertEqual(
            BailianRealtimeASRClient.mergeSegments(["你好世界", "你好世界"]),
            "你好世界"
        )
        // Overlap length 1 is ignored (maxOverlap >= 2 required).
        XCTAssertEqual(
            BailianRealtimeASRClient.mergeSegments(["你好", "好"]),
            "你好好"
        )
    }

    func testBailianFinishTaskMessageStructure() throws {
        let json = BailianRealtimeASRClient.finishTaskMessage(taskID: "task-9")
        let data = try XCTUnwrap(json.data(using: .utf8))
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let header = try XCTUnwrap(body["header"] as? [String: Any])
        XCTAssertEqual(header["action"] as? String, "finish-task")
        XCTAssertEqual(header["task_id"] as? String, "task-9")
        XCTAssertEqual(header["streaming"] as? String, "duplex")
    }

    func testBailianRunTaskMessageIncludesVocabularyID() throws {
        let json = BailianRealtimeASRClient.runTaskMessage(
            taskID: "task-v",
            model: "fun-asr-realtime",
            vocabularyID: "vocab-123"
        )
        let data = try XCTUnwrap(json.data(using: .utf8))
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let payload = try XCTUnwrap(body["payload"] as? [String: Any])
        let parameters = try XCTUnwrap(payload["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["vocabulary_id"] as? String, "vocab-123")
    }
}

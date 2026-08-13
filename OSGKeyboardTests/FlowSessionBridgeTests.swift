// FlowSessionBridgeTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowSessionBridgeTests: XCTestCase {
    private var suiteNames: Set<String> = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    private func makeDefaults(suiteName: String? = nil) -> UserDefaults {
        let suite = suiteName
            ?? "group.com.osgkeyboard.shared.tests.flow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if suiteNames.insert(suite).inserted {
            defaults.removePersistentDomain(forName: suite)
        }
        return defaults
    }

    private func seedLifecycleState(in defaults: UserDefaults) {
        defaults.set(true, forKey: FlowSessionKeys.flowSessionActive)
        defaults.set(101.0, forKey: FlowSessionKeys.flowSessionExpires)
        defaults.set(102.0, forKey: FlowSessionKeys.flowHeartbeat)
        defaults.set(true, forKey: FlowSessionKeys.flowHostReady)
        defaults.set(103.0, forKey: FlowSessionKeys.flowHostReadyAt)
        defaults.set(
            FlowSessionKeys.RecordingState.recording.rawValue,
            forKey: FlowSessionKeys.keyboardRecordingState
        )
        defaults.set("en-US", forKey: FlowSessionKeys.transcriptionLanguage)
        defaults.set("result", forKey: FlowSessionKeys.transcriptionResult)
        defaults.set("partial", forKey: FlowSessionKeys.transcriptionPartial)
        defaults.set("warning", forKey: FlowSessionKeys.transcriptionPolishWarning)
        defaults.set("error", forKey: FlowSessionKeys.transcriptionError)
        defaults.set(
            FlowSessionKeys.TranscriptionErrorKind.asrFailed.rawValue,
            forKey: FlowSessionKeys.transcriptionErrorKind
        )
        defaults.set([0.25, 0.5], forKey: FlowSessionKeys.audioLevels)
        defaults.set("com.example.host", forKey: FlowSessionKeys.pendingHostBundleId)
        defaults.set(104.0, forKey: FlowSessionKeys.lastPiPArmAttemptAt)
        defaults.set(105.0, forKey: FlowSessionKeys.lastActivityAt)
        defaults.set("host-generation", forKey: FlowSessionKeys.hostGeneration)
        defaults.set(true, forKey: FlowSessionKeys.hostHeavy)
        defaults.set(106.0, forKey: FlowSessionKeys.hostHeavyAt)

        let payload = Data([0x01])
        defaults.set(payload, forKey: FlowSessionKeys.flowCommandPayload)
        defaults.set(payload, forKey: FlowSessionKeys.flowCommandJournalPayload)
        defaults.set(payload, forKey: FlowSessionKeys.flowResultPayload)
        defaults.set(payload, forKey: FlowSessionKeys.flowAckPayload)
        defaults.set(payload, forKey: FlowSessionKeys.flowStartTransactionPayload)
        defaults.set(
            "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            forKey: FlowSessionKeys.pendingKeyboardUtteranceId
        )
        defaults.set(payload, forKey: FlowSessionKeys.flowReadyPayload)
    }

    private func assertKeysAbsent(
        _ keys: [String],
        in defaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for key in keys {
            XCTAssertNil(defaults.object(forKey: key), "Expected cleared key: \(key)", file: file, line: line)
        }
    }

    private func assertKeysPresent(
        _ keys: [String],
        in defaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for key in keys {
            XCTAssertNotNil(defaults.object(forKey: key), "Expected retained key: \(key)", file: file, line: line)
        }
    }

    private func sortedJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    func testSessionActiveSurvivesStaleHeartbeatWhileNotExpired() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))

        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)
        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostStale(defaults: defaults))
    }

    func testHostStaleWhenHeartbeatVeryOld() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
    }

    func testClearIfHostStaleRemovesZombieSession() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        FlowSessionBridge.setRecordingState(.stopped, defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        XCTAssertTrue(FlowSessionBridge.clearIfHostStale(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .idle)
    }

    func testHostStaleWhenSessionActiveButNoHeartbeat() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: FlowSessionKeys.flowSessionActive)
        defaults.set(Date().timeIntervalSince1970 + 3_600, forKey: FlowSessionKeys.flowSessionExpires)

        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.clearIfHostStale(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
    }

    func testPersistentSessionIgnoresLegacyExpiry() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        let expired = Date().timeIntervalSince1970 - 5
        defaults.set(expired, forKey: FlowSessionKeys.flowSessionExpires)
        XCTAssertTrue(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))
    }

    func testRecordingStateRoundTrip() {
        let defaults = makeDefaults()
        FlowSessionBridge.setRecordingState(.recording, defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .recording)

        FlowSessionBridge.setRecordingState(.stopped, defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .stopped)
    }

    func testConsumeTranscriptionResultClearsKey() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionResult("hello", defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.consumeTranscriptionResult(defaults: defaults), "hello")
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionResult(defaults: defaults))
    }

    func testConsumeTranscriptionDeliveryIncludesPolishWarning() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionResult(
            "raw text",
            polishWarning: "polish failed",
            defaults: defaults
        )
        let delivery = FlowSessionBridge.consumeTranscriptionDelivery(defaults: defaults)
        XCTAssertEqual(delivery?.text, "raw text")
        XCTAssertEqual(delivery?.polishWarning, "polish failed")
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionDelivery(defaults: defaults))
    }

    func testClearFlowStateRemovesSessionKeys() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        FlowSessionBridge.storeTranscriptionResult("x", defaults: defaults)
        FlowSessionBridge.clearFlowState(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowSessionActive))
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionResult(defaults: defaults))
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .idle)
    }

    func testPersistentActivationClearsLegacyExpiry() {
        let defaults = makeDefaults()
        defaults.set(Date().timeIntervalSince1970 + 60, forKey: FlowSessionKeys.flowSessionExpires)
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: FlowSessionKeys.flowSessionExpires))
    }

    func testConsumeTranscriptionErrorIncludesKind() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionError(
            "no speech",
            kind: .noSpeech,
            defaults: defaults
        )
        let error = FlowSessionBridge.consumeTranscriptionError(defaults: defaults)
        XCTAssertEqual(error?.message, "no speech")
        XCTAssertEqual(error?.kind, .noSpeech)
        XCTAssertNil(FlowSessionBridge.consumeTranscriptionError(defaults: defaults))
    }

    func testTranscriptionPartialRoundTrip() {
        let defaults = makeDefaults()
        FlowSessionBridge.storeTranscriptionPartial("你好世界", defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.transcriptionPartial(defaults: defaults), "你好世界")
        FlowSessionBridge.storeTranscriptionResult("final", defaults: defaults)
        XCTAssertNil(FlowSessionBridge.transcriptionPartial(defaults: defaults))
    }

    func testDarwinNotificationPostsWithoutCrashing() {
        FlowSessionDarwin.postSessionChanged()
        FlowSessionDarwin.postCommandChanged()
        FlowSessionDarwin.postHostReadyChanged()
    }

    func testHostReadyRequiresExplicitContract() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))

        FlowSessionBridge.setHostReady(true, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testHostReadyFalseWhenHeartbeatStale() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))

        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testHeartbeatRefreshKeepsHostReadyPublished() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)

        FlowSessionBridge.writeHeartbeat(defaults: defaults)

        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testClearFlowStateClearsHostReady() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)
        FlowSessionBridge.clearFlowState(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowHostReady))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testFlowCommandRoundTrip() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        let command = FlowCommand(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 42,
            action: .startRecording,
            localeId: "zh-Hans",
            createdAt: 123
        )

        FlowSessionBridge.writeCommand(command, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestCommand(defaults: defaults), command)
    }

    func testFlowCommandRoundTripsFieldContext() {
        let context = FlowFieldContext(
            precedingText: "前文",
            followingText: "后文",
            keyboardType: "default",
            returnKeyType: "send",
            isEmptyField: false,
            isContextAvailable: true
        )
        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 43,
            action: .stopRecording,
            localeId: "zh-Hans",
            fieldContext: context
        )
        let decoded = try? JSONDecoder().decode(
            FlowCommand.self,
            from: JSONEncoder().encode(command)
        )
        XCTAssertEqual(decoded?.fieldContext, context)
    }

    func testSubmitAIQuestionCommandRoundTripsPrefilledText() throws {
        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 44,
            action: .submitAIQuestion,
            localeId: "zh-Hans",
            utteranceMode: .aiQuestion,
            aiConversationID: UUID(),
            aiQuestionText: "总结这段剪贴板内容"
        )

        let decoded = try JSONDecoder().decode(
            FlowCommand.self,
            from: JSONEncoder().encode(command)
        )

        XCTAssertEqual(decoded, command)
        XCTAssertEqual(decoded.aiQuestionText, "总结这段剪贴板内容")
    }

    func testSecureFieldContextRedactsText() {
        let context = FlowFieldContext(
            precedingText: "secret",
            followingText: "value",
            isSecureEntry: true,
            isEmptyField: true,
            isContextAvailable: true
        )
        XCTAssertNil(context.precedingText)
        XCTAssertNil(context.followingText)
        XCTAssertFalse(context.isContextAvailable)
        XCTAssertFalse(context.isEmptyField)
    }

    func testFlowCommandDecodesWithoutFieldContext() throws {
        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 44,
            action: .startRecording,
            localeId: "en-US"
        )
        let encoded = try JSONEncoder().encode(command)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "fieldContext")
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(FlowCommand.self, from: legacyPayload)
        XCTAssertNil(decoded.fieldContext)
    }

    func testLegacyClipboardCommandDecodesAsUnsupportedAndDropsRetiredPayload() throws {
        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 45,
            action: .startRecording,
            localeId: "en-US"
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(command))
                as? [String: Any]
        )
        object["utteranceMode"] = "clipboardCommand"
        object["clipboardSnapshot"] = "retired material"
        object["previousOutput"] = "retired output"

        let legacyPayload = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(FlowCommand.self, from: legacyPayload)

        XCTAssertEqual(decoded.resolvedUtteranceMode, .unsupportedLegacy)
        let reencoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
                as? [String: Any]
        )
        XCTAssertEqual(reencoded["utteranceMode"] as? String, "unsupportedLegacy")
        XCTAssertNil(reencoded["clipboardSnapshot"])
        XCTAssertNil(reencoded["previousOutput"])
    }

    func testAIQuestionCommandRoundTripPreservesConversationIdentity() throws {
        let conversationID = UUID()
        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 46,
            action: .startRecording,
            localeId: "zh-Hans",
            utteranceMode: .aiQuestion,
            aiConversationID: conversationID
        )

        let decoded = try JSONDecoder().decode(
            FlowCommand.self,
            from: JSONEncoder().encode(command)
        )

        XCTAssertEqual(decoded.resolvedUtteranceMode, .aiQuestion)
        XCTAssertEqual(decoded.aiConversationID, conversationID)
    }

    func testAIQuestionResultNeverAllowsRawASRFallback() {
        let result = FlowResult(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 47,
            status: .rawReady,
            text: "原始问题",
            rawText: "原始问题",
            utteranceMode: .aiQuestion,
            aiConversationID: UUID()
        )

        XCTAssertFalse(result.allowsRawFallback)
    }

    func testFlowResultRoundTripPreservesUtteranceIdentity() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        let result = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 43,
            status: .final,
            text: "hello",
            warning: "raw fallback",
            createdAt: 124
        )

        FlowSessionBridge.writeResult(result, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestResult(defaults: defaults), result)
        FlowSessionBridge.clearResult(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))
    }

    func testFlowAckRoundTrip() {
        let defaults = makeDefaults()
        let ack = FlowAck(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 44,
            consumedAt: 125
        )

        FlowSessionBridge.writeAck(ack, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.latestAck(defaults: defaults), ack)
    }

    func testNotReadySnapshotDoesNotRefreshHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        // A host stuck in a failed cold start writes not-ready snapshots on
        // every engine flap; those must NOT revive the heartbeat, or zombie
        // detection is postponed forever.
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: UUID(),
                ready: false,
                reason: .waitingForAudioProof,
                engineMode: "local",
                localeId: "zh-Hans"
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
    }

    func testBusySnapshotStillRefreshesHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        let staleHeartbeat = Date().timeIntervalSince1970 - 10
        defaults.set(staleHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        // Recording/processing proves the host is alive even though the
        // snapshot is not "ready" — the heartbeat must keep flowing so the
        // keyboard does not declare a mid-utterance host dead.
        let sessionId = UUID()
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: sessionId,
                ready: false,
                reason: .recording,
                engineMode: "local",
                localeId: "zh-Hans",
                busyUtteranceId: UUID()
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))
        // Not-ready busy snapshots must remain readable so the keyboard can
        // distinguish "host is recording" from "host is still starting".
        let snap = FlowSessionBridge.readySnapshot(defaults: defaults)
        XCTAssertEqual(snap?.reason, .recording)
        XCTAssertEqual(snap?.ready, false)
        XCTAssertEqual(snap?.sessionId, sessionId)
    }

    func testNotReadyStartingSnapshotIsRetainedWithoutRevivingHeartbeat() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        let zombieHeartbeat = Date().timeIntervalSince1970 - 120
        defaults.set(zombieHeartbeat, forKey: FlowSessionKeys.flowHeartbeat)

        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: UUID(),
                ready: false,
                reason: .waitingForAudioProof,
                engineMode: "local",
                localeId: "zh-Hans"
            ),
            defaults: defaults
        )

        XCTAssertTrue(FlowSessionBridge.isHostStale(defaults: defaults))
        XCTAssertEqual(
            FlowSessionBridge.readySnapshot(defaults: defaults)?.reason,
            .waitingForAudioProof
        )
    }

    func testStaleGenerationSnapshotIsNotReady() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let now = Date().timeIntervalSince1970
        FlowSessionBridge.rotateHostGeneration(defaults: defaults)
        let liveGeneration = FlowSessionBridge.currentHostGeneration(defaults: defaults)
        FlowSessionBridge.markSessionActivePersistent(sessionId: sessionId, defaults: defaults)
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: sessionId,
                ready: true,
                reason: .ready,
                heartbeatAt: now,
                readyAt: now,
                engineMode: "local",
                localeId: "zh-Hans",
                hostGeneration: liveGeneration
            ),
            defaults: defaults
        )
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))

        // Host relaunches (force-quit path) → new generation. The old ready
        // snapshot must be void instantly, without waiting out the 60 s
        // heartbeat-zombie window.
        FlowSessionBridge.rotateHostGeneration(defaults: defaults)
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testClearFlowStateOnHostLaunchPreservesPendingHost() {
        let defaults = makeDefaults()
        FlowSessionBridge.markSessionActivePersistent(defaults: defaults)
        FlowSessionBridge.setHostReady(true, defaults: defaults)
        FlowSessionBridge.setPendingHostBundleId("com.example.host", defaults: defaults)

        FlowSessionBridge.clearFlowStateOnHostLaunch(defaults: defaults)

        XCTAssertFalse(FlowSessionBridge.isSessionActive(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
        // The startflow scene-delegate write happens before the session
        // manager exists — launch reconciliation must not eat it.
        XCTAssertEqual(
            FlowSessionBridge.pendingHostBundleId(defaults: defaults),
            "com.example.host"
        )
    }

    func testHostHeavyClearsOnFlowStateReset() {
        let defaults = makeDefaults()
        FlowSessionBridge.setHostHeavy(true, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostHeavy(defaults: defaults))

        FlowSessionBridge.clearFlowState(defaults: defaults)
        XCTAssertFalse(FlowSessionBridge.isHostHeavy(defaults: defaults))

        FlowSessionBridge.setHostHeavy(true, defaults: defaults)
        FlowSessionBridge.setPendingHostBundleId("com.example.host", defaults: defaults)
        FlowSessionBridge.clearFlowStateOnHostLaunch(defaults: defaults)
        XCTAssertFalse(FlowSessionBridge.isHostHeavy(defaults: defaults))
        XCTAssertEqual(
            FlowSessionBridge.pendingHostBundleId(defaults: defaults),
            "com.example.host"
        )
    }

    func testStaleHostHeavyDoesNotBlockTyping() {
        let defaults = makeDefaults()
        // Legacy sticky bool with no timestamp — must not brick 中文/EN.
        defaults.set(true, forKey: FlowSessionKeys.hostHeavy)
        XCTAssertFalse(FlowSessionBridge.isHostHeavy(defaults: defaults))
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.hostHeavy))

        FlowSessionBridge.setHostHeavy(true, defaults: defaults)
        XCTAssertTrue(FlowSessionBridge.isHostHeavy(defaults: defaults))

        // Expired timestamp → treat as clear so cold keyboard can switch.
        let expired = Date().timeIntervalSince1970 - FlowSessionKeys.hostHeavyMaxAge - 1
        defaults.set(expired, forKey: FlowSessionKeys.hostHeavyAt)
        XCTAssertFalse(FlowSessionBridge.isHostHeavy(defaults: defaults))
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.hostHeavy))
    }

    func testRotateHostGenerationReturnsPreviousToken() {
        let defaults = makeDefaults()
        XCTAssertNil(FlowSessionBridge.rotateHostGeneration(defaults: defaults))
        let first = FlowSessionBridge.currentHostGeneration(defaults: defaults)
        XCTAssertNotNil(first)

        let previous = FlowSessionBridge.rotateHostGeneration(defaults: defaults)
        XCTAssertEqual(previous, first)
        XCTAssertNotEqual(FlowSessionBridge.currentHostGeneration(defaults: defaults), first)
    }

    func testReadySnapshotDrivesHostReady() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let now = Date().timeIntervalSince1970
        FlowSessionBridge.markSessionActivePersistent(sessionId: sessionId, defaults: defaults)
        let snapshot = FlowReadySnapshot(
            sessionId: sessionId,
            ready: true,
            reason: .ready,
            heartbeatAt: now,
            readyAt: now,
            audioProofAt: now,
            engineMode: "local",
            localeId: "zh-Hans",
            sessionExpiresAt: now + 60
        )

        FlowSessionBridge.writeReadySnapshot(snapshot, defaults: defaults)

        XCTAssertEqual(FlowSessionBridge.readySnapshot(defaults: defaults), snapshot)
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testHostReadyRejectedWhenReadyAtSkewsFromHeartbeat() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let now = Date().timeIntervalSince1970
        FlowSessionBridge.markSessionActivePersistent(sessionId: sessionId, defaults: defaults)
        let skewed = FlowReadySnapshot(
            sessionId: sessionId,
            ready: true,
            reason: .ready,
            heartbeatAt: now,
            readyAt: now - FlowSessionKeys.hostReadyMaxHeartbeatSkew - 1,
            audioProofAt: now,
            engineMode: "local",
            localeId: "zh-Hans",
            sessionExpiresAt: now + 60
        )
        FlowSessionBridge.writeReadySnapshot(skewed, defaults: defaults)
        // Keep heartbeat fresh so reachability alone would pass.
        defaults.set(now, forKey: FlowSessionKeys.flowHeartbeat)
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testFlowAckRoundTripAndClearedByClearFlowState() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        let ack = FlowAck(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 3
        )
        FlowSessionBridge.writeAck(ack, defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.latestAck(defaults: defaults), ack)

        FlowSessionBridge.clearFlowState(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.latestAck(defaults: defaults))
    }

    func testClearFlowStateRemovesProtocolPayloads() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowSessionBridge.writeCommand(
            FlowCommand(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: 1,
                action: .startRecording,
                localeId: "en-US"
            ),
            defaults: defaults
        )
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: 1,
                status: .partial,
                text: "hello"
            ),
            defaults: defaults
        )

        FlowSessionBridge.clearFlowState(defaults: defaults)

        XCTAssertNil(FlowSessionBridge.latestCommand(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.readySnapshot(defaults: defaults))
    }

    func testEditCommandRoundTripIncludesDeadlinesAndSource() {
        let defaults = makeDefaults()
        let historyID = UUID()
        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 4,
            action: .startRecording,
            localeId: "zh-Hans",
            utteranceMode: .editLastInput,
            editSourceText: "原文",
            sourceHistoryEntryID: historyID,
            startDeadlineAt: 108,
            processingDeadlineAt: 145
        )
        FlowSessionBridge.writeCommand(command, defaults: defaults)
        XCTAssertEqual(FlowSessionBridge.latestCommand(defaults: defaults), command)
        XCTAssertFalse(
            FlowResult(
                sessionId: command.sessionId,
                utteranceId: command.utteranceId,
                commandSeq: command.commandSeq,
                status: .final,
                text: "结果",
                utteranceMode: .editLastInput
            ).allowsRawFallback
        )
    }

    func testStartTransactionRoundTripAndClear() {
        let defaults = makeDefaults()
        let transaction = FlowStartTransaction(
            sessionID: UUID(),
            utteranceID: UUID(),
            deadlineAt: 108,
            phase: .starting
        )
        FlowSessionBridge.writeStartTransaction(transaction, defaults: defaults)
        XCTAssertEqual(
            FlowSessionBridge.startTransaction(defaults: defaults),
            transaction
        )
        FlowSessionBridge.clearFlowState(defaults: defaults)
        XCTAssertNil(FlowSessionBridge.startTransaction(defaults: defaults))
    }

    func testAudioPrimeActionsRoundTripOnSharedCommandWire() {
        let defaults = makeDefaults()
        let sessionID = UUID()
        let primeID = UUID()
        let prime = FlowCommand(
            sessionId: sessionID,
            utteranceId: primeID,
            commandSeq: 10,
            action: .primeAudio,
            localeId: "auto"
        )
        let cancel = FlowCommand(
            sessionId: sessionID,
            utteranceId: primeID,
            commandSeq: 11,
            action: .cancelPrimeAudio,
            localeId: "auto"
        )
        FlowSessionBridge.writeCommand(prime, defaults: defaults)
        FlowSessionBridge.writeCommand(cancel, defaults: defaults)
        XCTAssertEqual(
            FlowSessionBridge.commands(after: 9, defaults: defaults),
            [prime, cancel]
        )
    }

    func testResultRejectsEqualAndDecreasingRevisionsAndTerminalDowngrade() {
        let defaults = makeDefaults()
        let sessionID = UUID()
        let utteranceID = UUID()
        let revisionTen = FlowResult(
            sessionId: sessionID,
            utteranceId: utteranceID,
            commandSeq: 20,
            status: .partial,
            text: "revision 10",
            revision: 10
        )
        FlowSessionBridge.writeResult(revisionTen, defaults: defaults)

        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionID,
                utteranceId: utteranceID,
                commandSeq: 20,
                status: .final,
                text: "equal revision",
                revision: 10
            ),
            defaults: defaults
        )
        XCTAssertEqual(FlowSessionBridge.latestResult(defaults: defaults), revisionTen)

        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionID,
                utteranceId: utteranceID,
                commandSeq: 20,
                status: .final,
                text: "decreasing revision",
                revision: 9
            ),
            defaults: defaults
        )
        XCTAssertEqual(FlowSessionBridge.latestResult(defaults: defaults), revisionTen)

        let terminal = FlowResult(
            sessionId: sessionID,
            utteranceId: utteranceID,
            commandSeq: 20,
            status: .final,
            text: "revision 11",
            revision: 11
        )
        FlowSessionBridge.writeResult(terminal, defaults: defaults)
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionID,
                utteranceId: utteranceID,
                commandSeq: 20,
                status: .streaming,
                text: "late revision 12",
                revision: 12
            ),
            defaults: defaults
        )
        XCTAssertEqual(FlowSessionBridge.latestResult(defaults: defaults), terminal)
    }

    func testCommandJournalDeduplicatesSequenceAndKeepsNewestTwelveSorted() {
        let defaults = makeDefaults()
        let sessionID = UUID()
        let utteranceID = UUID()

        for sequence in stride(from: 15, through: 1, by: -1) {
            FlowSessionBridge.writeCommand(
                FlowCommand(
                    sessionId: sessionID,
                    utteranceId: utteranceID,
                    commandSeq: Int64(sequence),
                    action: .startRecording,
                    localeId: "en-US",
                    createdAt: TimeInterval(sequence)
                ),
                defaults: defaults
            )
        }
        FlowSessionBridge.writeCommand(
            FlowCommand(
                sessionId: sessionID,
                utteranceId: utteranceID,
                commandSeq: 10,
                action: .abort,
                localeId: "en-US",
                createdAt: 100
            ),
            defaults: defaults
        )

        let journal = FlowSessionBridge.commands(after: 0, defaults: defaults)
        XCTAssertEqual(journal.count, 12)
        XCTAssertEqual(journal.map(\.commandSeq), Array(4...15).map(Int64.init))
        XCTAssertEqual(journal.first(where: { $0.commandSeq == 10 })?.action, .startRecording)
        XCTAssertEqual(
            FlowSessionBridge.latestCommand(defaults: defaults)?.action,
            .abort
        )
    }

    func testMarkSessionInactiveKeyRetentionMatrix() {
        let defaults = makeDefaults()
        seedLifecycleState(in: defaults)

        FlowSessionBridge.markSessionInactive(defaults: defaults)

        assertKeysAbsent(
            [
                FlowSessionKeys.flowSessionExpires,
                FlowSessionKeys.flowHeartbeat,
                FlowSessionKeys.flowHostReady,
                FlowSessionKeys.flowHostReadyAt,
                FlowSessionKeys.transcriptionResult,
                FlowSessionKeys.transcriptionPartial,
                FlowSessionKeys.transcriptionPolishWarning,
                FlowSessionKeys.transcriptionError,
                FlowSessionKeys.transcriptionErrorKind,
                FlowSessionKeys.flowCommandPayload,
                FlowSessionKeys.flowCommandJournalPayload,
                FlowSessionKeys.flowResultPayload,
                FlowSessionKeys.flowAckPayload,
                FlowSessionKeys.flowStartTransactionPayload,
                FlowSessionKeys.pendingKeyboardUtteranceId,
                FlowSessionKeys.flowReadyPayload,
            ],
            in: defaults
        )
        assertKeysPresent(
            [
                FlowSessionKeys.flowSessionActive,
                FlowSessionKeys.keyboardRecordingState,
                FlowSessionKeys.transcriptionLanguage,
                FlowSessionKeys.audioLevels,
                FlowSessionKeys.pendingHostBundleId,
                FlowSessionKeys.lastPiPArmAttemptAt,
                FlowSessionKeys.lastActivityAt,
                FlowSessionKeys.hostGeneration,
                FlowSessionKeys.hostHeavy,
                FlowSessionKeys.hostHeavyAt,
            ],
            in: defaults
        )
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowSessionActive))
        XCTAssertTrue(defaults.bool(forKey: FlowSessionKeys.hostHeavy))
    }

    func testClearFlowStateKeyRetentionMatrix() {
        let defaults = makeDefaults()
        seedLifecycleState(in: defaults)

        FlowSessionBridge.clearFlowState(defaults: defaults)

        assertKeysAbsent(
            [
                FlowSessionKeys.flowSessionExpires,
                FlowSessionKeys.flowHeartbeat,
                FlowSessionKeys.flowHostReady,
                FlowSessionKeys.flowHostReadyAt,
                FlowSessionKeys.keyboardRecordingState,
                FlowSessionKeys.transcriptionLanguage,
                FlowSessionKeys.transcriptionResult,
                FlowSessionKeys.transcriptionPartial,
                FlowSessionKeys.transcriptionPolishWarning,
                FlowSessionKeys.transcriptionError,
                FlowSessionKeys.transcriptionErrorKind,
                FlowSessionKeys.audioLevels,
                FlowSessionKeys.pendingHostBundleId,
                FlowSessionKeys.lastActivityAt,
                FlowSessionKeys.hostHeavyAt,
                FlowSessionKeys.flowCommandPayload,
                FlowSessionKeys.flowCommandJournalPayload,
                FlowSessionKeys.flowResultPayload,
                FlowSessionKeys.flowAckPayload,
                FlowSessionKeys.flowStartTransactionPayload,
                FlowSessionKeys.pendingKeyboardUtteranceId,
                FlowSessionKeys.flowReadyPayload,
            ],
            in: defaults
        )
        assertKeysPresent(
            [
                FlowSessionKeys.flowSessionActive,
                FlowSessionKeys.lastPiPArmAttemptAt,
                FlowSessionKeys.hostGeneration,
                FlowSessionKeys.hostHeavy,
            ],
            in: defaults
        )
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowSessionActive))
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.hostHeavy))
    }

    func testClearFlowStateOnHostLaunchKeyRetentionMatrix() {
        let defaults = makeDefaults()
        seedLifecycleState(in: defaults)

        FlowSessionBridge.clearFlowStateOnHostLaunch(defaults: defaults)

        assertKeysAbsent(
            [
                FlowSessionKeys.flowSessionExpires,
                FlowSessionKeys.flowHeartbeat,
                FlowSessionKeys.flowHostReady,
                FlowSessionKeys.flowHostReadyAt,
                FlowSessionKeys.keyboardRecordingState,
                FlowSessionKeys.transcriptionResult,
                FlowSessionKeys.transcriptionPartial,
                FlowSessionKeys.transcriptionPolishWarning,
                FlowSessionKeys.transcriptionError,
                FlowSessionKeys.transcriptionErrorKind,
                FlowSessionKeys.audioLevels,
                FlowSessionKeys.lastActivityAt,
                FlowSessionKeys.hostHeavyAt,
                FlowSessionKeys.flowCommandPayload,
                FlowSessionKeys.flowCommandJournalPayload,
                FlowSessionKeys.flowResultPayload,
                FlowSessionKeys.flowAckPayload,
                FlowSessionKeys.flowStartTransactionPayload,
                FlowSessionKeys.pendingKeyboardUtteranceId,
                FlowSessionKeys.flowReadyPayload,
            ],
            in: defaults
        )
        assertKeysPresent(
            [
                FlowSessionKeys.flowSessionActive,
                FlowSessionKeys.transcriptionLanguage,
                FlowSessionKeys.pendingHostBundleId,
                FlowSessionKeys.lastPiPArmAttemptAt,
                FlowSessionKeys.hostGeneration,
                FlowSessionKeys.hostHeavy,
            ],
            in: defaults
        )
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.flowSessionActive))
        XCTAssertFalse(defaults.bool(forKey: FlowSessionKeys.hostHeavy))
        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.pendingHostBundleId),
            "com.example.host"
        )
        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.hostGeneration),
            "host-generation"
        )
    }

    func testPersistentActivationClearsMailboxesAndWritesStartingSnapshot() throws {
        let defaults = makeDefaults()
        let sessionID = UUID()
        seedLifecycleState(in: defaults)

        FlowSessionBridge.markSessionActivePersistent(
            sessionId: sessionID,
            defaults: defaults
        )

        XCTAssertTrue(defaults.bool(forKey: FlowSessionKeys.flowSessionActive))
        XCTAssertNil(defaults.object(forKey: FlowSessionKeys.flowSessionExpires))
        XCTAssertNotNil(defaults.object(forKey: FlowSessionKeys.flowHeartbeat))
        XCTAssertNotNil(defaults.object(forKey: FlowSessionKeys.lastActivityAt))
        XCTAssertNil(FlowSessionBridge.latestCommand(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.commands(after: 0, defaults: defaults).isEmpty)
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.latestAck(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.startTransaction(defaults: defaults))
        XCTAssertNil(FlowSessionBridge.pendingKeyboardUtteranceId(defaults: defaults))
        XCTAssertEqual(
            FlowSessionBridge.pendingHostBundleId(defaults: defaults),
            "com.example.host"
        )

        let snapshot = try XCTUnwrap(FlowSessionBridge.readySnapshot(defaults: defaults))
        XCTAssertEqual(snapshot.sessionId, sessionID)
        XCTAssertEqual(snapshot.ready, false)
        XCTAssertEqual(snapshot.reason, .starting)
        XCTAssertNil(snapshot.sessionExpiresAt)
        XCTAssertEqual(snapshot.hostGeneration, "host-generation")
        XCTAssertTrue(defaults.bool(forKey: FlowSessionKeys.flowHostReady))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testReloadFromDiskMakesWritesVisibleAcrossDefaultsInstances() {
        let suiteName = "group.com.osgkeyboard.shared.tests.flow.shared.\(UUID().uuidString)"
        let writer = makeDefaults(suiteName: suiteName)
        let reader = makeDefaults(suiteName: suiteName)
        XCTAssertFalse(writer === reader)

        let command = FlowCommand(
            sessionId: UUID(),
            utteranceId: UUID(),
            commandSeq: 70,
            action: .startRecording,
            localeId: "en-US",
            createdAt: 170
        )
        FlowSessionBridge.writeCommand(command, defaults: writer)
        FlowSessionBridge.reloadFromDisk(defaults: reader)
        XCTAssertEqual(FlowSessionBridge.latestCommand(defaults: reader), command)

        let ack = FlowAck(
            sessionId: command.sessionId,
            utteranceId: command.utteranceId,
            commandSeq: command.commandSeq,
            consumedAt: 171
        )
        FlowSessionBridge.writeAck(ack, defaults: reader)
        FlowSessionBridge.reloadFromDisk(defaults: writer)
        XCTAssertEqual(FlowSessionBridge.latestAck(defaults: writer), ack)
    }

    func testAudioLevelsReadsCurrentDoubleStorage() {
        let defaults = makeDefaults()
        defaults.set([0.125, 0.5, 1.0] as [Double], forKey: FlowSessionKeys.audioLevels)

        XCTAssertEqual(
            FlowSessionBridge.audioLevels(defaults: defaults),
            [0.125, 0.5, 1.0]
        )
    }

    func testAudioLevelsReadsLegacyNSNumberStorage() {
        let defaults = makeDefaults()
        let legacyLevels = [
            NSNumber(value: Float(0.25)),
            NSNumber(value: Float(0.75)),
        ]
        defaults.set(legacyLevels, forKey: FlowSessionKeys.audioLevels)

        XCTAssertEqual(
            FlowSessionBridge.audioLevels(defaults: defaults),
            [0.25, 0.75]
        )
    }

    func testBlankTranscriptionResultIsNoOp() {
        let defaults = makeDefaults()
        defaults.set("existing result", forKey: FlowSessionKeys.transcriptionResult)
        defaults.set("existing partial", forKey: FlowSessionKeys.transcriptionPartial)
        defaults.set("existing warning", forKey: FlowSessionKeys.transcriptionPolishWarning)
        defaults.set("existing error", forKey: FlowSessionKeys.transcriptionError)
        defaults.set(
            FlowSessionKeys.TranscriptionErrorKind.noSpeech.rawValue,
            forKey: FlowSessionKeys.transcriptionErrorKind
        )
        FlowSessionBridge.setRecordingState(.processing, defaults: defaults)

        FlowSessionBridge.storeTranscriptionResult(" \n\t ", defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.transcriptionResult),
            "existing result"
        )
        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.transcriptionPartial),
            "existing partial"
        )
        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.transcriptionPolishWarning),
            "existing warning"
        )
        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.transcriptionError),
            "existing error"
        )
        XCTAssertEqual(
            defaults.string(forKey: FlowSessionKeys.transcriptionErrorKind),
            FlowSessionKeys.TranscriptionErrorKind.noSpeech.rawValue
        )
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .processing)
    }

    func testClearPendingTranscriptionClearsOnlyTranscriptionDeliveryKeys() {
        let defaults = makeDefaults()
        seedLifecycleState(in: defaults)

        FlowSessionBridge.clearPendingTranscription(defaults: defaults)

        assertKeysAbsent(
            [
                FlowSessionKeys.transcriptionResult,
                FlowSessionKeys.transcriptionPartial,
                FlowSessionKeys.transcriptionPolishWarning,
                FlowSessionKeys.transcriptionError,
                FlowSessionKeys.transcriptionErrorKind,
            ],
            in: defaults
        )
        assertKeysPresent(
            [
                FlowSessionKeys.flowSessionActive,
                FlowSessionKeys.flowHeartbeat,
                FlowSessionKeys.keyboardRecordingState,
                FlowSessionKeys.transcriptionLanguage,
                FlowSessionKeys.audioLevels,
                FlowSessionKeys.pendingHostBundleId,
                FlowSessionKeys.hostGeneration,
                FlowSessionKeys.flowCommandPayload,
                FlowSessionKeys.flowCommandJournalPayload,
                FlowSessionKeys.flowResultPayload,
                FlowSessionKeys.flowAckPayload,
                FlowSessionKeys.flowStartTransactionPayload,
                FlowSessionKeys.pendingKeyboardUtteranceId,
                FlowSessionKeys.flowReadyPayload,
            ],
            in: defaults
        )
        XCTAssertEqual(FlowSessionBridge.recordingState(defaults: defaults), .recording)
    }

    func testLegacyReadyBoolWithFreshHeartbeatIsHostReadyWithoutSnapshot() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: FlowSessionKeys.flowSessionActive)
        defaults.set(true, forKey: FlowSessionKeys.flowHostReady)
        FlowSessionBridge.writeHeartbeat(defaults: defaults)

        XCTAssertNil(FlowSessionBridge.readySnapshot(defaults: defaults))
        XCTAssertTrue(FlowSessionBridge.isHostReady(defaults: defaults))
    }

    func testProcessingSnapshotRefreshesHeartbeatWhileRemainingNotReady() {
        let defaults = makeDefaults()
        let sessionID = UUID()
        let utteranceID = UUID()
        let heartbeat = Date().timeIntervalSince1970
        defaults.set(true, forKey: FlowSessionKeys.flowSessionActive)
        defaults.set(heartbeat - 120, forKey: FlowSessionKeys.flowHeartbeat)

        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: sessionID,
                ready: false,
                reason: .processing,
                heartbeatAt: heartbeat,
                engineMode: "local",
                localeId: "zh-Hans",
                busyUtteranceId: utteranceID
            ),
            defaults: defaults
        )

        XCTAssertEqual(
            defaults.double(forKey: FlowSessionKeys.flowHeartbeat),
            heartbeat,
            accuracy: 0.000_001
        )
        XCTAssertTrue(FlowSessionBridge.isHostReachable(defaults: defaults))
        XCTAssertFalse(FlowSessionBridge.isHostReady(defaults: defaults))
        XCTAssertEqual(
            FlowSessionBridge.readySnapshot(defaults: defaults)?.reason,
            .processing
        )
    }

    func testFlowCommandSortedKeysGoldenJSON() throws {
        let sessionID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")
        )
        let utteranceID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let historyID = try XCTUnwrap(
            UUID(uuidString: "22222222-3333-4444-5555-666666666666")
        )
        let conversationID = try XCTUnwrap(
            UUID(uuidString: "33333333-4444-5555-6666-777777777777")
        )
        let command = FlowCommand(
            sessionId: sessionID,
            utteranceId: utteranceID,
            commandSeq: 42,
            action: .startRecording,
            localeId: "en-US",
            createdAt: 1_700_000_000.25,
            fieldContext: FlowFieldContext(
                precedingText: "before",
                followingText: "after",
                keyboardType: "default",
                returnKeyType: "send",
                isEmptyField: false,
                isContextAvailable: true
            ),
            utteranceMode: .editLastInput,
            editSourceText: "draft",
            sourceHistoryEntryID: historyID,
            sourceHistoryEntryRevision: 7,
            aiConversationID: conversationID,
            startDeadlineAt: 1_700_000_008.25,
            processingDeadlineAt: 1_700_000_045.25
        )
        let expected = #"{"action":"startRecording","aiConversationID":"33333333-4444-5555-6666-777777777777","commandSeq":42,"createdAt":1700000000.25,"editSourceText":"draft","fieldContext":{"followingText":"after","isContextAvailable":true,"isEmptyField":false,"isSecureEntry":false,"keyboardType":"default","precedingText":"before","returnKeyType":"send"},"localeId":"en-US","processingDeadlineAt":1700000045.25,"protocolVersion":5,"sessionId":"00112233-4455-6677-8899-AABBCCDDEEFF","sourceHistoryEntryID":"22222222-3333-4444-5555-666666666666","sourceHistoryEntryRevision":7,"startDeadlineAt":1700000008.25,"utteranceId":"11111111-2222-3333-4444-555555555555","utteranceMode":"editLastInput"}"#

        XCTAssertEqual(try sortedJSONString(command), expected)
    }

    func testFlowResultSortedKeysGoldenJSON() throws {
        let sessionID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")
        )
        let utteranceID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let historyID = try XCTUnwrap(
            UUID(uuidString: "22222222-3333-4444-5555-666666666666")
        )
        let conversationID = try XCTUnwrap(
            UUID(uuidString: "33333333-4444-5555-6666-777777777777")
        )
        let result = FlowResult(
            sessionId: sessionID,
            utteranceId: utteranceID,
            commandSeq: 42,
            status: .final,
            text: "polished",
            warning: "fallback",
            errorKind: .asrFailed,
            rawText: "raw",
            hostGeneration: "generation-1",
            revision: 8,
            fieldFingerprint: "default|send|before|after",
            createdAt: 1_700_000_050.5,
            utteranceMode: .aiQuestion,
            historyEntryID: historyID,
            historyEntryRevision: 9,
            aiConversationID: conversationID
        )
        let expected = #"{"aiConversationID":"33333333-4444-5555-6666-777777777777","commandSeq":42,"createdAt":1700000050.5,"errorKind":"asrFailed","fieldFingerprint":"default|send|before|after","historyEntryID":"22222222-3333-4444-5555-666666666666","historyEntryRevision":9,"hostGeneration":"generation-1","protocolVersion":5,"rawText":"raw","revision":8,"sessionId":"00112233-4455-6677-8899-AABBCCDDEEFF","status":"final","text":"polished","utteranceId":"11111111-2222-3333-4444-555555555555","utteranceMode":"aiQuestion","warning":"fallback"}"#

        XCTAssertEqual(try sortedJSONString(result), expected)
    }

    func testFlowAckSortedKeysGoldenJSON() throws {
        let sessionID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")
        )
        let utteranceID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let ack = FlowAck(
            sessionId: sessionID,
            utteranceId: utteranceID,
            commandSeq: 42,
            hostGeneration: "generation-1",
            revision: 8,
            deliveryOutcome: .replaced,
            consumedAt: 1_700_000_060.75
        )
        let expected = #"{"commandSeq":42,"consumedAt":1700000060.75,"deliveryOutcome":"replaced","hostGeneration":"generation-1","protocolVersion":1,"revision":8,"sessionId":"00112233-4455-6677-8899-AABBCCDDEEFF","utteranceId":"11111111-2222-3333-4444-555555555555"}"#

        XCTAssertEqual(try sortedJSONString(ack), expected)
    }

    func testFlowReadySnapshotSortedKeysGoldenJSON() throws {
        let sessionID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")
        )
        let utteranceID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let snapshot = FlowReadySnapshot(
            sessionId: sessionID,
            ready: false,
            reason: .processing,
            heartbeatAt: 1_700_000_070.25,
            readyAt: 1_700_000_069.25,
            audioProofAt: 1_700_000_068.25,
            engineMode: "cloud",
            localeId: "en-US",
            busyUtteranceId: utteranceID,
            sessionExpiresAt: 1_700_000_130.25,
            hostGeneration: "generation-1"
        )
        let expected = #"{"audioProofAt":1700000068.25,"busyUtteranceId":"11111111-2222-3333-4444-555555555555","engineMode":"cloud","heartbeatAt":1700000070.25,"hostGeneration":"generation-1","localeId":"en-US","protocolVersion":1,"ready":false,"readyAt":1700000069.25,"reason":"processing","sessionExpiresAt":1700000130.25,"sessionId":"00112233-4455-6677-8899-AABBCCDDEEFF"}"#

        XCTAssertEqual(try sortedJSONString(snapshot), expected)
    }

    func testFlowStartTransactionSortedKeysGoldenJSON() throws {
        let sessionID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")
        )
        let utteranceID = try XCTUnwrap(
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )
        let transaction = FlowStartTransaction(
            sessionID: sessionID,
            utteranceID: utteranceID,
            deadlineAt: 1_700_000_100.25,
            phase: .recording,
            updatedAt: 1_700_000_090.5
        )
        let expected = #"{"deadlineAt":1700000100.25,"phase":"recording","sessionID":"00112233-4455-6677-8899-AABBCCDDEEFF","updatedAt":1700000090.5,"utteranceID":"11111111-2222-3333-4444-555555555555"}"#

        XCTAssertEqual(try sortedJSONString(transaction), expected)
    }

    func testFlowWireEnumRawValuesRemainStable() {
        XCTAssertEqual(
            [
                FlowCommand.Action.startRecording,
                .stopRecording,
                .abort,
                .prewarm,
                .primeAudio,
                .cancelPrimeAudio,
                .endAIConversation,
                .submitAIQuestion,
            ].map(\.rawValue),
            [
                "startRecording",
                "stopRecording",
                "abort",
                "prewarm",
                "primeAudio",
                "cancelPrimeAudio",
                "endAIConversation",
                "submitAIQuestion",
            ]
        )
        XCTAssertEqual(
            [
                FlowResult.Status.partial,
                .rawReady,
                .streaming,
                .final,
                .error,
                .aborted,
                .timeout,
            ].map(\.rawValue),
            ["partial", "rawReady", "streaming", "final", "error", "aborted", "timeout"]
        )
        XCTAssertEqual(
            [
                FlowAck.DeliveryOutcome.replaced,
                .appended,
                .rejected,
            ].map(\.rawValue),
            ["replaced", "appended", "rejected"]
        )
        XCTAssertEqual(
            [
                FlowStartTransaction.Phase.issued,
                .starting,
                .recording,
                .terminal,
            ].map(\.rawValue),
            ["issued", "starting", "recording", "terminal"]
        )
        XCTAssertEqual(
            [
                FlowReadySnapshot.Reason.ready,
                .noSession,
                .starting,
                .audioEngineNotLive,
                .waitingForAudioProof,
                .recording,
                .processing,
                .awaitingDelivery,
                .permissionMissing,
                .appGroupUnavailable,
                .hostLost,
                .error,
            ].map(\.rawValue),
            [
                "ready",
                "noSession",
                "starting",
                "audioEngineNotLive",
                "waitingForAudioProof",
                "recording",
                "processing",
                "awaitingDelivery",
                "permissionMissing",
                "appGroupUnavailable",
                "hostLost",
                "error",
            ]
        )
    }
}

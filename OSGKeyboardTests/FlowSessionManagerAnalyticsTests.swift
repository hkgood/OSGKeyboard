// FlowSessionManagerAnalyticsTests.swift
// OSGKeyboardTests
//
// Pure coverage for the feature mapping and utterance-bound operation registry
// used by FlowSessionManager's asynchronous ASR/assistant pipeline.

import Foundation
@testable import OSGKeyboard
import OSGKeyboardShared
import XCTest

@MainActor
final class FlowSessionManagerAnalyticsTests: XCTestCase {
    func testEveryFlowEntryMapsToOneStableFeature() {
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .aiQuestion),
            .aiAssistant
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .clipboardTransform),
            .agent
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .customSkill),
            .agent
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .agentPlanning),
            .agent
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .dictationPolish),
            .polish
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .translation),
            .polish
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.feature(for: .editLastInput),
            .polish
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.recordingFeature(for: .dictation),
            .transcription
        )
        XCTAssertEqual(
            FlowAnalyticsFeatureMapping.recordingFeature(for: .aiQuestion),
            .aiAssistant
        )
    }

    func testStreamingCancelledProducesOneCancelledTerminal() {
        let client = RecordingFlowAnalyticsClient()
        let registry = FlowAnalyticsOperationRegistry()
        let utteranceID = UUID()
        registry.start(
            utteranceID: utteranceID,
            feature: .transcription,
            executionMode: .managed,
            client: client
        )

        registry.cancel(utteranceID: utteranceID)

        XCTAssertEqual(
            client.events(),
            [
                .started(.transcription),
                .failed(.transcription, .cancelled)
            ]
        )
    }

    func testASRSucceedsButAssistantFailureDoesNotRecordTranscriptionSuccess() {
        let client = RecordingFlowAnalyticsClient()
        let registry = FlowAnalyticsOperationRegistry()
        let utteranceID = UUID()
        registry.start(
            utteranceID: utteranceID,
            feature: .aiAssistant,
            executionMode: .managed,
            client: client
        )

        // ASR completion is intentionally not a terminal value event.
        registry.fail(utteranceID: utteranceID, category: .network)

        XCTAssertEqual(
            client.events(),
            [
                .started(.aiAssistant),
                .failed(.aiAssistant, .network)
            ]
        )
    }

    func testOrdinaryDictationSuccessRecordsTranscription() {
        let client = RecordingFlowAnalyticsClient()
        let registry = FlowAnalyticsOperationRegistry()
        let utteranceID = UUID()
        registry.start(
            utteranceID: utteranceID,
            feature: FlowAnalyticsFeatureMapping.recordingFeature(for: .dictation),
            executionMode: .local,
            client: client
        )

        registry.succeed(utteranceID: utteranceID)

        XCTAssertEqual(
            client.events(),
            [
                .started(.transcription),
                .succeeded(.transcription)
            ]
        )
    }

    func testVoiceAssistantSuccessRecordsOneValueTask() {
        let client = RecordingFlowAnalyticsClient()
        let registry = FlowAnalyticsOperationRegistry()
        let utteranceID = UUID()
        registry.start(
            utteranceID: utteranceID,
            feature: FlowAnalyticsFeatureMapping.recordingFeature(for: .aiQuestion),
            executionMode: .byok,
            client: client
        )

        registry.operation(for: utteranceID)?.succeed()
        registry.discard(utteranceID: utteranceID)

        XCTAssertEqual(
            client.events(),
            [
                .started(.aiAssistant),
                .succeeded(.aiAssistant)
            ]
        )
    }

    func testRepeatedTerminalCallsStillRecordOnlyOnce() {
        let client = RecordingFlowAnalyticsClient()
        let registry = FlowAnalyticsOperationRegistry()
        let utteranceID = UUID()
        registry.start(
            utteranceID: utteranceID,
            feature: .aiAssistant,
            executionMode: .managed,
            client: client
        )

        registry.succeed(utteranceID: utteranceID)
        registry.fail(utteranceID: utteranceID, category: .provider)
        registry.cancel(utteranceID: utteranceID)

        XCTAssertEqual(
            client.events(),
            [
                .started(.aiAssistant),
                .succeeded(.aiAssistant)
            ]
        )
    }
}

private final class RecordingFlowAnalyticsClient:
    AnalyticsClient,
    @unchecked Sendable {
    enum Event: Equatable {
        case started(AnalyticsFeature)
        case succeeded(AnalyticsFeature)
        case failed(AnalyticsFeature, AnalyticsFailureCategory)
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    func events() -> [Event] {
        lock.withLock { recordedEvents }
    }

    func startAIFeature(
        _ feature: AnalyticsFeature,
        executionMode: AnalyticsExecutionMode
    ) -> any AnalyticsAIOperation {
        append(.started(feature))
        return RecordingFlowAnalyticsOperation(feature: feature) { [weak self] event in
            self?.append(event)
        }
    }

    func recordSessionActivity() {}
    func recordKeyboardActivated() {}
    func recordPurchaseViewed() {}
    func recordPurchaseStarted() {}
    func recordPurchaseCancelled() {}
    func recordReferralShared() {}

    func recordInviteOpened(
        acquisitionChannel: AnalyticsAcquisitionChannel,
        surface: AnalyticsSurface
    ) {}

    private func append(_ event: Event) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

private final class RecordingFlowAnalyticsOperation:
    AnalyticsAIOperation,
    @unchecked Sendable {
    private let feature: AnalyticsFeature
    private let onTerminal: @Sendable (RecordingFlowAnalyticsClient.Event) -> Void
    private let lock = NSLock()
    private var isFinished = false

    init(
        feature: AnalyticsFeature,
        onTerminal: @escaping @Sendable (
            RecordingFlowAnalyticsClient.Event
        ) -> Void
    ) {
        self.feature = feature
        self.onTerminal = onTerminal
    }

    func succeed() {
        finish(.succeeded(feature))
    }

    func fail(category: AnalyticsFailureCategory) {
        finish(.failed(feature, category))
    }

    func cancel() {
        fail(category: .cancelled)
    }

    private func finish(_ event: RecordingFlowAnalyticsClient.Event) {
        let shouldRecord = lock.withLock {
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        guard shouldRecord else { return }
        onTerminal(event)
    }
}

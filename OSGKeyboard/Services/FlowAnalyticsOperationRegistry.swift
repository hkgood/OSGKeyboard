// FlowAnalyticsOperationRegistry.swift
// OSGKeyboard · Main App
//
// Binds analytics operations to utterance identity so late async completions
// can never finish a newer user's task.

import OSGKeyboardShared

enum FlowAnalyticsFeatureMapping {
    static func feature(for taskKind: ManagedGatewayTaskKind) -> AnalyticsFeature {
        switch taskKind {
        case .aiQuestion, .currentInformationQuestion:
            return .aiAssistant
        case .clipboardTransform, .customSkill, .agentPlanning:
            return .agent
        case .dictationPolish, .translation, .editLastInput:
            return .polish
        }
    }

    static func recordingFeature(for mode: FlowUtteranceMode) -> AnalyticsFeature {
        mode == .aiQuestion ? .aiAssistant : .transcription
    }
}

@MainActor
final class FlowAnalyticsOperationRegistry {
    private var operations: [UUID: any AnalyticsAIOperation] = [:]

    @discardableResult
    func start(
        utteranceID: UUID,
        feature: AnalyticsFeature,
        executionMode: AnalyticsExecutionMode,
        client: any AnalyticsClient
    ) -> any AnalyticsAIOperation {
        operations.removeValue(forKey: utteranceID)?.cancel()
        let operation = client.startAIFeature(
            feature,
            executionMode: executionMode
        )
        operations[utteranceID] = operation
        return operation
    }

    func operation(for utteranceID: UUID?) -> (any AnalyticsAIOperation)? {
        guard let utteranceID else { return nil }
        return operations[utteranceID]
    }

    func succeed(utteranceID: UUID?) {
        take(utteranceID)?.succeed()
    }

    func fail(
        utteranceID: UUID?,
        category: AnalyticsFailureCategory
    ) {
        take(utteranceID)?.fail(category: category)
    }

    func cancel(utteranceID: UUID?) {
        take(utteranceID)?.cancel()
    }

    func cancelAll() {
        let active = Array(operations.values)
        operations.removeAll()
        active.forEach { $0.cancel() }
    }

    func discard(utteranceID: UUID?) {
        guard let utteranceID else { return }
        operations.removeValue(forKey: utteranceID)
    }

    private func take(
        _ utteranceID: UUID?
    ) -> (any AnalyticsAIOperation)? {
        guard let utteranceID else { return nil }
        return operations.removeValue(forKey: utteranceID)
    }
}

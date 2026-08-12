// FlowUtteranceRequest.swift
// OSGKeyboard · Shared
//
// One keyboard-side start contract for dictation and explicit editing.

import Foundation

public struct FlowUtteranceRequest: Equatable, Sendable {
    public let mode: FlowUtteranceMode
    public let editSourceText: String?
    public let sourceHistoryEntryID: UUID?
    public let sourceHistoryEntryRevision: Int64?
    public let aiConversationID: UUID?
    /// When set with `.aiQuestion`, host skips ASR and answers this text.
    public let aiQuestionText: String?

    public static let dictation = FlowUtteranceRequest(mode: .dictation)

    public init(
        mode: FlowUtteranceMode,
        editSourceText: String? = nil,
        sourceHistoryEntryID: UUID? = nil,
        sourceHistoryEntryRevision: Int64? = nil,
        aiConversationID: UUID? = nil,
        aiQuestionText: String? = nil
    ) {
        self.mode = mode
        self.editSourceText = editSourceText
        self.sourceHistoryEntryID = sourceHistoryEntryID
        self.sourceHistoryEntryRevision = sourceHistoryEntryRevision
        self.aiConversationID = aiConversationID
        self.aiQuestionText = aiQuestionText
    }

    public static func editLastInput(
        _ reference: EditableInputReference
    ) -> FlowUtteranceRequest {
        FlowUtteranceRequest(
            mode: .editLastInput,
            editSourceText: reference.displayText,
            sourceHistoryEntryID: reference.historyEntryID,
            sourceHistoryEntryRevision: reference.historyEntryRevision
        )
    }

    public var isEdit: Bool { mode == .editLastInput }
    public var isAIQuestion: Bool { mode == .aiQuestion }

    public static func aiQuestion(
        conversationID: UUID,
        prefilledQuestion: String? = nil
    ) -> FlowUtteranceRequest {
        FlowUtteranceRequest(
            mode: .aiQuestion,
            aiConversationID: conversationID,
            aiQuestionText: prefilledQuestion
        )
    }
}

public enum FlowUtteranceStartRejection: Equatable, Sendable {
    case pipelineBusy
    case onboardingIncomplete
    case missingAPIKey
    case noFullAccess
    case appGroupUnavailable
    case hostUnavailable
}

public enum FlowUtteranceStartDisposition: Equatable, Sendable {
    case issued(UUID)
    case waitingForHost(UUID)
    case alreadyInFlight(UUID)
    case rejected(FlowUtteranceStartRejection)

    public var utteranceID: UUID? {
        switch self {
        case .issued(let id), .waitingForHost(let id), .alreadyInFlight(let id):
            return id
        case .rejected:
            return nil
        }
    }
}

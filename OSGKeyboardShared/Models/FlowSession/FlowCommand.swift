// FlowCommand.swift
// OSGKeyboard · Shared

import Foundation

public struct FlowCommand: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case startRecording
        case stopRecording
        case abort
        /// Light warm-up: ASR locale/assets only — no mic capture.
        case prewarm
        /// User has touched the mic; prime capture before tap/hold resolves.
        case primeAudio
        /// Touch ended without an utterance adopting the primed capture.
        case cancelPrimeAudio
        /// Remove one temporary AI conversation from host memory.
        case endAIConversation
        /// AI mode: submit a prefilled question and skip ASR.
        case submitAIQuestion
    }

    /// Wire version that includes submitAIQuestion + aiQuestionText.
    public static let currentProtocolVersion = 5

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let action: Action
    public let localeId: String
    public let createdAt: TimeInterval
    public let fieldContext: FlowFieldContext?
    /// Dictation (default) vs explicit edit mode. Absent on legacy v1 → dictation.
    public let utteranceMode: FlowUtteranceMode?
    /// Verified source for explicit last-input editing.
    public let editSourceText: String?
    public let sourceHistoryEntryID: UUID?
    public let sourceHistoryEntryRevision: Int64?
    /// Host-memory conversation used only by `.aiQuestion`.
    public let aiConversationID: UUID?
    /// Prefilled question used only by `.submitAIQuestion`.
    public let aiQuestionText: String?
    /// Absolute wall-clock deadlines survive extension reconstruction.
    public let startDeadlineAt: TimeInterval?
    public let processingDeadlineAt: TimeInterval?

    public init(
        protocolVersion: Int = FlowCommand.currentProtocolVersion,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        action: Action,
        localeId: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        fieldContext: FlowFieldContext? = nil,
        utteranceMode: FlowUtteranceMode? = nil,
        editSourceText: String? = nil,
        sourceHistoryEntryID: UUID? = nil,
        sourceHistoryEntryRevision: Int64? = nil,
        aiConversationID: UUID? = nil,
        aiQuestionText: String? = nil,
        startDeadlineAt: TimeInterval? = nil,
        processingDeadlineAt: TimeInterval? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.action = action
        self.localeId = localeId
        self.createdAt = createdAt
        self.fieldContext = fieldContext
        self.utteranceMode = utteranceMode
        self.editSourceText = editSourceText
        self.sourceHistoryEntryID = sourceHistoryEntryID
        self.sourceHistoryEntryRevision = sourceHistoryEntryRevision
        self.aiConversationID = aiConversationID
        self.aiQuestionText = aiQuestionText
        self.startDeadlineAt = startDeadlineAt
        self.processingDeadlineAt = processingDeadlineAt
    }

    public var resolvedUtteranceMode: FlowUtteranceMode {
        utteranceMode ?? .dictation
    }
}

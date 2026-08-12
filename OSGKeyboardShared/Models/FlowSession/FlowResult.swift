// FlowResult.swift
// OSGKeyboard · Shared

import Foundation

public struct FlowResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case partial
        case rawReady
        /// AI-mode LLM answer draft (not ASR). Non-terminal.
        case streaming
        case final
        case error
        case aborted
        case timeout
    }

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let status: Status
    public let text: String?
    public let warning: String?
    public let errorKind: FlowSessionKeys.TranscriptionErrorKind?
    /// Raw ASR survives polish/network failure and host process churn.
    public let rawText: String?
    public let hostGeneration: String?
    /// Monotonically increases within one session/utterance; readers may discard
    /// an equal or lower non-nil revision as a stale or duplicate delivery.
    public let revision: Int64?
    public let fieldFingerprint: String?
    public let createdAt: TimeInterval
    /// Echo of the command mode so the extension can skip raw fallback.
    public let utteranceMode: FlowUtteranceMode?
    /// History row created by normal dictation, or edited by edit mode.
    public let historyEntryID: UUID?
    public let historyEntryRevision: Int64?
    /// Echoed for AI result validation; absent for dictation and edit.
    public let aiConversationID: UUID?

    public init(
        protocolVersion: Int = FlowCommand.currentProtocolVersion,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        status: Status,
        text: String? = nil,
        warning: String? = nil,
        errorKind: FlowSessionKeys.TranscriptionErrorKind? = nil,
        rawText: String? = nil,
        hostGeneration: String? = nil,
        revision: Int64? = nil,
        fieldFingerprint: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        utteranceMode: FlowUtteranceMode? = nil,
        historyEntryID: UUID? = nil,
        historyEntryRevision: Int64? = nil,
        aiConversationID: UUID? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.status = status
        self.text = text
        self.warning = warning
        self.errorKind = errorKind
        self.rawText = rawText
        self.hostGeneration = hostGeneration
        self.revision = revision
        self.fieldFingerprint = fieldFingerprint
        self.createdAt = createdAt
        self.utteranceMode = utteranceMode
        self.historyEntryID = historyEntryID
        self.historyEntryRevision = historyEntryRevision
        self.aiConversationID = aiConversationID
    }

    public var resolvedUtteranceMode: FlowUtteranceMode {
        utteranceMode ?? .dictation
    }

    /// Instruction deliveries must never insert raw ASR into the field.
    public var allowsRawFallback: Bool {
        resolvedUtteranceMode == .dictation
    }
}

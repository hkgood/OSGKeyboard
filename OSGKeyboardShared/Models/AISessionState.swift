// AISessionState.swift
// OSGKeyboard · Shared
//
// Keyboard-local state for one temporary AI conversation. Conversation
// messages live in the host process; the extension keeps only the latest
// answer needed for review and explicit insertion.

import Foundation

public struct AIAnswer: Equatable, Identifiable, Sendable {
    public enum DeliveryState: Equatable, Sendable {
        case ready
        case awaitingSend
        case inserted
        case sent
    }

    public let id: UUID
    public let text: String
    public let createdAt: Date
    public private(set) var deliveryState: DeliveryState

    public var isInserted: Bool {
        deliveryState != .ready
    }

    public var isSent: Bool {
        deliveryState == .sent
    }

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        isSent: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.deliveryState = isSent ? .sent : .ready
    }

    public mutating func markInserted(offersSend: Bool) {
        guard deliveryState == .ready else { return }
        deliveryState = offersSend ? .awaitingSend : .inserted
    }

    public mutating func markSent() {
        guard deliveryState == .awaitingSend else { return }
        deliveryState = .sent
    }
}

public struct AISessionState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case inactive
        case idle
        case preparing
        case listening
        case recognizing
        case generating
        case ready
        case awaitingSend
        case inserted
        case sent
        case failed
    }

    public private(set) var phase: Phase
    public private(set) var conversationID: UUID?
    public private(set) var activeUtteranceID: UUID?
    public private(set) var answer: AIAnswer?
    /// Live LLM draft while `phase == .generating`. Cleared on final/cancel.
    public private(set) var draftAnswerText: String?
    public private(set) var transcript: String
    public private(set) var errorMessage: String?

    public static let inactive = AISessionState()

    public init(
        phase: Phase = .inactive,
        conversationID: UUID? = nil,
        activeUtteranceID: UUID? = nil,
        answer: AIAnswer? = nil,
        draftAnswerText: String? = nil,
        transcript: String = "",
        errorMessage: String? = nil
    ) {
        self.phase = phase
        self.conversationID = conversationID
        self.activeUtteranceID = activeUtteranceID
        self.answer = answer
        self.draftAnswerText = draftAnswerText
        self.transcript = transcript
        self.errorMessage = errorMessage
    }

    public var isActive: Bool { phase != .inactive }

    public var isBusy: Bool {
        switch phase {
        case .preparing, .listening, .recognizing, .generating:
            return true
        case .inactive, .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
            return false
        }
    }

    public var canInsert: Bool {
        phase == .ready && answer?.deliveryState == .ready
    }

    public var canSend: Bool {
        phase == .awaitingSend && answer?.deliveryState == .awaitingSend
    }

    public var canPerformAnswerAction: Bool {
        canInsert || canSend
    }

    public mutating func enter(conversationID: UUID = UUID()) {
        self = AISessionState(phase: .idle, conversationID: conversationID)
    }

    public mutating func leave() {
        self = .inactive
    }

    public mutating func beginPreparing(utteranceID: UUID) {
        guard isActive, !isBusy else { return }
        phase = .preparing
        activeUtteranceID = utteranceID
        transcript = ""
        errorMessage = nil
    }

    public mutating func beginListening(utteranceID: UUID) {
        guard isActive, activeUtteranceID == utteranceID else { return }
        phase = .listening
        errorMessage = nil
    }

    public mutating func updateTranscript(_ value: String, utteranceID: UUID) {
        guard isActive, activeUtteranceID == utteranceID else { return }
        transcript = value
    }

    public mutating func beginRecognizing(utteranceID: UUID) {
        guard isActive, activeUtteranceID == utteranceID else { return }
        phase = .recognizing
    }

    public mutating func beginGenerating(question: String, utteranceID: UUID) {
        guard isActive, activeUtteranceID == utteranceID else { return }
        transcript = question
        draftAnswerText = nil
        phase = .generating
    }

    /// Incremental AI answer draft. Keeps `phase == .generating` and does not
    /// replace the previous committed `answer` until `receiveAnswer`.
    public mutating func receivePartialAnswer(_ text: String, utteranceID: UUID) {
        guard isActive, activeUtteranceID == utteranceID else { return }
        if phase == .recognizing || phase == .preparing {
            phase = .generating
        }
        guard phase == .generating else { return }
        draftAnswerText = text
        errorMessage = nil
    }

    public mutating func receiveAnswer(_ text: String, utteranceID: UUID) {
        guard isActive, activeUtteranceID == utteranceID else { return }
        answer = AIAnswer(text: text)
        draftAnswerText = nil
        phase = .ready
        activeUtteranceID = nil
        errorMessage = nil
    }

    public mutating func markAnswerInserted(offersSend: Bool) {
        guard canInsert else { return }
        answer?.markInserted(offersSend: offersSend)
        phase = offersSend ? .awaitingSend : .inserted
    }

    public mutating func markAnswerSent() {
        guard canSend else { return }
        answer?.markSent()
        phase = .sent
    }

    /// Drops a result retained because the insertion target changed.
    /// The conversation remains active so the user can immediately ask again.
    public mutating func discardReadyAnswer() {
        guard phase == .ready else { return }
        answer = nil
        activeUtteranceID = nil
        draftAnswerText = nil
        transcript = ""
        errorMessage = nil
        phase = .idle
    }

    public mutating func cancelCurrentWork() {
        guard isBusy else { return }
        activeUtteranceID = nil
        transcript = ""
        draftAnswerText = nil
        errorMessage = nil
        phase = restingPhase
    }

    public mutating func fail(_ message: String, utteranceID: UUID?) {
        guard isActive else { return }
        if let utteranceID, activeUtteranceID != utteranceID { return }
        activeUtteranceID = nil
        draftAnswerText = nil
        errorMessage = message
        phase = .failed
    }

    public mutating func resetConversationPreservingAnswer(
        conversationID: UUID = UUID()
    ) {
        guard isActive else { return }
        self.conversationID = conversationID
        activeUtteranceID = nil
        transcript = ""
        draftAnswerText = nil
        errorMessage = nil
        phase = restingPhase
    }

    private var restingPhase: Phase {
        guard let answer else { return .idle }
        switch answer.deliveryState {
        case .ready:
            return .ready
        case .awaitingSend:
            return .awaitingSend
        case .inserted:
            return .inserted
        case .sent:
            return .sent
        }
    }
}

public enum AIQuestionLimits {
    public static let retainedConversationRounds = 6
    /// Safety ceiling only — user-facing length is guided by prompt, not this cap.
    public static let maximumAnswerCharacterCount = 4_500
}

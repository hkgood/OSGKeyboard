// FlowStartTransactionPolicy.swift
// OSGKeyboard · Shared
//
// Pure gate for exactly-once side effects over at-least-once Flow commands.

import Foundation

public enum FlowHostUtteranceState: Equatable, Sendable {
    case idle
    case starting(UUID)
    case recording(UUID)
    case processing(UUID)
}

public enum FlowStartDecision: Equatable, Sendable {
    case accept
    case idempotent
    case rejectBusy
    case rejectExpired
}

public enum FlowStartTransactionPolicy {
    public static func decide(
        incomingUtteranceID: UUID,
        deadlineAt: TimeInterval?,
        now: TimeInterval = Date().timeIntervalSince1970,
        hostState: FlowHostUtteranceState
    ) -> FlowStartDecision {
        if let deadlineAt, now >= deadlineAt {
            return .rejectExpired
        }
        switch hostState {
        case .idle:
            return .accept
        case .starting(let id), .recording(let id), .processing(let id):
            return id == incomingUtteranceID ? .idempotent : .rejectBusy
        }
    }
}

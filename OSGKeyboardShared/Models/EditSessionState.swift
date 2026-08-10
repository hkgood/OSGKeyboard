// EditSessionState.swift
// OSGKeyboard · Shared
//
// Closed state machine for long-press editing. Associated values make invalid
// combinations (for example "reviewing with no result") unrepresentable.

import Foundation

public struct EditSessionSource: Equatable, Sendable {
    public let reference: EditableInputReference
    public let generation: UUID

    public init(reference: EditableInputReference, generation: UUID = UUID()) {
        self.reference = reference
        self.generation = generation
    }
}

public struct EditReview: Equatable, Sendable {
    public let source: EditSessionSource
    public let resultText: String
    public let utteranceID: UUID

    public init(source: EditSessionSource, resultText: String, utteranceID: UUID) {
        self.source = source
        self.resultText = resultText
        self.utteranceID = utteranceID
    }
}

public enum EditSessionState: Equatable, Sendable {
    case inactive
    case preparing(EditSessionSource)
    case listening(EditSessionSource)
    case processing(EditSessionSource)
    case review(EditReview)
    case applying(EditReview)
    case appending(EditReview)
    case failed(EditSessionSource, message: String)

    public var isActive: Bool {
        if case .inactive = self { return false }
        return true
    }

    public var source: EditSessionSource? {
        switch self {
        case .inactive:
            return nil
        case .preparing(let source),
             .listening(let source),
             .processing(let source),
             .failed(let source, _):
            return source
        case .review(let review),
             .applying(let review),
             .appending(let review):
            return review.source
        }
    }

    public var review: EditReview? {
        switch self {
        case .review(let review), .applying(let review), .appending(let review):
            return review
        default:
            return nil
        }
    }
}

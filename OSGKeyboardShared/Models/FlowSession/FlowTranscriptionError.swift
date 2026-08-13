// FlowTranscriptionError.swift
// OSGKeyboard · Shared

import Foundation

public struct FlowTranscriptionError: Equatable, Sendable {
    public let message: String
    public let kind: FlowSessionKeys.TranscriptionErrorKind

    public init(message: String, kind: FlowSessionKeys.TranscriptionErrorKind) {
        self.message = message
        self.kind = kind
    }
}

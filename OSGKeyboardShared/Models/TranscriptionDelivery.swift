// TranscriptionDelivery.swift
// OSGKeyboard · Shared
//
// Host-app → keyboard handoff payload: final text plus an optional soft
// warning when cloud polish failed but the raw transcript is still delivered.

import Foundation

public struct TranscriptionDelivery: Sendable, Equatable {
    public let text: String
    public let polishWarning: String?

    public init(text: String, polishWarning: String? = nil) {
        self.text = text
        self.polishWarning = polishWarning
    }
}

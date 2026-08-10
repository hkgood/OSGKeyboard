// FlowUtteranceMode.swift
// OSGKeyboard · Shared
//
// Distinguishes dictation polish from explicit last-input editing on the
// Flow command / result wire.

import Foundation

public enum FlowUtteranceMode: String, Codable, Equatable, Sendable {
    /// ASR is draft text to polish and insert (default / legacy).
    case dictation
    /// ASR is an explicit instruction over the last verified OSG insertion.
    case editLastInput
    /// Decoded only from retired or unknown wire modes. Production code must
    /// reject this value and must never treat it as dictation.
    case unsupportedLegacy

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case Self.dictation.rawValue:
            self = .dictation
        case Self.editLastInput.rawValue:
            self = .editLastInput
        case "clipboardCommand", Self.unsupportedLegacy.rawValue:
            self = .unsupportedLegacy
        default:
            self = .unsupportedLegacy
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// AIResponseLength.swift
// OSGKeyboard · Shared
//
// Soft response-length preference for AI keyboard mode. Guidance is
// applied through the system prompt — not a hard character gate.

import Foundation

public enum AIResponseLength: String, Codable, CaseIterable, Sendable {
    case short
    case medium
    case detailed

    public static let `default`: AIResponseLength = .medium

    public var labelKey: String {
        switch self {
        case .short: return "ai.responseLength.short"
        case .medium: return "ai.responseLength.medium"
        case .detailed: return "ai.responseLength.detailed"
        }
    }

    /// Soft length guidance injected into the AI-mode system prompt.
    public var promptGuidance: String {
        switch self {
        case .short:
            return "Keep the answer brief: about 2–3 sentences."
        case .medium:
            return "Keep the answer moderately long: roughly within 500 characters."
        case .detailed:
            return "You may answer in more detail: roughly within 3000 characters."
        }
    }

    public static func resolve(storedRawValue rawValue: String?) -> AIResponseLength {
        switch rawValue {
        case AIResponseLength.short.rawValue:
            return .short
        case AIResponseLength.detailed.rawValue:
            return .detailed
        case AIResponseLength.medium.rawValue:
            return .medium
        default:
            return .default
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.resolve(storedRawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

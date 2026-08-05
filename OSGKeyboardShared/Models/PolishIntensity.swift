// PolishIntensity.swift
// OSGKeyboard · Shared
//
// Selects the safety envelope used by built-in fun polish styles.

import Foundation

public enum PolishIntensity: String, Codable, CaseIterable, Sendable {
    /// Full fidelity, question, and insertion-context safeguards.
    case light

    /// Formatting-only shared core followed by the selected fun personality.
    case heavy

    public static let `default`: PolishIntensity = .light

    public var labelKey: String {
        switch self {
        case .light: return "polish.intensity.light"
        case .heavy: return "polish.intensity.heavy"
        }
    }

    public var descriptionKey: String {
        switch self {
        case .light: return "polish.intensity.light.desc"
        case .heavy: return "polish.intensity.heavy.desc"
        }
    }

    public static func resolve(storedRawValue rawValue: String?) -> PolishIntensity {
        switch rawValue {
        case PolishIntensity.heavy.rawValue:
            return .heavy
        case PolishIntensity.light.rawValue:
            return .light
        default:
            // Retired `off` / `medium` values and malformed data use the new
            // conservative product default.
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

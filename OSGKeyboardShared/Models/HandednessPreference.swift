// HandednessPreference.swift
// OSGKeyboard · Shared
//
// Which hand the user holds the phone with — controls bottom-row key order
// on the keyboard (delete ↔ space swap for right-handed use).

import Foundation

public enum HandednessPreference: String, CaseIterable, Identifiable, Sendable, Codable {
    case left
    case right

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .left:  return "settings.handedness.left"
        case .right: return "settings.handedness.right"
        }
    }

    /// Right-handed preference places space on the left and delete on the right.
    public var swapsActionKeys: Bool { self == .right }

    public static func fromStored(_ raw: String?) -> HandednessPreference {
        guard let raw, let value = HandednessPreference(rawValue: raw) else { return .left }
        return value
    }
}

// KeyboardHapticIntensity.swift
// OSGKeyboard · Shared
//
// Typing-key haptic strength: Off / Light (default, system-like) / Strong
// (more mechanical). Persisted in App Group so the keyboard extension
// mirrors the host Settings → General picker.

import Foundation

public enum KeyboardHapticIntensity: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case light
    case strong

    public var id: String { rawValue }

    public static let `default`: KeyboardHapticIntensity = .light

    public var labelKey: String {
        switch self {
        case .off:    return "settings.keyboardHaptic.off"
        case .light:  return "settings.keyboardHaptic.light"
        case .strong: return "settings.keyboardHaptic.strong"
        }
    }

    public static func fromStored(_ raw: String?) -> KeyboardHapticIntensity {
        guard let raw, let value = KeyboardHapticIntensity(rawValue: raw) else {
            return .default
        }
        return value
    }
}

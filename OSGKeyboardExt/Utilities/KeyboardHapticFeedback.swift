// KeyboardHapticFeedback.swift
// OSGKeyboard · Keyboard Extension
//
// Role-based typing haptics (no screen-position mapping). Intensity comes
// from Settings → General → Haptics (off / light / strong).

import UIKit
import OSGKeyboardShared

/// Key roles drive distinct Taptic styles — closer to a real keyboard than
/// a single buzz for every tap.
enum KeyboardHapticKeyRole {
    /// Letters, digits, punctuation.
    case character
    /// Shift, 123 / ABC / #+=.
    case modifier
    /// Space, return / send.
    case action
    /// Delete (including hold-to-repeat ticks).
    case delete
}

@MainActor
enum KeyboardHapticFeedback {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)

    /// Warm the generators so the first keypress is not soft/late.
    static func prepare() {
        soft.prepare()
        light.prepare()
        medium.prepare()
        heavy.prepare()
        rigid.prepare()
    }

    static func play(role: KeyboardHapticKeyRole, intensity: KeyboardHapticIntensity) {
        guard intensity != .off else { return }

        switch intensity {
        case .off:
            return
        case .light:
            playLight(role: role)
        case .strong:
            playStrong(role: role)
        }
    }

    // Soft / light — near stock keyboard feedback.
    private static func playLight(role: KeyboardHapticKeyRole) {
        switch role {
        case .character:
            soft.impactOccurred(intensity: 0.55)
            soft.prepare()
        case .modifier:
            light.impactOccurred(intensity: 0.65)
            light.prepare()
        case .action:
            light.impactOccurred(intensity: 0.8)
            light.prepare()
        case .delete:
            medium.impactOccurred(intensity: 0.45)
            medium.prepare()
        }
    }

    // Heavier / sharper — more mechanical-keyboard feel.
    private static func playStrong(role: KeyboardHapticKeyRole) {
        switch role {
        case .character:
            medium.impactOccurred(intensity: 0.75)
            medium.prepare()
        case .modifier:
            medium.impactOccurred(intensity: 0.95)
            medium.prepare()
        case .action:
            heavy.impactOccurred(intensity: 0.9)
            heavy.prepare()
        case .delete:
            rigid.impactOccurred(intensity: 1.0)
            rigid.prepare()
        }
    }
}

/// Sound + haptic for a typing-grid key press (pressed-down timing).
@MainActor
enum TypingKeyFeedback {
    static func play(
        role: KeyboardHapticKeyRole,
        intensity: KeyboardHapticIntensity,
        isDelete: Bool = false
    ) {
        if isDelete {
            KeyboardSoundFeedback.deleteClick()
        } else {
            KeyboardSoundFeedback.keyClick()
        }
        KeyboardHapticFeedback.play(role: role, intensity: intensity)
    }
}

// ClipboardCommandEligibility.swift
// OSGKeyboard · Shared
//
// User-visible failure reasons when long-press clipboard command cannot start.
// (30s eligibility window and continuous-rewrite sessions were removed.)

import Foundation

/// Why a clipboard-command long-press did not start recording.
public enum ClipboardCommandFailure: Equatable, Sendable {
    case pasteDenied
    case secureField
    case noFullAccess
    /// Host never confirmed capture (double-start / mic not ready / timeout).
    case prepareFailed
    case material(ClipboardMaterialFilter.Rejection)

    /// Localization key under the keyboard extension `Keyboard.strings` table.
    public var localizationKey: String {
        switch self {
        case .pasteDenied:
            return "keyboard.clipboard.reject.pasteDenied"
        case .secureField:
            return "keyboard.clipboard.reject.secureField"
        case .noFullAccess:
            return "keyboard.clipboard.reject.noFullAccess"
        case .prepareFailed:
            return "keyboard.clipboard.reject.prepareFailed"
        case .material(let rejection):
            switch rejection {
            case .empty:
                return "keyboard.clipboard.reject.empty"
            case .phoneOrNumeric:
                return "keyboard.clipboard.reject.phoneOrNumeric"
            case .emojiOrSymbolOnly:
                return "keyboard.clipboard.reject.emojiOrSymbolOnly"
            case .verificationCode:
                return "keyboard.clipboard.reject.verificationCode"
            case .tooShort:
                return "keyboard.clipboard.reject.tooShort"
            case .repetitiveSpam:
                return "keyboard.clipboard.reject.repetitiveSpam"
            }
        }
    }
}

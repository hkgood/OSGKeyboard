// RecordButtonGesturePolicy.swift
// OSGKeyboard · Shared
//
// Pure tap / hold routing for the mic button. Kept out of the view so the
// "one press produces at most one action" invariant is unit-testable: the
// edit long-press flips the phase while the finger is still down, and
// regressions there let a single press both open and close a round.

import Foundation

public enum RecordButtonGestureAction: Equatable, Sendable {
    case none
    /// Start dictation, cancel a preparing edit, or stop recording —
    /// all of which the coordinator resolves from its own phase.
    case toggle
    case beginEditLastInput
}

public enum RecordButtonGesturePolicy {
    /// Action for a press released before the hold threshold.
    public static func tapAction(
        phase: RecordButton.Phase,
        isEnabled: Bool
    ) -> RecordButtonGestureAction {
        switch phase {
        case .idleUnavailable:
            return .toggle
        case .idleReady, .error, .preparing, .recording:
            return isEnabled ? .toggle : .none
        case .processing:
            return .none
        }
    }

    /// Action for a press held past the threshold. A `.none` result means the
    /// hold did not consume the press, so its release still counts as a tap and
    /// no gesture becomes a dead key.
    public static func holdAction(
        phase: RecordButton.Phase,
        isEnabled: Bool,
        supportsEditLongPress: Bool
    ) -> RecordButtonGestureAction {
        switch phase {
        case .idleReady, .idleUnavailable, .error:
            guard supportsEditLongPress else { return .none }
            guard isEnabled || phase == .idleUnavailable else { return .none }
            return .beginEditLastInput
        case .recording:
            return isEnabled ? .toggle : .none
        case .preparing, .processing:
            return .none
        }
    }

    /// A hold that produced an action owns the press; its release must be
    /// swallowed rather than replayed as a tap.
    public static func consumesPress(_ action: RecordButtonGestureAction) -> Bool {
        action != .none
    }
}

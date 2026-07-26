// KeyboardFlowResultMatcher.swift
// OSGKeyboard · Shared
//
// Pure matching rules for keyboard-side Flow result consumption.

import Foundation

public enum KeyboardFlowResultMatcher {
    /// Returns the latest result when it belongs to the active session + utterance.
    public static func matchingResult(
        latest: FlowResult?,
        activeSessionId: UUID?,
        currentUtteranceId: UUID?
    ) -> FlowResult? {
        guard let result = latest else { return nil }
        guard let activeSessionId, let currentUtteranceId else { return nil }
        guard result.sessionId == activeSessionId,
              result.utteranceId == currentUtteranceId else {
            return nil
        }
        return result
    }

    public static func isTerminalFailure(_ result: FlowResult) -> Bool {
        result.status == .error || result.status == .timeout || result.status == .aborted
    }

    public static func isConsumableFinal(_ result: FlowResult) -> Bool {
        result.status == .final && !(result.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

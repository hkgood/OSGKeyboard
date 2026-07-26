// FlowResultDelivery.swift
// OSGKeyboard · Shared
//
// Typed helpers for writing Flow utterance results to App Group storage.

import Foundation

public enum FlowResultDelivery {
    public static func writePartial(
        text: String,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        defaults: UserDefaults? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: .partial,
                text: trimmed
            ),
            defaults: defaults
        )
    }

    public static func writeFinal(
        text: String,
        warning: String? = nil,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        defaults: UserDefaults? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: .final,
                text: trimmed,
                warning: warning
            ),
            defaults: defaults
        )
    }

    public static func writeError(
        message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .generic,
        status: FlowResult.Status = .error,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        defaults: UserDefaults? = nil
    ) {
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: status,
                text: message,
                errorKind: kind
            ),
            defaults: defaults
        )
    }
}

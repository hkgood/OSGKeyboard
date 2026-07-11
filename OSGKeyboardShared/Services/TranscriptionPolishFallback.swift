// TranscriptionPolishFallback.swift
// OSGKeyboard · Shared
//
// Shared polish-failure handling: conservative raw ASR cleanup plus
// bilingual user-visible warnings (iOS Flow + macOS dictation).

import Foundation

public enum TranscriptionPolishFallback: Sendable {

    public static func makeDelivery(
        rawText: String,
        error: Error,
        engineMode: String,
        chunkWarning: String?
    ) -> TranscriptionDelivery {
        let fallbackText = TranscriptPostProcessor.cleanRawASRFallback(rawText)
        let warning = warning(for: error, engineMode: engineMode)
            ?? degradedWarning()
            ?? chunkWarning
        return TranscriptionDelivery(text: fallbackText, polishWarning: warning)
    }

    public static func warning(for error: Error, engineMode: String) -> String? {
        if let polishError = error as? PolishingService.PolishError {
            switch polishError {
            case .missingAPIKey:
                if engineMode == "local" {
                    return SharedL10n.string("flow.warning.localPolishUnavailable")
                }
                return SharedL10n.string("flow.warning.cloudPolishMissingKey")
            case .timeout, .keychainLocked:
                return degradedWarning()
            case .noTranscript:
                return nil
            }
        }
        if error is LLMError {
            return degradedWarning()
        }
        return nil
    }

    public static func degradedWarning() -> String? {
        SharedL10n.string("flow.warning.polishDegraded")
    }
}

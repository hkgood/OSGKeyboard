// FlowTranscriptFinalizer.swift
// OSGKeyboard · Main App
//
// ASR drain wait + polish orchestration helpers extracted from FlowSessionManager.

import Foundation
import OSGKeyboardShared

enum FlowTranscriptFinalizer {
    /// Host-side ASR wait budget for the active engine mode.
    static func asrWaitTimeout(engineMode: String) -> TimeInterval {
        engineMode == "local"
            ? FlowSessionKeys.localASRWaitTimeout
            : FlowSessionKeys.cloudASRWaitTimeout
    }

    /// Publish raw ASR text as a partial so the keyboard can show progress while polish runs.
    static func publishRawPreviewBeforePolish(
        text: String,
        sessionId: UUID?,
        utteranceId: UUID?,
        commandSeq: Int64
    ) {
        guard let sessionId, let utteranceId else { return }
        FlowResultDelivery.writePartial(
            text: text,
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: commandSeq
        )
    }

    /// Host-level polish cap — does not wait for a cancelled LLM task to unwind.
    static func polishWithHostTimeout(
        polisher: PolishingService,
        text: String,
        mode: PolishingService.PolishMode,
        providerIdOverride: String?
    ) async throws -> String {
        try await HardTimeout.run(seconds: FlowSessionKeys.maxPolishTimeout) {
            try await polisher.polish(
                text,
                mode: mode,
                providerIdOverride: providerIdOverride
            )
        }
    }

    static func polishModeLogLabel(_ mode: PolishingService.PolishMode) -> String {
        switch mode {
        case .polish:
            return "polish"
        case .translate(let targetLocaleId):
            return "translate(\(targetLocaleId))"
        }
    }

    static func chunkWarningMessage(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.joined(separator: "\n")
    }
}

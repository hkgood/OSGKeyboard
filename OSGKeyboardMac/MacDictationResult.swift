// MacDictationResult.swift
// OSGKeyboard · Mac

import Foundation

struct MacDictationResult: Sendable, Equatable {
    let text: String
    /// Corrected ASR transcript before LLM polishing; never shown in History.
    let prePolishText: String
    /// Exact style metadata returned by the successful polish request.
    let polishStyleID: String?
    let polishStylePrompt: String?
    /// Shown when DeepSeek / cloud polish failed but raw ASR was delivered.
    let polishWarning: String?
    /// Non-fatal per-chunk ASR issues from long utterance chunking.
    let chunkWarning: String?
}

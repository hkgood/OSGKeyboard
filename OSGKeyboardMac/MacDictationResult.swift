// MacDictationResult.swift
// OSGKeyboard · Mac

import Foundation

struct MacDictationResult: Sendable, Equatable {
    let text: String
    /// Shown when DeepSeek / cloud polish failed but raw ASR was delivered.
    let polishWarning: String?
    /// Non-fatal per-chunk ASR issues from long utterance chunking.
    let chunkWarning: String?
}

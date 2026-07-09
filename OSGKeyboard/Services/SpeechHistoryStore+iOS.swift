// SpeechHistoryStore+iOS.swift
// OSGKeyboard · Main App
//
// iOS-only helper that records history and home-screen usage stats together.

import Foundation
import OSGKeyboardShared

extension SpeechHistoryStore {
    /// Append history and update cumulative home-screen usage stats.
    func recordUtterance(
        text: String,
        engineMode: String,
        duration: TimeInterval,
        wasTranslation: Bool
    ) {
        append(text: text, engineMode: engineMode)
        UsageStatisticsStore.shared.recordUtterance(
            text: text,
            duration: duration,
            wasTranslation: wasTranslation
        )
    }
}

// FlowUtteranceMode.swift
// OSGKeyboard · Shared
//
// Distinguishes dictation polish from clipboard-command generation on the
// Flow command / result wire (plan §11).

import Foundation

public enum FlowUtteranceMode: String, Codable, Equatable, Sendable {
    /// ASR is draft text to polish and insert (default / legacy).
    case dictation
    /// ASR is an instruction over a frozen clipboard snapshot.
    case clipboardCommand
}

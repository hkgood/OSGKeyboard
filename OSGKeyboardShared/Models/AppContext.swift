// AppContext.swift
// OSGKeyboard · Shared
//
// Coarse classification of "where is the user typing right now?".
// We use it to pick a tone / style guideline for the LLM polish
// step (e.g. code stays technical, chat stays casual).
//
// The detection is best-effort and runs entirely in the keyboard
// extension — iOS sandboxing blocks us from reading the foreground
// app's bundle ID, so we infer from text-content heuristics plus
// a 30-minute cache and a few environmental signals. See
// `AppContextDetector` for the actual algorithm.

import Foundation

public enum AppContext: String, Codable, Sendable, CaseIterable {
    /// IDE / code editor / terminal.
    case code
    /// Mail composer (long form, formal-ish).
    case email
    /// IM / chat (short lines, casual).
    case chat
    /// Notes / long-form document.
    case document
    /// Anything we cannot classify confidently.
    case unknown

    /// User-facing label for the Settings view's preview banner.
    public var labelKey: String {
        switch self {
        case .code: return "appContext.code"
        case .email: return "appContext.email"
        case .chat: return "appContext.chat"
        case .document: return "appContext.document"
        case .unknown: return "appContext.unknown"
        }
    }

    /// Tone / style constraint appended to the LLM prompt. Kept
    /// intentionally short — the LLM does better with 1-2 sharp
    /// instructions than a wall of rules.
    public var polishGuideline: String {
        switch self {
        case .code:
            return "Code context: preserve English identifiers, variable names, file paths, and indentation-relevant whitespace exactly. Do not natural-language them. Keep code snippets unformatted; do not wrap in code fences."
        case .email:
            return "Email context: you may add a polite greeting or sign-off if the user clearly forgot one. Reasonable paragraph breaks. Keep tone professional but not stiff."
        case .chat:
            return "Chat context: keep it short, conversational, and emoji-friendly. Drop formalities. Preserve the speaker's casual voice."
        case .document:
            return "Document context: add structure — split into paragraphs, use lists when the user enumerates. Keep tone written-formal. Do not invent headings the user did not say."
        case .unknown:
            return "Unknown context: pick a neutral, friendly tone. Err on the side of minimal changes."
        }
    }
}

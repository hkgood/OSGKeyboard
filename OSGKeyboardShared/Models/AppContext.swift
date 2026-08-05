// AppContext.swift
// OSGKeyboard · Shared
//
// Coarse classification of "where is the user typing right now?".
// We use it to provide concise environment hints to polish and translation.
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

    /// Translation uses an English context hint; polish has an equivalent
    /// localized hint in PolishPromptComposer.
    public var translationGuideline: String {
        switch self {
        case .code:
            return "Code context: preserve English identifiers, variable names, file paths, and indentation-relevant whitespace exactly. Do not natural-language them. Keep code snippets unformatted; do not wrap in code fences."
        case .email:
            return "Email context: preserve existing paragraph breaks and lists; if the transcript is a flat blob with multiple points, reconstruct clear paragraphs. Keep the tone professional but not stiff. Preserve greetings and sign-offs only when present; never invent them."
        case .chat:
            return "Chat context: keep it short, conversational, and natural. Drop formalities. Preserve the speaker's casual voice. Still honor the structure contract for multi-point messages; do not add decorative paragraphs to a single short line. Do not add emojis."
        case .document:
            return "Document context: preserve existing paragraphs and lists; if the transcript lacks breaks, split into paragraphs and use lists when the user enumerates. Keep tone written-formal. Do not invent headings the user did not say."
        case .unknown:
            return "Unknown context: pick a neutral, friendly tone. Prefer minimal wording changes, but still preserve or reconstruct paragraphs and lists per the structure contract."
        }
    }
}

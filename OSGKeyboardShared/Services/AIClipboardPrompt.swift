// AIClipboardPrompt.swift
// OSGKeyboard · Shared
//
// The single place where clipboard text enters an AI prompt. The instruction
// and the clipboard body travel as separate blocks so the body stays untrusted
// data, and every caller must fail closed when no material is available.

import Foundation

public enum AIClipboardPrompt: Sendable {
    /// Legacy / remote hint packs may still inline this token in `prompt`.
    public static let materialPlaceholder = "{clipboard}"

    public enum Resolution: Equatable, Sendable {
        case ready(String)
        /// The request needs clipboard text and none can be used.
        case materialUnavailable
    }

    /// Instruction + clipboard body in the shared untrusted-data schema.
    public static func compose(instruction: String, material: String) -> String {
        """
        <clipboard_request protocol="clipboard-ai-v1">
          <instruction>
        \(PromptXMLEscaping.escapeTextContent(trimmed(instruction)))
          </instruction>
          <clipboard_text>
        \(PromptXMLEscaping.escapeTextContent(trimmed(material)))
          </clipboard_text>
        </clipboard_request>
        """
    }

    /// Resolves a clipboard-dependent instruction. Empty material fails closed
    /// instead of asking the model to answer without the text it needs.
    public static func resolve(instruction: String, material: String?) -> Resolution {
        let body = trimmed(material ?? "")
        guard !body.isEmpty else { return .materialUnavailable }
        return .ready(
            compose(instruction: strippingPlaceholder(instruction), material: body)
        )
    }

    /// Spoken AI questions carry clipboard text only when the user asked for
    /// it; every other question is passed through untouched.
    public static func resolveSpoken(question: String, material: String?) -> Resolution {
        guard mentionsClipboard(question) else { return .ready(question) }
        return resolve(instruction: question, material: material)
    }

    /// True when `text` is the clipboard-AI XML envelope, not user-visible copy.
    public static func isInternalPrompt(_ text: String) -> Bool {
        text.contains("<clipboard_request") || text.contains("clipboard-ai-v1")
    }

    /// Instruction text with any inline material placeholder removed.
    static func strippingPlaceholder(_ prompt: String) -> String {
        trimmed(prompt.replacingOccurrences(of: materialPlaceholder, with: ""))
    }

    /// Naming the clipboard is the authorization: the user chose the material.
    static func mentionsClipboard(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { lowered.contains($0) }
    }

    private static let keywords = [
        "剪贴板", "剪切板", "剪贴版", "粘贴板", "clipboard"
    ]

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

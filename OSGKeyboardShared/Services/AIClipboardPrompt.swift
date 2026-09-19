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

    /// Instruction + clipboard body in the shared untrusted-data schema. When
    /// `conversationContext` is present it is emitted as its own untrusted block
    /// before the clipboard body: it is earlier back-and-forth in the same chat
    /// (also not authored by the app), so it must not join the trusted
    /// `<instruction>`.
    public static func compose(
        instruction: String,
        material: String,
        conversationContext: String? = nil
    ) -> String {
        let context = trimmed(conversationContext ?? "")
        let contextBlock = context.isEmpty ? "" : """

          <conversation_context>
        \(PromptXMLEscaping.escapeTextContent(context))
          </conversation_context>
        """
        return """
        <clipboard_request protocol="clipboard-ai-v1">
          <instruction>
        \(PromptXMLEscaping.escapeTextContent(trimmed(instruction)))
          </instruction>\(contextBlock)
          <clipboard_text>
        \(PromptXMLEscaping.escapeTextContent(trimmed(material)))
          </clipboard_text>
        </clipboard_request>
        """
    }

    /// Resolves a clipboard-dependent instruction. Empty material fails closed
    /// instead of asking the model to answer without the text it needs.
    /// `conversationContext`, when present, carries recent turns of the same
    /// chat as background (see `compose`).
    public static func resolve(
        instruction: String,
        material: String?,
        conversationContext: String? = nil
    ) -> Resolution {
        let body = trimmed(material ?? "")
        guard !body.isEmpty else { return .materialUnavailable }
        return .ready(
            compose(
                instruction: strippingPlaceholder(instruction),
                material: body,
                conversationContext: conversationContext
            )
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

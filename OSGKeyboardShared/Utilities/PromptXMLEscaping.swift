// PromptXMLEscaping.swift
// OSGKeyboard · Shared
//
// Escapes untrusted prompt data embedded in XML-like text nodes.

import Foundation

enum PromptXMLEscaping {
    static func escapeTextContent(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// AITodoExtraction.swift
// OSGKeyboard · Shared
//
// Parses the LLM's extract-todos reply into reminder titles. Fail closed:
// empty / NONE / "no tasks" never become a Shortcut run. A single long
// echo of the clipboard is also rejected so the model cannot dump the
// whole paste as one reminder.

import Foundation

public enum AITodoExtraction: Sendable {
    public static let maximumItems = 20

    private static let emptyTokens: Set<String> = [
        "none", "no", "n/a", "na", "nil", "null",
        "无", "没有", "没有待办", "没有待办事项", "无待办", "无待办事项",
        "no tasks", "no task", "no todos", "no to-dos", "no to-do",
        "no actionable items", "no action items",
    ]

    /// Titles to send to the companion Shortcut. Empty → do not run it.
    public static func items(from raw: String, sourceClipboard: String? = nil) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if isEmptyToken(trimmed) { return [] }

        var seen = Set<String>()
        var items: [String] = []
        for line in trimmed.components(separatedBy: .newlines) {
            let title = stripBullet(line)
            guard !title.isEmpty, !isEmptyToken(title) else { continue }
            let key = title.lowercased()
            guard seen.insert(key).inserted else { continue }
            items.append(title)
            if items.count == maximumItems { break }
        }

        if items.count == 1, isWholeClipboardEcho(items[0], source: sourceClipboard) {
            return []
        }
        return items
    }

    private static func isEmptyToken(_ text: String) -> Bool {
        let folded = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.!！"))
            .lowercased()
        return emptyTokens.contains(folded)
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["- ", "* ", "• ", "、"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dotted = text.range(of: #"^\d+[\.\)、]\s*"#, options: .regularExpression) {
            text = String(text[dotted.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// One long line that is essentially the clipboard body is not a todo.
    private static func isWholeClipboardEcho(_ item: String, source: String?) -> Bool {
        guard let source, source.count > 80, item.count > 80 else { return false }
        let a = collapse(item)
        let b = collapse(source)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return a.contains(b) || b.contains(a)
    }

    private static func collapse(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

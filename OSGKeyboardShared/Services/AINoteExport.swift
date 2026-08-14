// AINoteExport.swift
// OSGKeyboard · Shared
//
// Builds one Notes payload: generated title + original clipboard body,
// joined by `fieldSeparator` so the companion Shortcut can combine them
// as first-line title + body. Fail open: a missing or unusable model title
// falls back to a dated snippet so the paste still lands in Notes.

import Foundation

public enum AINoteExport: Sendable {
    public static let maximumTitleLength = 40
    public static let maximumSnippetLength = 24
    /// Split token for the companion Shortcut: title, then original body.
    /// Newlines stay inside the body, so do not join with `\n`.
    /// Avoid `<>` — `shortcuts://…&text=` treats angle brackets like tags and
    /// drops the payload (todos/events work because they only use `|` / newlines).
    public static let fieldSeparator = "||OSG_NOTE||"

    private static let emptyTokens: Set<String> = [
        "none", "no", "n/a", "na", "nil", "null",
        "无", "没有", "没有标题", "无标题",
        "no title", "no note", "no notes",
    ]

    /// One string for Shortcuts: `title||OSG_NOTE||body`. Empty → do not run it.
    public static func items(
        from answer: String,
        sourceClipboard: String?,
        now: Date = Date(),
        locale: String = "zh",
        calendar: Calendar = .current
    ) -> [String] {
        let body = sourceClipboard?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !body.isEmpty else { return [] }
        let title = resolvedTitle(
            from: answer,
            body: body,
            now: now,
            locale: locale,
            calendar: calendar
        )
        return ["\(title)\(fieldSeparator)\(body)"]
    }

    // MARK: - Title

    private static func resolvedTitle(
        from answer: String,
        body: String,
        now: Date,
        locale: String,
        calendar: Calendar
    ) -> String {
        if let title = parsedTitle(answer),
           !isWholeClipboardEcho(title, source: body) {
            return truncate(title, maximumTitleLength)
        }
        return fallbackTitle(body: body, now: now, locale: locale, calendar: calendar)
    }

    private static func parsedTitle(_ raw: String) -> String? {
        let first = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        var title = stripBullet(first)
        title = stripWrappingQuotes(title)
        if let pipe = title.firstIndex(of: "|") {
            title = String(title[..<pipe])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !title.isEmpty, !isEmptyToken(title) else { return nil }
        return title
    }

    private static func fallbackTitle(
        body: String,
        now: Date,
        locale: String,
        calendar: Calendar
    ) -> String {
        let stamp = dateStamp(now, locale: locale, calendar: calendar)
        let snippet = truncate(firstLine(body), maximumSnippetLength)
        if snippet.isEmpty { return stamp }
        return "\(stamp) · \(snippet)"
    }

    private static func dateStamp(_ now: Date, locale: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: locale == "zh" ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = locale == "zh" ? "M月d日" : "d MMM"
        return formatter.string(from: now)
    }

    // MARK: - Text

    private static func firstLine(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func truncate(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
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

    private static func stripWrappingQuotes(_ line: String) -> String {
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("“", "”"),
            ("「", "」"),
            ("『", "』"),
            ("'", "'"),
            ("‘", "’"),
        ]
        var text = line
        for (open, close) in pairs where text.count >= 2 {
            if text.first == open, text.last == close {
                text = String(text.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// A title that is essentially the whole clipboard is not a title.
    private static func isWholeClipboardEcho(_ title: String, source: String) -> Bool {
        guard source.count > 80, title.count > 80 else { return false }
        let a = collapse(title)
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

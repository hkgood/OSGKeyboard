// AIGenericSkillExport.swift
// OSGKeyboard · Shared
//
// Line-oriented Shortcut input for user-created export skills. Built-in
// extract-todos / extract-events / save-to-notes keep their dedicated parsers.

import Foundation

public enum AIGenericSkillExport {
    public static let maximumItems = 20

    public static func items(from answer: String) -> [String] {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.compare("NONE", options: .caseInsensitive) == .orderedSame {
            return []
        }
        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.isEmpty { return [trimmed] }
        return Array(lines.prefix(maximumItems))
    }
}

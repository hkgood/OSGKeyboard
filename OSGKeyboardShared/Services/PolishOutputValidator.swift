// PolishOutputValidator.swift
// OSGKeyboard · Shared
//
// Deterministic protection for content that must survive an LLM rewrite.

import Foundation

public enum PolishViolation: Equatable, Sendable {
    case missingDictionaryTerms([String])
    case missingIdentifiers([String])

    public var logLabel: String {
        switch self {
        case .missingDictionaryTerms(let values): return "dictionary:\(values.count)"
        case .missingIdentifiers(let values): return "identifier:\(values.count)"
        }
    }
}

public enum PolishOutputValidator {
    public static func validate(
        input: String,
        output: String,
        dictionary: PersonalDictionary
    ) -> [PolishViolation] {
        var violations: [PolishViolation] = []

        let missingTerms = dictionary.effectiveEntries.compactMap { entry -> String? in
            let variants = [entry.term] + entry.aliases
            let appeared = variants.contains {
                input.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            guard appeared, !output.contains(entry.term) else { return nil }
            return entry.term
        }
        if !missingTerms.isEmpty {
            violations.append(.missingDictionaryTerms(Array(Set(missingTerms)).sorted()))
        }

        let missingIdentifiers = protectedIdentifiers(in: input)
            .filter { !output.contains($0) }
            .sorted()
        if !missingIdentifiers.isEmpty {
            violations.append(.missingIdentifiers(missingIdentifiers))
        }

        return violations
    }

    private static func protectedIdentifiers(in text: String) -> Set<String> {
        let patterns = [
            #"https?://[^\s<>"']+"#,
            #"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"#,
            #"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b"#,
            #"\b[A-Za-z]+[a-z0-9][A-Z][A-Za-z0-9]*\b"#
        ]
        var result = Set<String>()
        for pattern in patterns {
            for value in matches(pattern, in: text) {
                result.insert(value.trimmingCharacters(in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "(")
                )))
            }
        }
        let pathPattern = #"(?:^|[\s(])(?:~?/|\.\.?/)?(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+"#
        for rawValue in matches(pathPattern, in: text) {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "(")
            ))
            if isProtectedPath(value) {
                result.insert(value)
            }
        }
        return result
    }

    private static func isProtectedPath(_ value: String) -> Bool {
        let explicitPrefix = value.hasPrefix("/")
            || value.hasPrefix("./")
            || value.hasPrefix("../")
            || value.hasPrefix("~/")
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let segments = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count >= 2 else { return false }

        // Dates and fractions such as 2025/03/01, 3/4, and 3/5 are not paths.
        if segments.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return false
        }
        if explicitPrefix { return true }
        if segments.count >= 3 { return true }
        return segments.contains { $0.contains(".") || $0.contains("_") }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

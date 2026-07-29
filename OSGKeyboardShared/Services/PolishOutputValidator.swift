// PolishOutputValidator.swift
// OSGKeyboard · Shared
//
// Deterministic protection for content that must survive an LLM rewrite.
// High-confidence violations are enforced; noisier heuristics are observed.

import Foundation

public enum PolishViolation: Equatable, Sendable {
    case missingDictionaryTerms([String])
    case missingIdentifiers([String])
    case missingNumbers([String])
    case lengthOutOfRange(ratio: Double, allowed: ClosedRange<Double>)
    case languageDrift(inputCJK: Double, outputCJK: Double)

    public var isHard: Bool {
        switch self {
        case .missingDictionaryTerms, .missingIdentifiers:
            return true
        case .missingNumbers, .lengthOutOfRange, .languageDrift:
            return false
        }
    }

    public var logLabel: String {
        switch self {
        case .missingDictionaryTerms(let values): return "dictionary:\(values.count)"
        case .missingIdentifiers(let values): return "identifier:\(values.count)"
        case .missingNumbers(let values): return "number:\(values.count)"
        case .lengthOutOfRange: return "length:1"
        case .languageDrift: return "language:1"
        }
    }
}

public enum PolishOutputValidator {
    public static func validate(
        input: String,
        output: String,
        dictionary: PersonalDictionary,
        lengthRatio: ClosedRange<Double>
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

        let inputNumbers = matches(#"\d+(?:[.,]\d+)*"#, in: input)
        let missingNumbers = Array(Set(inputNumbers.filter { !output.contains($0) })).sorted()
        if !missingNumbers.isEmpty {
            violations.append(.missingNumbers(missingNumbers))
        }

        if input.count >= 20 {
            let ratio = Double(output.count) / Double(max(input.count, 1))
            if !lengthRatio.contains(ratio) {
                violations.append(.lengthOutOfRange(ratio: ratio, allowed: lengthRatio))
            }
        }

        let inputCJK = TranscriptLanguageDetector.cjkRatio(input)
        let outputCJK = TranscriptLanguageDetector.cjkRatio(output)
        if input.count >= 20, abs(inputCJK - outputCJK) >= 0.15 {
            violations.append(.languageDrift(inputCJK: inputCJK, outputCJK: outputCJK))
        }

        return violations
    }

    public static func retryInstruction(
        for violations: [PolishViolation],
        useChinese: Bool
    ) -> String {
        let protectedValues = violations.flatMap { violation -> [String] in
            switch violation {
            case .missingDictionaryTerms(let values), .missingIdentifiers(let values):
                return values
            default:
                return []
            }
        }
        guard !protectedValues.isEmpty else { return "" }
        let joined = protectedValues.joined(separator: ", ")
        return useChinese
            ? "上一次输出遗漏或修改了以下受保护内容：\(joined)。重新处理，并确保它们逐字符原样保留。"
            : "The previous output omitted or changed protected content: \(joined). Process it again and preserve every item exactly."
    }

    private static func protectedIdentifiers(in text: String) -> Set<String> {
        let patterns = [
            #"https?://[^\s<>"']+"#,
            #"\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b"#,
            #"(?:^|[\s(])(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+"#,
            #"\b[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b"#,
            #"\b[A-Za-z]+[a-z0-9][A-Z][A-Za-z0-9]*\b"#,
        ]
        var result = Set<String>()
        for pattern in patterns {
            for value in matches(pattern, in: text) {
                result.insert(value.trimmingCharacters(in: .whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "(")
                )))
            }
        }
        return result
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

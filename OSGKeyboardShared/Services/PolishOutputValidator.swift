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
        let allowedOrdinalNumbers = allowedOrdinalRepairNumbers(input: input, output: output)
        let missingNumbers = Array(Set(inputNumbers.filter {
            !output.contains($0) && !allowedOrdinalNumbers.contains($0)
        })).sorted()
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

        // Dates and fractions such as 2025/03/01, 3/4, and 3/5 are numeric
        // values, not file paths. They remain covered by soft number telemetry.
        if segments.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return false
        }
        if explicitPrefix { return true }
        if segments.count >= 3 { return true }
        return segments.contains { $0.contains(".") || $0.contains("_") }
    }

    private static func allowedOrdinalRepairNumbers(
        input: String,
        output: String
    ) -> Set<String> {
        let pattern = #"第\s*(\d+)\s*[:：]\s*00"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(input.startIndex..<input.endIndex, in: input)
        var allowed = Set<String>()

        for match in regex.matches(in: input, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let ordinalRange = Range(match.range(at: 1), in: input),
                  let matchRange = Range(match.range, in: input) else {
                continue
            }
            let ordinal = String(input[ordinalRange])
            let prefixRange = input.startIndex..<matchRange.lowerBound
            let prefix = String(input[prefixRange])
            guard hasEstablishedEnumeration(prefix) else { continue }

            let escaped = NSRegularExpression.escapedPattern(for: ordinal)
            let arabicListPattern = #"(?m)(?:^|\n)\s*"# + escaped + #"\s*[.、)]"#
            let chineseOrdinal = Int(ordinal).flatMap(chineseNumeral)
            let hasArabicOrdinal = output.range(
                of: arabicListPattern,
                options: .regularExpression
            ) != nil
            let hasChineseOrdinal = chineseOrdinal.map {
                output.contains("第\($0)点")
            } ?? false
            if hasArabicOrdinal || hasChineseOrdinal {
                allowed.insert(ordinal)
                allowed.insert("00")
            }
        }
        return allowed
    }

    private static func hasEstablishedEnumeration(_ prefix: String) -> Bool {
        prefix.range(
            of: #"(?:第一点|第[一二三四五六七八九十]+点|首先)"#,
            options: .regularExpression
        ) != nil
    }

    private static func chineseNumeral(_ value: Int) -> String? {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch value {
        case 0...9:
            return digits[value]
        case 10:
            return "十"
        case 11...19:
            return "十" + digits[value % 10]
        case 20...99:
            let tens = digits[value / 10] + "十"
            return value % 10 == 0 ? tens : tens + digits[value % 10]
        default:
            return nil
        }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}

// ClipboardHistoryPolicy.swift
// OSGKeyboard · Shared
//
// Pure rules for accepting clipboard text and simple English/whitespace tokens.

import Foundation

public enum ClipboardHistoryPolicy: Sendable {
    public static let maxEntries = 15
    public static let maxEntryUTF8Bytes = 16 * 1_024
    public static let maxPayloadBytes = 256 * 1_024
    /// Reject short all-digit strings (OTP / verification-code shaped).
    public static let otpDigitMaxLength = 8
    /// AI idle clipboard-hint eligibility window after copy.
    public static let aiHintEligibilitySeconds: TimeInterval = 30

    public enum RejectionReason: Equatable, Sendable {
        case empty
        case exceedsEntrySize
        case oneTimeCode
        case privateKey
        case jwt
        case bearerToken
        case providerKey
        case paymentCard
    }

    /// Returns trimmed text when it should be stored; otherwise `nil`.
    public static func acceptedText(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rejectionReason(for: trimmed) == nil else { return nil }
        return trimmed
    }

    /// A conservative, pure decision used by capture and unit tests.
    public static func rejectionReason(for text: String) -> RejectionReason? {
        guard !text.isEmpty else { return .empty }
        guard isStorageSizeAllowed(text) else { return .exceedsEntrySize }
        if looksLikeOTP(text) { return .oneTimeCode }
        if containsPrivateKeyHeader(text) { return .privateKey }
        if containsJWT(text) { return .jwt }
        if containsBearerToken(text) { return .bearerToken }
        if containsProviderKey(text) { return .providerKey }
        if containsLuhnValidCardNumber(text) { return .paymentCard }
        return nil
    }

    public static func isStorageSizeAllowed(_ text: String) -> Bool {
        text.lengthOfBytes(using: .utf8) <= maxEntryUTF8Bytes
    }

    public static func encodedPayloadFitsLimit(_ entries: [ClipboardHistoryEntry]) -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        return data.count <= maxPayloadBytes
    }

    /// A pasteboard generation observed inside a secure field must never be
    /// persisted later after focus moves to a normal field.
    public static func shouldSuppressCapture(
        changeCount: Int,
        secureFieldSuppressedChangeCount: Int?
    ) -> Bool {
        changeCount == secureFieldSuppressedChangeCount
    }

    /// Removes invalid legacy rows without truncating row contents.
    public static func sanitizedEntries(
        _ entries: [ClipboardHistoryEntry],
        limit: Int = maxEntries
    ) -> [ClipboardHistoryEntry] {
        var seen = Set<String>()
        var sanitized = entries.filter { entry in
            isStorageSizeAllowed(entry.text) && seen.insert(entry.text).inserted
        }
        if sanitized.count > limit {
            sanitized = Array(sanitized.prefix(limit))
        }
        while !sanitized.isEmpty, !encodedPayloadFitsLimit(sanitized) {
            sanitized.removeLast()
        }
        return sanitized
    }

    /// Pure digits (optionally with spaces/dashes) of length 4…8 → treat as OTP.
    public static func looksLikeOTP(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard digits.count == text.filter({ !$0.isWhitespace && $0 != "-" }).count else {
            return false
        }
        if digits.count == 4, let year = Int(digits), (1900...2099).contains(year) {
            return false
        }
        let dateParts = text.split(separator: "-", omittingEmptySubsequences: false)
        if dateParts.count == 2,
           let month = Int(dateParts[0]),
           let day = Int(dateParts[1]),
           isValidGregorianDate(year: 2000, month: month, day: day) {
            return false
        }
        if digits.count == 8 {
            let year = Int(digits.prefix(4)) ?? 0
            let monthStart = digits.index(digits.startIndex, offsetBy: 4)
            let dayStart = digits.index(digits.startIndex, offsetBy: 6)
            let month = Int(digits[monthStart..<dayStart]) ?? 0
            let day = Int(digits[dayStart...]) ?? 0
            if (1900...2099).contains(year),
               isValidGregorianDate(year: year, month: month, day: day) {
                return false
            }
        }
        return (4...otpDigitMaxLength).contains(digits.count)
    }

    /// Simple whitespace / ASCII-punctuation split for English-ish snippets.
    public static func whitespaceTokens(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            // Skip pure CJK-only single chars that aren't useful as chips.
            .filter { token in
                token.count > 1 || token.unicodeScalars.contains { $0.isASCII }
            }
    }

    /// Merge `incoming` onto `existing` (newest first), dedupe by exact text.
    public static func merging(
        incoming: ClipboardHistoryEntry,
        into existing: [ClipboardHistoryEntry],
        limit: Int = maxEntries
    ) -> [ClipboardHistoryEntry] {
        var next = existing.filter { $0.text != incoming.text }
        next.insert(incoming, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        return next
    }

    private static func containsPrivateKeyHeader(_ text: String) -> Bool {
        text.uppercased().split(whereSeparator: \.isNewline).contains { line in
            let header = line.trimmingCharacters(in: .whitespaces)
            return header == "-----BEGIN PRIVATE KEY-----"
                || (header.hasPrefix("-----BEGIN ")
                    && header.hasSuffix(" PRIVATE KEY-----"))
        }
    }

    private static func containsJWT(_ text: String) -> Bool {
        credentialCandidates(in: text).contains { candidate in
            let segments = candidate.split(separator: ".", omittingEmptySubsequences: false)
            guard segments.count == 3,
                  segments[0].count >= 16,
                  segments[1].count >= 16,
                  segments[2].count >= 32
            else {
                return false
            }
            return segments.allSatisfy { segment in
                segment.allSatisfy(isBase64URLCharacter)
            }
        }
    }

    private static func containsBearerToken(_ text: String) -> Bool {
        let candidates = credentialCandidates(in: text)
        guard candidates.count >= 2 else { return false }
        for index in 0..<(candidates.count - 1) {
            guard candidates[index].caseInsensitiveCompare("bearer") == .orderedSame else {
                continue
            }
            let token = candidates[index + 1]
            if token.count >= 16, token.allSatisfy(isCredentialCharacter) {
                return true
            }
        }
        return false
    }

    private static func containsProviderKey(_ text: String) -> Bool {
        let patterns: [(prefix: String, minimumLength: Int, caseSensitive: Bool)] = [
            ("sk-ant-", 32, true),
            ("sk-proj-", 32, true),
            ("sk-", 32, true),
            ("AIza", 35, true),
            ("github_pat_", 30, true),
            ("ghp_", 30, true),
            ("glpat-", 20, true),
            ("xoxb-", 24, true),
            ("xoxp-", 24, true),
            ("xoxa-", 24, true),
            ("xoxr-", 24, true),
            ("AKIA", 20, true),
            ("ASIA", 20, true)
        ]
        return credentialCandidates(in: text).contains { candidate in
            guard candidate.allSatisfy(isCredentialCharacter) else { return false }
            return patterns.contains { pattern in
                guard candidate.count >= pattern.minimumLength else { return false }
                if pattern.caseSensitive {
                    return candidate.hasPrefix(pattern.prefix)
                }
                return candidate.lowercased().hasPrefix(pattern.prefix.lowercased())
            }
        }
    }

    private static func containsLuhnValidCardNumber(_ text: String) -> Bool {
        var run = ""
        func isAllowed(_ scalar: UnicodeScalar) -> Bool {
            isASCIIDigit(scalar) || scalar == " " || scalar == "-"
        }
        func runIsCard(_ candidate: String) -> Bool {
            let digits = candidate.unicodeScalars.compactMap { scalar -> Int? in
                guard isASCIIDigit(scalar) else { return nil }
                return Int(scalar.value - 48)
            }
            // Restrict automatic filtering to the overwhelmingly common
            // 16-digit card shape; broader Luhn matches also catch IMEI and
            // other legitimate identifiers.
            guard digits.count == 16 else { return false }
            var sum = 0
            for (offset, digit) in digits.reversed().enumerated() {
                var value = digit
                if offset.isMultiple(of: 2) == false {
                    value *= 2
                    if value > 9 { value -= 9 }
                }
                sum += value
            }
            return sum.isMultiple(of: 10)
        }

        for scalar in text.unicodeScalars {
            if isAllowed(scalar) {
                run.unicodeScalars.append(scalar)
            } else {
                if runIsCard(run) { return true }
                run.removeAll(keepingCapacity: true)
            }
        }
        return runIsCard(run)
    }

    private static func credentialCandidates(in text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "\"'`()[]{}<>,;:=")
        )
        return text.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    private static func isBase64URLCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1
            && character.unicodeScalars.allSatisfy { scalar in
                isASCIIDigit(scalar)
                    || (65...90).contains(scalar.value)
                    || (97...122).contains(scalar.value)
                    || scalar == "-"
                    || scalar == "_"
            }
    }

    private static func isCredentialCharacter(_ character: Character) -> Bool {
        isBase64URLCharacter(character)
            || character == "."
            || character == "+"
            || character == "/"
            || character == "="
            || character == "~"
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value)
    }

    private static func isValidGregorianDate(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    /// Whether `entry` still qualifies for AI clipboard hints.
    public static func isEligibleForAIHint(
        _ entry: ClipboardHistoryEntry,
        now: Date = Date()
    ) -> Bool {
        now.timeIntervalSince(entry.createdAt) <= aiHintEligibilitySeconds
    }
}

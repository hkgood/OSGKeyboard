// AIPhoneNumberActions.swift
// OSGKeyboard · Shared
//
// Deterministic phone-number actions. Detection stays local; contact creation
// uses a short-lived App Group payload so the number never appears in a URL.

import Foundation

public enum AIPhoneNumberResolver: Sendable {
    public static func phoneNumbers(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        let numbers = detector.matches(
            in: text,
            options: [],
            range: range
        ).compactMap { match in
            normalized(match.phoneNumber ?? "")
        }
        return deduplicated(numbers)
    }

    public static func singlePhoneNumber(in text: String) -> String? {
        singlePhoneNumber(from: phoneNumbers(in: text))
    }

    public static func singlePhoneNumber(
        from labels: [ClipboardTextLabel]
    ) -> String? {
        singlePhoneNumber(from: labels.compactMap {
            normalized($0.sourceText)
        })
    }

    public static func telephoneURL(for phoneNumber: String) -> URL? {
        guard let number = normalized(phoneNumber) else { return nil }
        return URL(string: "tel:\(number)")
    }

    public static func normalized(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var result = trimmed.hasPrefix("+") ? "+" : ""
        for character in trimmed {
            guard let value = character.wholeNumberValue else { continue }
            result.append(String(value))
        }
        let digitCount = result.filter(\.isNumber).count
        guard (3...20).contains(digitCount) else { return nil }
        return result
    }

    private static func singlePhoneNumber(from numbers: [String]) -> String? {
        let numbers = deduplicated(numbers)
        return numbers.count == 1 ? numbers[0] : nil
    }

    private static func deduplicated(_ numbers: [String]) -> [String] {
        var seen = Set<String>()
        return numbers.filter { seen.insert($0).inserted }
    }
}

public struct AIContactCreationPayload: Codable, Equatable, Sendable {
    public let phoneNumber: String
    public let createdAt: Date

    public init(phoneNumber: String, createdAt: Date = Date()) {
        self.phoneNumber = phoneNumber
        self.createdAt = createdAt
    }
}

public enum AIContactCreationHandoff: Sendable {
    public static let pendingKey = "ai.contactCreation.pending.v1"
    public static let maximumAge: TimeInterval = 2 * 60

    public static func encode(_ payload: AIContactCreationPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    public static func decode(
        _ data: Data,
        now: Date = Date()
    ) -> AIContactCreationPayload? {
        guard let payload = try? JSONDecoder().decode(
            AIContactCreationPayload.self,
            from: data
        ),
              now.timeIntervalSince(payload.createdAt) >= 0,
              now.timeIntervalSince(payload.createdAt) <= maximumAge,
              let normalized = AIPhoneNumberResolver.normalized(payload.phoneNumber) else {
            return nil
        }
        return AIContactCreationPayload(
            phoneNumber: normalized,
            createdAt: payload.createdAt
        )
    }
}

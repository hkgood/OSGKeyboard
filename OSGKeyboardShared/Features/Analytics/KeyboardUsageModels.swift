// KeyboardUsageModels.swift
// OSGKeyboard · Shared
//
// Fixed-schema keyboard usage summaries. Raw text never crosses this model
// boundary: callers provide only grapheme counts and random session IDs.

import Foundation

public enum KeyboardTextInsertionSource: String, CaseIterable, Sendable {
    case manualKeyboard = "MANUAL_KEYBOARD"
    case voiceTranscription = "VOICE_TRANSCRIPTION"
    case aiGenerated = "AI_GENERATED"
    case pasteboard = "PASTEBOARD"
    case editGenerated = "EDIT_GENERATED"
    case redo = "REDO"
    case assistantAction = "ASSISTANT_ACTION"
    case debugDemo = "DEBUG_DEMO"

    public var contributesToKeyboardUsage: Bool {
        self == .manualKeyboard
    }
}

public struct KeyboardUsageCharacterCounts: Equatable, Sendable {
    public static let maximumPerCategory = 1_000_000

    public let chinese: Int
    public let english: Int
    public let other: Int

    public init(chinese: Int = 0, english: Int = 0, other: Int = 0) {
        self.chinese = Self.clamped(chinese)
        self.english = Self.clamped(english)
        self.other = Self.clamped(other)
    }

    public var total: Int {
        chinese + english + other
    }

    public var isEmpty: Bool {
        total == 0
    }

    private static func clamped(_ value: Int) -> Int {
        min(maximumPerCategory, max(0, value))
    }
}

public enum KeyboardUsageCharacterClassifier {
    public static func classify(_ text: String) -> KeyboardUsageCharacterCounts {
        var chinese = 0
        var english = 0
        var other = 0

        for character in text {
            switch classification(of: character) {
            case .chinese:
                chinese = saturatingIncrement(chinese)
            case .english:
                english = saturatingIncrement(english)
            case .other:
                other = saturatingIncrement(other)
            }
        }
        return KeyboardUsageCharacterCounts(
            chinese: chinese,
            english: english,
            other: other
        )
    }

    private enum Classification {
        case chinese
        case english
        case other
    }

    private static func classification(of character: Character) -> Classification {
        // ICU Script properties cover CJK extensions and future Unicode updates;
        // checking the whole grapheme keeps combining sequences at one count.
        if character.unicodeScalars.contains(where: {
            matchesScript($0, regularExpression: hanScriptExpression)
        }) {
            return .chinese
        }
        if character.unicodeScalars.contains(where: {
            isLetter($0) && matchesScript($0, regularExpression: latinScriptExpression)
        }) {
            return .english
        }
        return .other
    }

    private static func matchesScript(
        _ scalar: Unicode.Scalar,
        regularExpression: NSRegularExpression
    ) -> Bool {
        let text = String(scalar)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regularExpression.firstMatch(
            in: text,
            options: [],
            range: range
        ) != nil
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter,
             .lowercaseLetter,
             .titlecaseLetter,
             .modifierLetter,
             .otherLetter:
            return true
        default:
            return false
        }
    }

    private static func saturatingIncrement(_ value: Int) -> Int {
        min(KeyboardUsageCharacterCounts.maximumPerCategory, value + 1)
    }

    private static let hanScriptExpression = try! NSRegularExpression(
        pattern: #"^\p{sc=Han}$"#
    )
    private static let latinScriptExpression = try! NSRegularExpression(
        pattern: #"^\p{sc=Latin}$"#
    )
}

public enum KeyboardUsageSessionClassification: Int, CaseIterable, Sendable {
    case chineseOnly = 0
    case englishOnly = 1
    case mixedLanguage = 2
    case otherOnly = 3

    init(counts: KeyboardUsageCharacterCounts) {
        switch (counts.chinese > 0, counts.english > 0) {
        case (true, true):
            self = .mixedLanguage
        case (true, false):
            self = .chineseOnly
        case (false, true):
            self = .englishOnly
        case (false, false):
            self = .otherOnly
        }
    }

    func merging(_ counts: KeyboardUsageCharacterCounts) -> Self {
        let hasChinese = self == .chineseOnly
            || self == .mixedLanguage
            || counts.chinese > 0
        let hasEnglish = self == .englishOnly
            || self == .mixedLanguage
            || counts.english > 0
        switch (hasChinese, hasEnglish) {
        case (true, true):
            return .mixedLanguage
        case (true, false):
            return .chineseOnly
        case (false, true):
            return .englishOnly
        case (false, false):
            return .otherOnly
        }
    }
}

public enum KeyboardUsageModelError: Error, Sendable {
    case invalidDate
    case invalidCount
    case invalidSessionPartition
    case invalidVersion
    case invalidResponseCounts
    case unknownField(String)
}

public struct KeyboardUsageSummary: Codable, Equatable, Sendable {
    public let clientSummaryId: UUID
    public let summaryDate: String
    public let chineseCharacterCount: Int
    public let englishCharacterCount: Int
    public let otherCharacterCount: Int
    public let inputSessionCount: Int
    public let chineseOnlySessionCount: Int
    public let englishOnlySessionCount: Int
    public let mixedLanguageSessionCount: Int
    public let otherOnlySessionCount: Int
    public let appVersion: String
    public let osVersion: String

    public init(
        clientSummaryId: UUID,
        summaryDate: String,
        chineseCharacterCount: Int,
        englishCharacterCount: Int,
        otherCharacterCount: Int,
        inputSessionCount: Int,
        chineseOnlySessionCount: Int,
        englishOnlySessionCount: Int,
        mixedLanguageSessionCount: Int,
        otherOnlySessionCount: Int,
        appVersion: String,
        osVersion: String
    ) throws {
        let characterCounts = [
            chineseCharacterCount,
            englishCharacterCount,
            otherCharacterCount
        ]
        let sessionCounts = [
            inputSessionCount,
            chineseOnlySessionCount,
            englishOnlySessionCount,
            mixedLanguageSessionCount,
            otherOnlySessionCount
        ]
        guard KeyboardUsageUTCDate.date(from: summaryDate) != nil else {
            throw KeyboardUsageModelError.invalidDate
        }
        guard characterCounts.allSatisfy({
            (0...KeyboardUsageCharacterCounts.maximumPerCategory).contains($0)
        }),
        sessionCounts.allSatisfy({ (0...100_000).contains($0) }) else {
            throw KeyboardUsageModelError.invalidCount
        }
        guard chineseOnlySessionCount
                + englishOnlySessionCount
                + mixedLanguageSessionCount
                + otherOnlySessionCount == inputSessionCount,
              characterCounts.reduce(0, +) >= inputSessionCount else {
            throw KeyboardUsageModelError.invalidSessionPartition
        }
        guard AnalyticsEnvironment.isSafeVersion(appVersion),
              AnalyticsEnvironment.isSafeVersion(osVersion) else {
            throw KeyboardUsageModelError.invalidVersion
        }

        self.clientSummaryId = clientSummaryId
        self.summaryDate = summaryDate
        self.chineseCharacterCount = chineseCharacterCount
        self.englishCharacterCount = englishCharacterCount
        self.otherCharacterCount = otherCharacterCount
        self.inputSessionCount = inputSessionCount
        self.chineseOnlySessionCount = chineseOnlySessionCount
        self.englishOnlySessionCount = englishOnlySessionCount
        self.mixedLanguageSessionCount = mixedLanguageSessionCount
        self.otherOnlySessionCount = otherOnlySessionCount
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clientSummaryId
        case summaryDate
        case chineseCharacterCount
        case englishCharacterCount
        case otherCharacterCount
        case inputSessionCount
        case chineseOnlySessionCount
        case englishOnlySessionCount
        case mixedLanguageSessionCount
        case otherOnlySessionCount
        case appVersion
        case osVersion
    }

    public init(from decoder: Decoder) throws {
        try KeyboardUsageCodableAllowlist.rejectUnknownKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            clientSummaryId: container.decode(UUID.self, forKey: .clientSummaryId),
            summaryDate: container.decode(String.self, forKey: .summaryDate),
            chineseCharacterCount: container.decode(Int.self, forKey: .chineseCharacterCount),
            englishCharacterCount: container.decode(Int.self, forKey: .englishCharacterCount),
            otherCharacterCount: container.decode(Int.self, forKey: .otherCharacterCount),
            inputSessionCount: container.decode(Int.self, forKey: .inputSessionCount),
            chineseOnlySessionCount: container.decode(
                Int.self,
                forKey: .chineseOnlySessionCount
            ),
            englishOnlySessionCount: container.decode(
                Int.self,
                forKey: .englishOnlySessionCount
            ),
            mixedLanguageSessionCount: container.decode(
                Int.self,
                forKey: .mixedLanguageSessionCount
            ),
            otherOnlySessionCount: container.decode(
                Int.self,
                forKey: .otherOnlySessionCount
            ),
            appVersion: container.decode(String.self, forKey: .appVersion),
            osVersion: container.decode(String.self, forKey: .osVersion)
        )
    }
}

public struct KeyboardUsageUploadRequest: Codable, Equatable, Sendable {
    public let installationId: UUID
    public let summaries: [KeyboardUsageSummary]

    public init(installationId: UUID, summaries: [KeyboardUsageSummary]) {
        self.installationId = installationId
        self.summaries = summaries
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case installationId
        case summaries
    }

    public init(from decoder: Decoder) throws {
        try KeyboardUsageCodableAllowlist.rejectUnknownKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installationId = try container.decode(UUID.self, forKey: .installationId)
        summaries = try container.decode([KeyboardUsageSummary].self, forKey: .summaries)
    }
}

public struct KeyboardUsageUploadResponse: Codable, Equatable, Sendable {
    public let accepted: Int
    public let replayed: Int

    public init(accepted: Int, replayed: Int) throws {
        guard accepted >= 0, replayed >= 0 else {
            throw KeyboardUsageModelError.invalidResponseCounts
        }
        self.accepted = accepted
        self.replayed = replayed
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accepted
        case replayed
    }

    public init(from decoder: Decoder) throws {
        try KeyboardUsageCodableAllowlist.rejectUnknownKeys(
            in: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accepted: container.decode(Int.self, forKey: .accepted),
            replayed: container.decode(Int.self, forKey: .replayed)
        )
    }
}

enum KeyboardUsageUTCDate {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        guard value.utf8.count == 10 else { return nil }
        return formatter.date(from: value)
    }

    static func oldestAcceptedDate(relativeTo today: String) -> String? {
        guard let todayDate = date(from: today),
              let oldest = calendar.date(byAdding: .day, value: -35, to: todayDate) else {
            return nil
        }
        return string(from: oldest)
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private enum KeyboardUsageCodableAllowlist {
    static func rejectUnknownKeys(
        in decoder: Decoder,
        allowed: Set<String>
    ) throws {
        let container = try decoder.container(keyedBy: KeyboardUsageAnyCodingKey.self)
        if let unknown = container.allKeys.first(where: {
            !allowed.contains($0.stringValue)
        }) {
            throw KeyboardUsageModelError.unknownField(unknown.stringValue)
        }
    }
}

private struct KeyboardUsageAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

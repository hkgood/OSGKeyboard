// AIHintModels.swift
// OSGKeyboard · Shared
//
// Hint cards for the AI-mode idle carousel. Remote packs use `text` plus
// optional `metadata`; the host extracts a keyword `displayText` for the chip.

import Foundation

public struct AIHintMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var city: String?
    public var tempC: Double?
    public var soul: String?
    public var name: String?
    public var date: String?
    public var day: String?

    public init(
        title: String? = nil,
        city: String? = nil,
        tempC: Double? = nil,
        soul: String? = nil,
        name: String? = nil,
        date: String? = nil,
        day: String? = nil
    ) {
        self.title = title
        self.city = city
        self.tempC = tempC
        self.soul = soul
        self.name = name
        self.date = date
        self.day = day
    }
}

public struct AIHintCard: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// One-line carousel label (after host keyword pass, or local catalog).
    public var displayText: String
    /// Full user message sent to the AI question LLM on tap.
    public var prompt: String
    public var category: String
    public var priority: Int
    public var source: String
    public var locale: String
    public var conditions: [String]
    public var metadata: AIHintMetadata?

    public init(
        id: String,
        displayText: String,
        prompt: String,
        category: String,
        priority: Int = 50,
        source: String = "local",
        locale: String = "zh",
        conditions: [String] = [],
        metadata: AIHintMetadata? = nil
    ) {
        self.id = id
        self.displayText = displayText
        self.prompt = prompt
        self.category = category
        self.priority = priority
        self.source = source
        self.locale = locale
        self.conditions = conditions
        self.metadata = metadata
    }

    public var requiresClipboard30s: Bool {
        conditions.contains("clipboard_30s") || category == "clipboard"
    }

    /// Keyword shown in the idle chip; prefers feed metadata over raw `text`.
    public var resolvedDisplayText: String {
        AIHintKeywordExtractor.displayText(for: self)
    }

    public var visualKind: AIHintVisualKind {
        AIHintVisualKind.resolve(self)
    }

    enum CodingKeys: String, CodingKey {
        case id, displayText, text, prompt, category, priority, source, locale, conditions, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        prompt = try container.decode(String.self, forKey: .prompt)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "general"
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 50
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "remote"
        locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? "zh"
        conditions = try container.decodeIfPresent([String].self, forKey: .conditions) ?? []
        metadata = try container.decodeIfPresent(AIHintMetadata.self, forKey: .metadata)
        if let display = try container.decodeIfPresent(String.self, forKey: .displayText),
           !display.isEmpty {
            displayText = display
        } else {
            displayText = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayText, forKey: .displayText)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(category, forKey: .category)
        try container.encode(priority, forKey: .priority)
        try container.encode(source, forKey: .source)
        try container.encode(locale, forKey: .locale)
        try container.encode(conditions, forKey: .conditions)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

public struct AIHintPack: Codable, Equatable, Sendable {
    public var locale: String
    public var generatedAt: String?
    public var expiresAt: String?
    public var version: Int
    public var cards: [AIHintCard]
    /// Wall-clock when the host last successfully wrote this ready pack.
    public var refreshedAt: Date?

    public init(
        locale: String,
        generatedAt: String? = nil,
        expiresAt: String? = nil,
        version: Int = 1,
        cards: [AIHintCard] = [],
        refreshedAt: Date? = nil
    ) {
        self.locale = locale
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.version = version
        self.cards = cards
        self.refreshedAt = refreshedAt
    }
}

public struct AIHintManifest: Codable, Equatable, Sendable {
    public var generatedAt: String?
    public var expiresAt: String?
    public var intervalHours: Int?
    public var locales: [String]?
    public var files: [String: String?]?

    public init(
        generatedAt: String? = nil,
        expiresAt: String? = nil,
        intervalHours: Int? = nil,
        locales: [String]? = nil,
        files: [String: String?]? = nil
    ) {
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.intervalHours = intervalHours
        self.locales = locales
        self.files = files
    }
}

public enum AIHintFeedEndpoints {
    public static let baseURL = URL(string: "https://key.osglab.com/hints")!
    public static let manifestURL = baseURL.appendingPathComponent("manifest.json")
    /// Packs the app fetches and the keyboard can resolve.
    public static let supportedLocales = ["zh", "en"]

    public static func packURL(locale: String) -> URL {
        baseURL.appendingPathComponent("hints-\(locale).json")
    }
}

public enum AIHintLocaleResolver {
    /// Only `zh-Hans` uses the Chinese pack; everything else uses English.
    public static func packLocale(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let primary = (preferredLanguages.first ?? "").lowercased()
        if primary == "zh-hans" || primary.hasPrefix("zh-hans-") || primary.hasPrefix("zh-hans_") {
            return "zh"
        }
        return "en"
    }
}

public enum AIHintAppGroupKeys {
    public static let readyPackPrefix = "hints.ready."
    public static let lastSuccessPrefix = "hints.meta.lastSuccessAt."
    public static let lastAttemptAt = "hints.meta.lastAttemptAt"

    public static func readyPackKey(locale: String) -> String {
        readyPackPrefix + locale
    }

    /// Freshness is tracked per locale so a zh success cannot mask an en failure.
    public static func lastSuccessKey(locale: String) -> String {
        lastSuccessPrefix + locale
    }
}

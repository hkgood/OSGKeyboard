// OfficialSkillCatalog.swift
// OSGKeyboard · Shared
//
// Validated, host-fetched official clipboard skills. The keyboard extension
// only reads the last-known-good App Group snapshot and never performs network work.

import Foundation

public struct OfficialSkillLocalization: Codable, Equatable, Sendable {
    public let name: String
    public let summary: String
    public let prompt: String

    public init(name: String, summary: String, prompt: String) {
        self.name = name
        self.summary = summary
        self.prompt = prompt
    }
}

public struct OfficialSkillDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let systemImage: String
    public let sortOrder: Int
    public let kind: AIClipboardSkillKind
    public let thinkingEnabled: Bool
    public let localizations: [String: OfficialSkillLocalization]

    public init(
        id: String,
        systemImage: String,
        sortOrder: Int,
        kind: AIClipboardSkillKind,
        thinkingEnabled: Bool,
        localizations: [String: OfficialSkillLocalization]
    ) {
        self.id = id
        self.systemImage = systemImage
        self.sortOrder = sortOrder
        self.kind = kind
        self.thinkingEnabled = thinkingEnabled
        self.localizations = localizations
    }

    public func localization(
        language: AppUILanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> OfficialSkillLocalization {
        localization(locale: language.resolvedLanguageCode(preferredLanguages: preferredLanguages))
    }

    public func localization(locale: String) -> OfficialSkillLocalization {
        let normalized = locale.lowercased()
        let key = normalized.hasPrefix("zh") ? "zh-Hans" : "en"
        // A validated definition always contains both keys. Keep an English
        // fallback so a corrupt in-memory fixture cannot crash the extension.
        return localizations[key] ?? localizations["en"] ?? OfficialSkillLocalization(
            name: id,
            summary: "",
            prompt: ""
        )
    }

    public func asClipboardSkill(
        language: AppUILanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AIClipboardSkill {
        asClipboardSkill(
            localization: localization(
                language: language,
                preferredLanguages: preferredLanguages
            )
        )
    }

    public func asClipboardSkill(locale: String) -> AIClipboardSkill {
        asClipboardSkill(localization: localization(locale: locale))
    }

    private func asClipboardSkill(localization: OfficialSkillLocalization) -> AIClipboardSkill {
        AIClipboardSkill(
            id: id,
            systemImage: systemImage,
            titleKey: "",
            cardTitleKey: "",
            descriptionKey: "",
            kind: kind,
            isDefault: false,
            customName: localization.name,
            customSummary: localization.summary,
            customPrompt: localization.prompt,
            thinkingEnabled: thinkingEnabled
        )
    }
}

public enum OfficialSkillCatalogValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidRevision
    case invalidGeneratedAt
    case tooManySkills(maximum: Int)
    case invalidID(String)
    case duplicateID(String)
    case conflictsWithBuiltInID(String)
    case invalidSystemImage(String)
    case invalidSortOrder(String)
    case unsupportedKind(String)
    case invalidLocalizations(String)
    case emptyName(String, locale: String)
    case emptySummary(String, locale: String)
    case emptyPrompt(String, locale: String)
    case promptTooLong(String, locale: String, maximum: Int)
}

public struct OfficialSkillCatalog: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let maximumSkillCount = 100
    public static let maximumIDCharacters = 100
    public static let maximumSystemImageCharacters = 100
    public static let maximumSortOrder = 100_000
    public static let maximumNameCharacters = 40
    public static let maximumSummaryCharacters = 200
    public static let maximumPromptCharacters = 6_000

    public let schemaVersion: Int
    public let revision: Int64
    public let generatedAt: String?
    public let skills: [OfficialSkillDefinition]
    /// Host wall clock for cache freshness. Absent in the server response.
    public var refreshedAt: Date?
    /// Last response ETag. Absent in the server response.
    public var etag: String?

    public init(
        schemaVersion: Int = supportedSchemaVersion,
        revision: Int64,
        generatedAt: String? = nil,
        skills: [OfficialSkillDefinition],
        refreshedAt: Date? = nil,
        etag: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.skills = skills
        self.refreshedAt = refreshedAt
        self.etag = etag
    }

    public static let empty = OfficialSkillCatalog(revision: 0, skills: [])

    public func validated(
        builtInIDs: Set<String> = Set(AIClipboardSkillCatalog.catalog.map(\.id))
    ) throws -> OfficialSkillCatalog {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw OfficialSkillCatalogValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard revision >= 0 else {
            throw OfficialSkillCatalogValidationError.invalidRevision
        }
        if let generatedAt, Self.iso8601Date(from: generatedAt) == nil {
            throw OfficialSkillCatalogValidationError.invalidGeneratedAt
        }
        guard skills.count <= Self.maximumSkillCount else {
            throw OfficialSkillCatalogValidationError.tooManySkills(
                maximum: Self.maximumSkillCount
            )
        }

        var seen = Set<String>()
        for skill in skills {
            guard Self.isValidID(skill.id) else {
                throw OfficialSkillCatalogValidationError.invalidID(skill.id)
            }
            guard seen.insert(skill.id).inserted else {
                throw OfficialSkillCatalogValidationError.duplicateID(skill.id)
            }
            guard !builtInIDs.contains(skill.id) else {
                throw OfficialSkillCatalogValidationError.conflictsWithBuiltInID(skill.id)
            }
            let image = skill.systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !image.isEmpty, image.count <= Self.maximumSystemImageCharacters else {
                throw OfficialSkillCatalogValidationError.invalidSystemImage(skill.id)
            }
            guard (0...Self.maximumSortOrder).contains(skill.sortOrder) else {
                throw OfficialSkillCatalogValidationError.invalidSortOrder(skill.id)
            }
            guard skill.kind == .transform else {
                throw OfficialSkillCatalogValidationError.unsupportedKind(skill.id)
            }
            guard Set(skill.localizations.keys) == ["zh-Hans", "en"] else {
                throw OfficialSkillCatalogValidationError.invalidLocalizations(skill.id)
            }
            for locale in ["zh-Hans", "en"] {
                guard let localization = skill.localizations[locale] else {
                    throw OfficialSkillCatalogValidationError.invalidLocalizations(skill.id)
                }
                let name = localization.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = localization.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let prompt = localization.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= Self.maximumNameCharacters else {
                    throw OfficialSkillCatalogValidationError.emptyName(skill.id, locale: locale)
                }
                guard !summary.isEmpty,
                      summary.count <= Self.maximumSummaryCharacters else {
                    throw OfficialSkillCatalogValidationError.emptySummary(skill.id, locale: locale)
                }
                guard !prompt.isEmpty else {
                    throw OfficialSkillCatalogValidationError.emptyPrompt(skill.id, locale: locale)
                }
                guard prompt.count <= Self.maximumPromptCharacters else {
                    throw OfficialSkillCatalogValidationError.promptTooLong(
                        skill.id,
                        locale: locale,
                        maximum: Self.maximumPromptCharacters
                    )
                }
            }
        }

        return OfficialSkillCatalog(
            schemaVersion: schemaVersion,
            revision: revision,
            generatedAt: generatedAt,
            skills: skills.sorted {
                if $0.sortOrder == $1.sortOrder { return $0.id < $1.id }
                return $0.sortOrder < $1.sortOrder
            },
            refreshedAt: refreshedAt,
            etag: etag
        )
    }

    public func resolvedSkills(
        language: AppUILanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [AIClipboardSkill] {
        skills.map {
            $0.asClipboardSkill(
                language: language,
                preferredLanguages: preferredLanguages
            )
        }
    }

    public func resolvedSkills(locale: String) -> [AIClipboardSkill] {
        skills.map { $0.asClipboardSkill(locale: locale) }
    }

    private static func isValidID(_ id: String) -> Bool {
        guard id.hasPrefix("official."), id.count <= Self.maximumIDCharacters else {
            return false
        }
        let suffix = id.dropFirst("official.".count)
        guard !suffix.isEmpty else { return false }
        return suffix.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97...122).contains(value)
                || (48...57).contains(value)
                || value == 46
                || value == 45
                || value == 95
        }
    }

    private static func iso8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

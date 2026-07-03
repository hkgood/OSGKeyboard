// PolishScenario.swift
// OSGKeyboard · Shared
//
// Curated polish scenarios the user picks instead of editing a raw
// system prompt. Display names live in Shared.strings; prompt bodies
// are built by `ScenarioPrompt.make`.

import Foundation

public struct PolishScenario: Identifiable, Hashable, Sendable {
    public let id: String
    /// Shared.strings key for the picker label.
    public let labelKey: String
    /// Shared.strings key for the compact keyboard chip label.
    public let chipLabelKey: String

    public init(id: String, labelKey: String, chipLabelKey: String) {
        self.id = id
        self.labelKey = labelKey
        self.chipLabelKey = chipLabelKey
    }
}

public enum PolishScenarioCatalog {
    public static let defaultId = "daily_chat"
    public static let customId = "custom"

    /// Order matters — picker / chip render top-to-bottom.
    public static let all: [PolishScenario] = [
        PolishScenario(id: "daily_chat", labelKey: "polishScenario.daily_chat", chipLabelKey: "polishScenario.chip.daily_chat"),
        PolishScenario(id: "social_lifestyle", labelKey: "polishScenario.social_lifestyle", chipLabelKey: "polishScenario.chip.social_lifestyle"),
        PolishScenario(id: "social_short", labelKey: "polishScenario.social_short", chipLabelKey: "polishScenario.chip.social_short"),
        PolishScenario(id: "goofy", labelKey: "polishScenario.goofy", chipLabelKey: "polishScenario.chip.goofy"),
        PolishScenario(id: "work", labelKey: "polishScenario.work", chipLabelKey: "polishScenario.chip.work"),
        PolishScenario(id: "document", labelKey: "polishScenario.document", chipLabelKey: "polishScenario.chip.document"),
        PolishScenario(id: "todo", labelKey: "polishScenario.todo", chipLabelKey: "polishScenario.chip.todo"),
        PolishScenario(id: customId, labelKey: "polishScenario.custom", chipLabelKey: "polishScenario.chip.custom"),
    ]

    public static func isCustom(_ id: String) -> Bool {
        id == customId
    }

    public static func resolve(_ id: String) -> PolishScenario {
        all.first { $0.id == id } ?? all.first { $0.id == defaultId } ?? all[0]
    }

    public static func displayName(for id: String, language: AppUILanguage? = nil) -> String {
        SharedL10n.string(resolve(id).labelKey, language: language)
    }

    public static func chipLabel(for id: String, language: AppUILanguage? = nil) -> String {
        SharedL10n.string(resolve(id).chipLabelKey, language: language)
    }
}

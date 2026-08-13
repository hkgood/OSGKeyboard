// AIClipboardSkill.swift
// OSGKeyboard · Shared
//
// Built-in clipboard actions for AI idle. The catalog is an ordered list so
// Settings / the Skills tab can persist a subset or permutation without
// changing the view. Transform skills insert into the current field;
// export skills hand off to a companion Shortcut after the model runs.

import Foundation

public enum AIClipboardSkillKind: String, Sendable {
    /// LLM output is reviewed and inserted into the current text field.
    case transform
    /// LLM output is parsed and sent to a companion Shortcut. Never inserted.
    case export
}

public struct AIClipboardSkill: Identifiable, Equatable, Sendable {
    public let id: String
    public let systemImage: String
    /// Keyboard.strings key for the short chip title.
    public let titleKey: String
    /// App Localizable key for the Skills-tab card title. Falls back to `titleKey`.
    public let cardTitleKey: String
    public let descriptionKey: String
    public let kind: AIClipboardSkillKind
    /// Default skills can be turned off but not removed from the catalog.
    public let isDefault: Bool
    /// Frozen companion Shortcut name. Nil for transform skills.
    public let shortcutName: String?
    /// Optional `icloud.com/shortcuts/` share URL. Nil → open the bundled file.
    public let shortcutICloudURL: URL?

    public var requiresShortcut: Bool { kind == .export }

    public init(
        id: String,
        systemImage: String,
        titleKey: String,
        cardTitleKey: String,
        descriptionKey: String,
        kind: AIClipboardSkillKind,
        isDefault: Bool,
        shortcutName: String? = nil,
        shortcutICloudURL: URL? = nil
    ) {
        self.id = id
        self.systemImage = systemImage
        self.titleKey = titleKey
        self.cardTitleKey = cardTitleKey
        self.descriptionKey = descriptionKey
        self.kind = kind
        self.isDefault = isDefault
        self.shortcutName = shortcutName
        self.shortcutICloudURL = shortcutICloudURL
    }
}

public enum AIClipboardSkillCatalog: Sendable {
    public static let replyID = "reply"
    public static let summarizeID = "summarize"
    public static let translateID = "translate"
    public static let extractTodosID = "extractTodos"
    public static let extractTodosShortcutName = "OSG · 提取待办"
    public static let extractTodosShortcutICloudURL = URL(
        string: "https://www.icloud.com/shortcuts/520317da7ae74759b64d5fb069c71f81"
    )!

    /// Full built-in catalog, in a stable display order for the Skills tab.
    public static let catalog: [AIClipboardSkill] = [
        AIClipboardSkill(
            id: replyID,
            systemImage: "arrowshape.turn.up.left.fill",
            titleKey: "keyboard.ai.skill.reply",
            cardTitleKey: "skills.reply.name",
            descriptionKey: "skills.reply.description",
            kind: .transform,
            isDefault: true
        ),
        AIClipboardSkill(
            id: summarizeID,
            systemImage: "doc.text.magnifyingglass",
            titleKey: "keyboard.ai.skill.summarize",
            cardTitleKey: "skills.summarize.name",
            descriptionKey: "skills.summarize.description",
            kind: .transform,
            isDefault: true
        ),
        AIClipboardSkill(
            id: translateID,
            systemImage: "character.bubble.fill",
            titleKey: "keyboard.ai.skill.translate",
            cardTitleKey: "skills.translate.name",
            descriptionKey: "skills.translate.description",
            kind: .transform,
            isDefault: true
        ),
        AIClipboardSkill(
            id: extractTodosID,
            systemImage: "checklist",
            titleKey: "keyboard.ai.skill.extractTodos",
            cardTitleKey: "skills.extractTodos.name",
            descriptionKey: "skills.extractTodos.description",
            kind: .export,
            isDefault: false,
            shortcutName: extractTodosShortcutName,
            shortcutICloudURL: extractTodosShortcutICloudURL
        ),
    ]

    /// Legacy alias: the three default transform skills used to be the whole list.
    public static let builtIn: [AIClipboardSkill] = catalog

    public static func skill(id: String) -> AIClipboardSkill? {
        catalog.first { $0.id == id }
    }

    /// `enabledIDs` is the Skills-tab order. `nil` keeps the default three.
    /// An explicit empty array shows no chips (carousel fallback).
    public static func visible(enabledIDs: [String]? = nil) -> [AIClipboardSkill] {
        let ids = enabledIDs ?? AIAgentSkillLayout.defaultEnabledIDs
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public static func instruction(
        for skill: AIClipboardSkill,
        locale: String,
        translationTargetLocaleId: String
    ) -> String {
        instruction(
            skillID: skill.id,
            locale: locale,
            translationTargetLocaleId: translationTargetLocaleId
        )
    }

    /// Compact Translate-chip label. Unset target → 中英互译; Chinese UI
    /// targeting 简/繁 → 简繁互转 (avoids「中译中」); otherwise 中译× / To XX.
    public static func translateButtonTitle(
        translationTargetLocaleId: String,
        uiLanguage: AppUILanguage
    ) -> String {
        let isChineseUI = uiLanguage.resolvedLanguageCode() == "zh-Hans"
        if TranslationLanguageCatalog.isOff(translationTargetLocaleId) {
            return isChineseUI ? "中↔英" : "CN↔EN"
        }
        let target = TranslationLanguageCatalog.resolve(translationTargetLocaleId)
        if isChineseUI, target.isChineseScript {
            return "简↔繁"
        }
        if isChineseUI {
            return "中译\(target.chineseShort)"
        }
        return "To \(target.englishShort)"
    }

    public static func instruction(
        skillID: String,
        locale: String,
        translationTargetLocaleId: String
    ) -> String {
        let zh = locale == "zh"
        switch skillID {
        case replyID:
            return zh
                ? "请根据剪贴板内容起草一段礼貌、简洁的回复，语气自然，可直接发送。"
                : "Draft a concise, polite reply the user can send, based on the clipboard text."
        case summarizeID:
            return zh
                ? "请概括剪贴板内容的核心意思，保留关键事实与结论，不要改写成可发送的短消息。"
                : "Summarize the clipboard text: keep the key facts and conclusions; do not rewrite it as a sendable short message."
        case translateID:
            return translateInstruction(
                locale: locale,
                translationTargetLocaleId: translationTargetLocaleId
            )
        case extractTodosID:
            return zh
                ? """
                请从剪贴板中只提取明确的待办事项。每条一行，只要标题，不要编号、不要项目符号、不要解释。最多 20 条。
                若没有任何可执行的待办，只输出 NONE，不要把整段原文当成一条待办。
                若原文本身就是一句短待办（例如「买牛奶」），输出那一句即可。
                """
                : """
                Extract only explicit to-do items from the clipboard. One title per line; no numbering, bullets, or commentary. Maximum 20 lines.
                If there are no actionable tasks, output NONE and nothing else. Do not treat the whole clipboard as one task.
                If the clipboard itself is already one short task (for example "buy milk"), output that single line.
                """
        default:
            return zh
                ? "请根据剪贴板内容完成用户选择的操作。"
                : "Complete the selected action using the clipboard text."
        }
    }

    /// Uses the keyboard translation target when set; otherwise Chinese ↔ English.
    private static func translateInstruction(
        locale: String,
        translationTargetLocaleId: String
    ) -> String {
        let zh = locale == "zh"
        if !TranslationLanguageCatalog.isOff(translationTargetLocaleId) {
            let language = TranslationLanguageCatalog.resolve(translationTargetLocaleId)
            let name = language.promptLanguageName
            return zh
                ? "请将剪贴板内容翻译成\(name)，保留原意与语气。"
                : "Translate the clipboard text into \(name), preserving meaning and tone."
        }
        return zh
            ? "请将剪贴板内容在中文与英文之间互译：若原文主要是中文则译成自然英文，若主要是英文则译成自然中文。保留原意与语气。"
            : "Translate the clipboard between Chinese and English: if it is primarily Chinese, produce natural English; if primarily English, produce natural Chinese. Preserve meaning and tone."
    }
}

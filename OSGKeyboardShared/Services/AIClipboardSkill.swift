// AIClipboardSkill.swift
// OSGKeyboard · Shared
//
// Built-in clipboard actions for AI idle. The catalog is an ordered list so
// Settings can later persist a subset or permutation without changing the view.

import Foundation

public struct AIClipboardSkill: Identifiable, Equatable, Sendable {
    public let id: String
    public let systemImage: String
    /// Keyboard.strings key for the short button title.
    public let titleKey: String

    public init(id: String, systemImage: String, titleKey: String) {
        self.id = id
        self.systemImage = systemImage
        self.titleKey = titleKey
    }
}

public enum AIClipboardSkillCatalog: Sendable {
    public static let replyID = "reply"
    public static let summarizeID = "summarize"
    public static let translateID = "translate"

    /// Default set, in display order. Future skills append here.
    public static let builtIn: [AIClipboardSkill] = [
        AIClipboardSkill(
            id: replyID,
            systemImage: "arrowshape.turn.up.left.fill",
            titleKey: "keyboard.ai.skill.reply"
        ),
        AIClipboardSkill(
            id: summarizeID,
            systemImage: "doc.text.magnifyingglass",
            titleKey: "keyboard.ai.skill.summarize"
        ),
        AIClipboardSkill(
            id: translateID,
            systemImage: "character.bubble.fill",
            titleKey: "keyboard.ai.skill.translate"
        ),
    ]

    /// `enabledIDs` is the future Settings hook: `nil` keeps the built-in list.
    public static func visible(enabledIDs: [String]? = nil) -> [AIClipboardSkill] {
        guard let enabledIDs, !enabledIDs.isEmpty else { return builtIn }
        let byID = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.id, $0) })
        return enabledIDs.compactMap { byID[$0] }
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

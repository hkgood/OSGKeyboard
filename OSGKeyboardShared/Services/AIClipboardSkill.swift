// AIClipboardSkill.swift
// OSGKeyboard · Shared
//
// Built-in clipboard actions for AI idle. The catalog is an ordered list so
// Settings / the Skills tab can persist a subset or permutation without
// changing the view. Transform skills insert into the current field;
// export skills hand off to the host after the model runs (Shortcut, Maps, or Didi).

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
    /// Bundled `.shortcut` resource name without extension. Nil → no file fallback.
    public let shortcutResourceName: String?
    /// User-created skills store display copy here instead of localization keys.
    public let customName: String?
    public let customSummary: String?
    public let customPrompt: String?
    /// Built-in skills are always false. Custom skills default off.
    public let thinkingEnabled: Bool

    /// Reminders, Calendar, and Notes exports need a companion Shortcut.
    /// Navigate and Ride hand off to the host (Maps or Didi). No Shortcut.
    public var requiresShortcut: Bool { kind == .export && shortcutName != nil }
    public var isUserCreated: Bool { id.hasPrefix("user.") }
    /// The server applies the final model policy; this only preserves whether
    /// the user invoked a built-in transform or a custom skill.
    public var managedGatewayTaskKind: ManagedGatewayTaskKind {
        isUserCreated ? .customSkill : .clipboardTransform
    }

    public init(
        id: String,
        systemImage: String,
        titleKey: String,
        cardTitleKey: String,
        descriptionKey: String,
        kind: AIClipboardSkillKind,
        isDefault: Bool,
        shortcutName: String? = nil,
        shortcutICloudURL: URL? = nil,
        shortcutResourceName: String? = nil,
        customName: String? = nil,
        customSummary: String? = nil,
        customPrompt: String? = nil,
        thinkingEnabled: Bool = false
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
        self.shortcutResourceName = shortcutResourceName
        self.customName = customName
        self.customSummary = customSummary
        self.customPrompt = customPrompt
        self.thinkingEnabled = id.hasPrefix("user.") ? thinkingEnabled : false
    }
}

public enum AIClipboardSkillCatalog: Sendable {
    public static let replyID = "reply"
    public static let summarizeID = "summarize"
    public static let translateID = "translate"
    public static let extractTodosID = "extractTodos"
    public static let extractTodosShortcutName = "OSGExtractTodos"
    public static let extractTodosResourceName = "OSGExtractTodos"

    public static let extractEventsID = "extractEvents"
    public static let extractEventsShortcutName = "OSGExtractEvents"
    public static let extractEventsResourceName = "OSGExtractEvents"

    public static let saveToNotesID = "saveToNotes"
    public static let saveToNotesShortcutName = "OSGSaveToNotes"
    public static let saveToNotesResourceName = "OSGSaveToNotes"

    public static let navigateID = "navigate"

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
            shortcutResourceName: extractTodosResourceName
        ),
        AIClipboardSkill(
            id: extractEventsID,
            systemImage: "calendar",
            titleKey: "keyboard.ai.skill.extractEvents",
            cardTitleKey: "skills.extractEvents.name",
            descriptionKey: "skills.extractEvents.description",
            kind: .export,
            isDefault: false,
            shortcutName: extractEventsShortcutName,
            shortcutResourceName: extractEventsResourceName
        ),
        AIClipboardSkill(
            id: saveToNotesID,
            systemImage: "note.text",
            titleKey: "keyboard.ai.skill.saveToNotes",
            cardTitleKey: "skills.saveToNotes.name",
            descriptionKey: "skills.saveToNotes.description",
            kind: .export,
            isDefault: false,
            shortcutName: saveToNotesShortcutName,
            shortcutResourceName: saveToNotesResourceName
        ),
        AIClipboardSkill(
            id: navigateID,
            systemImage: "arrow.triangle.turn.up.right.diamond.fill",
            titleKey: "keyboard.ai.skill.navigate",
            cardTitleKey: "skills.navigate.name",
            descriptionKey: "skills.navigate.description",
            kind: .export,
            isDefault: false
        )
    ]

    /// Legacy alias: the three default transform skills used to be the whole list.
    public static let builtIn: [AIClipboardSkill] = catalog

    public static func all(userCatalog: AIUserSkillCatalog = .empty) -> [AIClipboardSkill] {
        catalog + userCatalog.entries.map { $0.asClipboardSkill() }
    }

    public static func skill(
        id: String,
        userCatalog: AIUserSkillCatalog = .empty
    ) -> AIClipboardSkill? {
        catalog.first { $0.id == id } ?? userCatalog.skill(id: id)?.asClipboardSkill()
    }

    /// `enabledIDs` is the Skills-tab order. `nil` keeps the default three.
    /// An explicit empty array shows no chips (carousel fallback).
    public static func visible(
        enabledIDs: [String]? = nil,
        userCatalog: AIUserSkillCatalog = .empty
    ) -> [AIClipboardSkill] {
        let ids = enabledIDs ?? AIAgentSkillLayout.defaultEnabledIDs
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: all(userCatalog: userCatalog).map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    public static func instruction(
        for skill: AIClipboardSkill,
        locale: String,
        translationTargetLocaleId: String,
        now: Date = Date()
    ) -> String {
        if let custom = skill.customPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return instruction(
            skillID: skill.id,
            locale: locale,
            translationTargetLocaleId: translationTargetLocaleId,
            now: now
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
        translationTargetLocaleId: String,
        now: Date = Date()
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
        case extractEventsID:
            return eventInstruction(zh: zh, now: now)
        case saveToNotesID:
            return noteInstruction(zh: zh, now: now)
        case navigateID:
            return navigateInstruction(zh: zh)
        default:
            return zh
                ? "请根据剪贴板内容完成用户选择的操作。"
                : "Complete the selected action using the clipboard text."
        }
    }

    /// Title only. The original clipboard is the note body; do not ask the
    /// model to rewrite it.
    private static func noteInstruction(zh: Bool, now: Date) -> String {
        let clock = clockContext(now: now, zh: zh)
        if zh {
            return """
            \(clock)
            请根据剪贴板正文写一个简短备忘录标题。只要一行标题，不要输出正文，不要编号、不要引号、不要解释。标题中不要出现换行或 |。最多 40 个字。
            标题应能让人在列表里认出这篇笔记，可结合今天的日期或时间（例如「8月13日周会纪要」）。不要改写或重复正文。
            即使原文很短也要给一个标题。不要输出 NONE。
            """
        }
        return """
        \(clock)
        Write a short Notes title from the clipboard. One line only; do not output the body. No numbering, quotes, or commentary. No newlines or | in the title. Maximum 40 characters.
        The title should identify the note in a list and may include today's date or time (for example "13 Aug standup notes"). Do not rewrite or repeat the body.
        Always return a title, even when the clipboard is short. Do not output NONE.
        """
    }

    private static func navigateInstruction(zh: Bool) -> String {
        if zh {
            return """
            请从剪贴板提取明确的地点用于导航。只输出一行，两段用 | 分隔：起点|终点
            从当前位置出发则起点留空，但保留竖线，例如 |朝阳区酒仙桥路10号
            两点都写了则两侧都填，例如 北京南站|三里屯太古里
            可以是完整地址或常用地名。不要编号、不要解释、不要多行、不要链接。
            若有多条地址，只输出最明确的一条。
            没有可导航的地点时，只输出 NONE。不要把整段原文当成一个地点。
            """
        }
        return """
        Extract one place for turn-by-turn navigation from the clipboard. One line, two fields separated by | : origin|destination
        Leave origin empty when starting from the current location, but keep the pipe, for example |10 Jiuxianqiao Road
        Fill both sides when the source names two places, for example Beijing South|Sanlitun Taikoo Li
        A full address or a well-known place name is fine. No numbering, commentary, extra lines, or URLs.
        If there are several addresses, output only the clearest one.
        If there is no navigable place, output NONE and nothing else. Do not treat the whole clipboard as one place.
        """
    }

    /// Clock context so relative phrases (tomorrow, 3pm) resolve to local time.
    private static func eventInstruction(zh: Bool, now: Date) -> String {
        let clock = clockContext(now: now, zh: zh)
        if zh {
            return """
            \(clock)
            请从剪贴板提取明确的日程。每条一行，四段用 | 分隔：开始|结束|标题|地点
            开始有钟点用 YYYY-MM-DD HH:mm；只有日期（全天）用 YYYY-MM-DD。没有结束时间或地点则该段留空，但保留竖线。标题中不要出现 |。最多 20 条。不要编号、不要解释。
            只有时刻、没有日期时，使用今天的日期。日期和时间都没有的条目不要输出。
            原文写了结束时间就填写结束段，否则留空（后续按 1 小时处理）。原文有地点就填写地点段。
            若没有任何带日期或时间的日程，只输出 NONE，不要把整段原文当成一条日程。
            """
        }
        return """
        \(clock)
        Extract explicit calendar events from the clipboard. One event per line, four fields separated by | : start|end|title|location
        Timed start uses YYYY-MM-DD HH:mm; date-only (all-day) uses YYYY-MM-DD. Leave end or location empty when unknown, but keep the pipes. Do not put | in the title. Maximum 20 lines. No numbering or commentary.
        Time without a date uses today. Skip items that have neither a date nor a time.
        Fill the end field when the source gives an end time; otherwise leave it empty (treated as 1 hour). Fill location when the source names a place.
        If there are no events with a date or time, output NONE and nothing else. Do not treat the whole clipboard as one event.
        """
    }

    private static func clockContext(now: Date, zh: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: zh ? "zh_CN" : "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = zh ? "yyyy年M月d日EEEE HH:mm" : "EEEE, d MMMM yyyy, HH:mm"
        let stamp = formatter.string(from: now)
        return zh
            ? "现在是\(stamp)（设备本地时区）。"
            : "It is now \(stamp) (device local timezone)."
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

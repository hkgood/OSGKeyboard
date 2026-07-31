// PolishStylePolicy.swift
// OSGKeyboard · Shared
//
// Runtime-only policy metadata for style packs. The policy is deliberately
// separate from persisted user packs so older synced data keeps decoding.

import Foundation

public enum PolishRewriteMode: String, Sendable {
    case practical
    case transformative
}

public enum StructurePolicy: String, Sendable {
    case never
    case onlyExplicit
    case encouraged
}

public enum PunctuationStyle: String, Sendable {
    case full
    case light
    case minimal
}

public struct PolishStylePolicy: Sendable, Equatable {
    public let mode: PolishRewriteMode
    public let lengthRatio: ClosedRange<Double>
    public let structure: StructurePolicy
    public let punctuation: PunctuationStyle

    public init(
        mode: PolishRewriteMode,
        lengthRatio: ClosedRange<Double>,
        structure: StructurePolicy,
        punctuation: PunctuationStyle
    ) {
        self.mode = mode
        self.lengthRatio = lengthRatio
        self.structure = structure
        self.punctuation = punctuation
    }
}

public enum PolishStylePolicyResolver {
    public static func policy(for style: PolishStylePack) -> PolishStylePolicy {
        switch style.id {
        case "builtin.chat":
            return .init(mode: .practical, lengthRatio: 0.85...1.10, structure: .never, punctuation: .light)
        case "builtin.structured":
            return .init(mode: .practical, lengthRatio: 0.85...1.35, structure: .encouraged, punctuation: .full)
        case "builtin.formal":
            return .init(mode: .practical, lengthRatio: 0.85...1.25, structure: .onlyExplicit, punctuation: .full)
        case "builtin.dating", "builtin.flex", "builtin.corp", "builtin.diba":
            return .init(mode: .transformative, lengthRatio: 0.70...1.60, structure: .never, punctuation: .light)
        case "builtin.xhs":
            return .init(mode: .transformative, lengthRatio: 0.80...1.80, structure: .encouraged, punctuation: .light)
        case "builtin.light":
            return .init(mode: .practical, lengthRatio: 0.80...1.20, structure: .onlyExplicit, punctuation: .full)
        default:
            return .init(mode: .transformative, lengthRatio: 0.70...1.60, structure: .onlyExplicit, punctuation: .full)
        }
    }

    public static func styleCard(
        for style: PolishStylePack,
        useChineseGuidance: Bool
    ) -> String {
        guard style.kind == .builtin else {
            return useChineseGuidance
                ? customChineseCard(prompt: style.prompt)
                : customEnglishCard(prompt: style.prompt)
        }
        return useChineseGuidance
            ? chineseBuiltinCard(id: style.id)
            : englishBuiltinCard(id: style.id)
    }

    private static func chineseBuiltinCard(id: String) -> String {
        switch id {
        case "builtin.structured":
            return """
            # 风格卡：清晰结构
            用最小必要改写提高扫读性。多个独立事项可分项，连续叙述不要硬拆列表；不得改变执行顺序。
            禁止添加标题、总结、建议或用户没说过的责任结论。
            示例：输入「有三件事第一点修登录第二点发版本第三点通知客服」
            输出「有三件事：\n1. 修复登录\n2. 发布版本\n3. 通知客服」
            """
        case "builtin.formal":
            return """
            # 风格卡：正式表达
            职业、清楚但不僵硬，去掉口头噪声；只在原文明确列举时使用列表。
            禁止增加称呼、落款、寒暄、空洞管理术语或「希望能帮到你」类套话。
            """
        case "builtin.chat":
            return """
            # 风格卡：日常聊天
            像用户本人发出的即时消息：口语、简短、保留随意感。不要列表、不要分段、不要变正式。
            保留有语气作用的「吧、呢、啦、哈哈」；不要增加称呼、笑点、建议或第二句话。
            示例：输入「我觉得吧首先这个价格不合适其次时间也太赶了」
            输出「我觉得吧，首先这个价格不合适，其次时间也太赶了。」
            """
        case "builtin.dating":
            return """
            # 风格卡：直男癌拯救器（趣味改写）
            在意图和事实不变的前提下，让恋爱聊天更自然、好接、有一点态度；允许整句重写。
            禁止编造共同经历、关系承诺和对方说过的话；问句仍由用户向对方提出。
            """
        case "builtin.flex":
            return """
            # 风格卡：装逼指南（趣味改写）
            改成简短可发送的中英混合戏仿，英文只作少量调味；力度决定装感浓度。
            禁止编造品牌、资产、经历，不要写成广告或英文长句。
            """
        case "builtin.corp":
            return """
            # 风格卡：大厂黑话（趣味改写）
            改成自然会议口语，可少量使用对齐、同步、owner、闭环等表达。
            禁止堆砌黑话、编造责任人、威胁或事实，不要扩成 PPT 小作文。
            """
        case "builtin.diba":
            return """
            # 风格卡：帝吧大神（趣味改写）
            在已有反驳意图上增强冷幽默和拆前提力度，保持 1–3 个短句。
            禁止新增攻击对象、脏话、群体攻击或用户没有表达的观点。
            """
        case "builtin.xhs":
            return """
            # 风格卡：小红书集美（趣味改写）
            改成亲切、有节奏、短段落的笔记正文；原文有多个要点时可结构化。
            禁止编造体验、功效、数字、受众和前后对比；不要自动添加话题标签或 emoji。
            """
        default:
            return """
            # 风格卡：轻度清理
            只做准确、通顺、可直接发送所需的最小改动。原句清楚时只补标点。
            仅在原文明示列举时使用列表；禁止扩写、总结、换人格或加入书面套话。
            """
        }
    }

    private static func englishBuiltinCard(id: String) -> String {
        switch id {
        case "builtin.structured":
            return """
            # Style card: Clear Structure
            Improve scanability with the smallest necessary rewrite. List genuinely separate items, but keep a continuous narrative as prose and preserve execution order.
            Never add headings, summaries, advice, or responsibility claims.
            Example: input "three things first fix login second ship the release third notify support"
            output "Three things:\n1. Fix login\n2. Ship the release\n3. Notify support"
            """
        case "builtin.formal":
            return """
            # Style card: Formal
            Be professional and clear without sounding stiff. Remove speech noise; use lists only for explicit enumeration.
            Never invent greetings, sign-offs, pleasantries, management jargon, or generic helper phrases.
            """
        case "builtin.chat":
            return """
            # Style card: Daily Chat
            Write a short, casual instant message in the user's own voice. Never turn it into a list, paragraphs, or formal prose.
            Preserve meaningful hesitation and tone words. Do not add a greeting, joke, advice, or a second sentence.
            """
        case "builtin.dating":
            return """
            # Style card: Dating Coach (transformative)
            While preserving intent and facts, make dating chat natural, engaging, and lightly playful; a full-sentence rewrite is allowed.
            Never invent shared history, commitments, or the other person's words. A question must remain the user's question.
            """
        case "builtin.flex":
            return """
            # Style card: Flex Guide (transformative)
            Produce a short, sendable parody with sparse Chinese-English code switching when the input is Chinese; intensity controls the flex.
            Never invent brands, possessions, or experiences, and do not write ad copy or long English passages.
            """
        case "builtin.corp":
            return """
            # Style card: Corp Speak (transformative)
            Use concise spoken workplace language with a small amount of natural corporate shorthand.
            Never dump jargon, invent owners or facts, make threats, or expand into a presentation.
            """
        case "builtin.diba":
            return """
            # Style card: DiBa Logic (transformative)
            Strengthen an existing rebuttal with cool premise-breaking humor in one to three short sentences.
            Never add a target, profanity, group attack, or an opinion the user did not express.
            """
        case "builtin.xhs":
            return """
            # Style card: Xiaohongshu (transformative)
            Produce a friendly, rhythmic note body with short paragraphs; structure multiple genuine points when useful.
            Never invent experiences, efficacy, numbers, an audience, or before-and-after claims. Do not add hashtags or emojis.
            """
        default:
            return """
            # Style card: Light Clean
            Make only the minimum changes needed for accuracy, fluency, and direct use. If the draft is already clear, add punctuation only.
            Use a list only for explicit enumeration. Never expand, summarize, change persona, or add formal filler.
            """
        }
    }

    private static func customChineseCard(prompt: String) -> String {
        """
        # 用户自定义风格（低于核心事实与安全规则）
        \(prompt)
        """
    }

    private static func customEnglishCard(prompt: String) -> String {
        """
        # User custom style (lower priority than core factual and safety rules)
        \(prompt)
        """
    }
}

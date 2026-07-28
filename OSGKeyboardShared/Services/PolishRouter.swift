// PolishRouter.swift
// OSGKeyboard · Shared
//
// Pre-LLM routing for polish: information-density gate (A), prompt
// hard-brake blocks (B), and style-specific degradation (E). Keeps a
// single LLM round-trip — decisions are local and zero-latency.

import Foundation

/// How aggressively the polish prompt may rewrite this utterance.
public enum PolishRoutingMode: String, Sendable, Equatable {
    /// Normal style + intensity.
    case full
    /// Sparse input: force Light and forbid style theater / invented facts.
    case conservative
    /// Fun style cannot run (e.g. DiBa with no opponent quote) → chat cleanup.
    case chatFallback
}

/// Result of ABE routing for one polish request.
public struct PolishRouteDecision: Sendable, Equatable {
    public let mode: PolishRoutingMode
    public let effectiveStyleID: String
    public let effectiveIntensity: PolishIntensity
    public let reasons: [String]

    public init(
        mode: PolishRoutingMode,
        effectiveStyleID: String,
        effectiveIntensity: PolishIntensity,
        reasons: [String]
    ) {
        self.mode = mode
        self.effectiveStyleID = effectiveStyleID
        self.effectiveIntensity = effectiveIntensity
        self.reasons = reasons
    }
}

public enum PolishRouter {

    /// Decide polish mode / intensity / style remapping before prompt assembly.
    public static func decide(
        text: String,
        styleID: String,
        intensity: PolishIntensity
    ) -> PolishRouteDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var reasons: [String] = []
        let sparse = isInformationSparse(trimmed)

        // Practical non-chat styles keep full routing; chat still gets
        // sparse → conservative so it cannot invent interlocutor replies.
        if styleID == "builtin.chat" {
            if sparse {
                reasons.append("A:sparse")
                reasons.append("E:chat_no_reply")
                return PolishRouteDecision(
                    mode: .conservative,
                    effectiveStyleID: styleID,
                    effectiveIntensity: .light,
                    reasons: reasons
                )
            }
            return PolishRouteDecision(
                mode: .full,
                effectiveStyleID: styleID,
                effectiveIntensity: intensity,
                reasons: ["pass"]
            )
        }

        if styleID == "builtin.light"
            || styleID == "builtin.structured"
            || styleID == "builtin.formal" {
            return PolishRouteDecision(
                mode: .full,
                effectiveStyleID: styleID,
                effectiveIntensity: intensity,
                reasons: ["practical_full"]
            )
        }

        if sparse {
            reasons.append("A:sparse")
        }

        // E: DiBa without an opponent claim → chat cleanup.
        if styleID == "builtin.diba", !hasOpponentQuote(trimmed) {
            reasons.append("E:diba_no_opponent")
            return PolishRouteDecision(
                mode: .chatFallback,
                effectiveStyleID: "builtin.chat",
                effectiveIntensity: .light,
                reasons: reasons
            )
        }

        // E: note / flirt / buzzword styles with hollow short input.
        if sparse {
            switch styleID {
            case "builtin.xhs" where !hasConcreteEntity(trimmed):
                reasons.append("E:xhs_no_topic")
            case "builtin.dating":
                reasons.append("E:dating_short_no_flirt")
            case "builtin.corp" where !hasConcreteEntity(trimmed),
                 "builtin.flex" where !hasConcreteEntity(trimmed):
                let shortName = styleID.replacingOccurrences(of: "builtin.", with: "")
                reasons.append("E:\(shortName)_no_subject")
            default:
                break
            }
            return PolishRouteDecision(
                mode: .conservative,
                effectiveStyleID: styleID,
                effectiveIntensity: .light,
                reasons: reasons
            )
        }

        return PolishRouteDecision(
            mode: .full,
            effectiveStyleID: styleID,
            effectiveIntensity: intensity,
            reasons: reasons.isEmpty ? ["pass"] : reasons
        )
    }

    /// Prompt block injected after intensity / before the global contract.
    public static func promptBlock(
        mode: PolishRoutingMode,
        styleID: String,
        useChineseGuidance: Bool
    ) -> String {
        var parts: [String] = []

        if PolishStylePackCatalog.isFunPersonality(id: styleID)
            || styleID == "builtin.chat" {
            parts.append(sparseHardBrake(useChineseGuidance: useChineseGuidance))
            parts.append(antiExampleBlock(useChineseGuidance: useChineseGuidance))
        }

        if styleID == "builtin.chat" {
            parts.append(chatNoReplyBlock(useChineseGuidance: useChineseGuidance))
        }

        switch styleID {
        case "builtin.xhs":
            parts.append(xhsDegradeBlock(useChineseGuidance: useChineseGuidance))
        case "builtin.dating":
            parts.append(datingDegradeBlock(useChineseGuidance: useChineseGuidance))
        case "builtin.diba":
            parts.append(dibaDegradeBlock(useChineseGuidance: useChineseGuidance))
        case "builtin.corp":
            parts.append(corpDegradeBlock(useChineseGuidance: useChineseGuidance))
        case "builtin.flex":
            parts.append(flexDegradeBlock(useChineseGuidance: useChineseGuidance))
        default:
            break
        }

        switch mode {
        case .conservative:
            parts.append(conservativeModeBlock(useChineseGuidance: useChineseGuidance))
        case .chatFallback:
            parts.append(chatFallbackModeBlock(useChineseGuidance: useChineseGuidance))
        case .full:
            break
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Density signals

    public static func isInformationSparse(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        // Questions / invites / reply-shaped lines are not "empty" — keep full polish.
        if hasOpponentQuote(trimmed) || hasCommunicativeSignal(trimmed) {
            return false
        }
        let cjk = cjkCount(trimmed)
        if cjk > 0 {
            if cjk <= 4 { return true }
            if cjk <= 10, !hasConcreteEntity(trimmed) {
                return true
            }
            if cjk <= 12, !hasConcreteEntity(trimmed) {
                let stripped = stripHollowTokens(trimmed)
                if cjkCount(stripped) <= 4 { return true }
            }
            return false
        }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count <= 3 && trimmed.count <= 16
    }

    public static func hasOpponentQuote(_ text: String) -> Bool {
        let markers = ["回他", "回她", "对方", "他说", "她说", "你说的", "你这叫", "大家都"]
        return markers.contains { text.contains($0) }
    }

    public static func hasConcreteEntity(_ text: String) -> Bool {
        let entities = [
            "面膜", "防晒", "口红", "粉底", "洗发", "咖啡", "火锅", "酒店", "餐厅",
            "方案", "接口", "测试", "Key", "老板", "电影", "地铁", "快递", "会议",
            "周报", "加班", "机票", "医院", "课程", "健身", "外卖", "微信", "项目",
            "发布", "文档", "密码", "充电器", "门卡",
        ]
        return entities.contains { text.contains($0) }
    }

    public static func hasCommunicativeSignal(_ text: String) -> Bool {
        if text.contains("？") || text.contains("?") { return true }
        let patterns = [
            #"吗|么|怎么|什么|哪|谁|为何|为什么|为啥"#,
            #"能不能|可不可以|要不要|行不行"#,
            #"回他|回她"#,
            #"约|见面|吃饭|电影"#,
        ]
        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Prompt fragments

    private static func sparseHardBrake(useChineseGuidance: Bool) -> String {
        if useChineseGuidance {
            return """
            # 信息不足时的硬刹车（优先级高于出味与力度跳变）
            若原文信息密度不足（极短、缺对象/主题、只有评价或情绪词、无可改写的事实核）：
            1. 只做口头禅清理与标点恢复，输出长度贴近原文（±30% 以内）。
            2. 禁止钩子开头、分段小作文、评论区互动、亲测细节、暧昧加戏、虚构对手论点或会议流程。
            3. 宁可「不够味」也不可「编故事」；此时忽略 Light/Medium/Heavy 的跳变要求。
            """
        }
        return """
        # Sparse-input hard brake (outranks style flavor and intensity jumps)
        When the transcript is information-sparse (very short, no topic/object, only evaluation/mood words):
        1. Only clean fillers and restore punctuation; keep length within ±30% of the original.
        2. Do not invent hooks, essays, CTAs, lived-experience details, flirtation, opponent claims, or meeting workflows.
        3. Prefer under-flavored over fabricated; ignore Light/Medium/Heavy jump requirements in this case.
        """
    }

    private static func antiExampleBlock(useChineseGuidance: Bool) -> String {
        if useChineseGuidance {
            return """
            # 反例（禁止）
            - 「香香的」✘→ 编闺蜜安利、喷手腕、同事问香水
            - 「踩坑了」✘→ 编博主种草与性价比剧情
            - 「还行」✘→ 扩成暧昧句或闭环会议发言
            - 「嗯」/「没事」✘→「我在呢」「那就好」（禁止接话续写）
            """
        }
        return """
        # Counterexamples (forbidden)
        - "smells nice" ✘→ invent friend recommendations or usage scenes
        - "got burned" ✘→ invent influencer / value narratives
        - "fine" ✘→ expand into flirtation or meeting jargon
        - "mm" / "it's fine" ✘→ invent interlocutor replies
        """
    }

    private static func chatNoReplyBlock(useChineseGuidance: Bool) -> String {
        if useChineseGuidance {
            return """
            # 日常聊天专属：禁止接话
            输入是用户要发出的消息草稿，不是对方发来的消息。
            不要以聊天对象身份接话、附和、安慰或反问。
            极短确认/状态词：近原样输出，禁止续写第二句。
            """
        }
        return """
        # Daily chat: no interlocutor replies
        Input is the user's outbound draft, not a message from someone else.
        Do not answer, affirm, comfort, or ask follow-ups as the other party.
        Ultra-short confirmations/status words: stay near-verbatim; never add a second invented sentence.
        """
    }

    private static func xhsDegradeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "# 小红书专属降级\n无明确主题/产品/对象时：禁止笔记结构、CTA 与「姐妹们/集美们」堆砌；禁止从示例抄入原文没有的细节。"
            : "# RED Note degrade\nWithout a clear topic/product/object: no note structure, CTA, or sisterly openers; do not copy example-only details."
    }

    private static func datingDegradeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "# 直男癌专属降级\n极短关心/评价/确认：禁止暧昧、挑逗、欲擒故纵；本条优先于「原文很干也要完整发挥」。"
            : "# Dating degrade\nUltra-short care/praise/acks: no flirtation or push-pull; this outranks “rewrite dry input fully”."
    }

    private static func dibaDegradeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "# 帝吧专属降级\n检测不到对方原话或可拆论点时：禁止拆前提与高级黑模板；只做最短清理。"
            : "# DiBa degrade\nWithout an opponent claim: no premise-breaking templates; shortest cleanup only."
    }

    private static func corpDegradeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "# 大厂黑话专属降级\n无事项主语时：禁止发明 owner/交界面/闭环指令；最多一个黑话点缀或短清理。"
            : "# Corp degrade\nWithout a concrete matter: do not invent owners/interfaces/闭环 directives; at most one buzzword or short cleanup."
    }

    private static func flexDegradeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "# 装逼指南专属降级\n无评价对象时：禁止整句英文与虚构品牌；最多一个英文词或短清理。"
            : "# Flex degrade\nWithout an evaluation target: no full-English dumps or invented brands; at most one English seasoning word."
    }

    private static func conservativeModeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "## 本次模式：保守清理\n输入已判定信息不足。忽略风格出味与力度跳变。只输出贴近原文的短句（±30%），禁止扩写与接话。"
            : "## Mode: conservative cleanup\nInput is information-sparse. Ignore style flavor and intensity jumps. Output a near-original short line (±30%); no expansion or interlocutor replies."
    }

    private static func chatFallbackModeBlock(useChineseGuidance: Bool) -> String {
        useChineseGuidance
            ? "## 本次模式：降级为日常清理\n原趣味风格不适用（例如帝吧无对方原话）。按日常聊天最短清理输出，禁止接话续写。"
            : "## Mode: fall back to daily-chat cleanup\nThe fun style does not apply (e.g. DiBa without an opponent quote). Shortest daily-chat cleanup only; no invented replies."
    }

    // MARK: - Helpers

    private static func cjkCount(_ text: String) -> Int {
        text.unicodeScalars.filter(isCJKScalar).count
    }

    private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static let hollowTokens = [
        "怎么说呢", "就是说", "然后那个", "嗯那个", "那个", "一下", "感觉",
        "嗯", "呃", "啊", "吧", "呢", "的", "了", "这个",
    ]

    private static func stripHollowTokens(_ text: String) -> String {
        var result = text
        for token in hollowTokens.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

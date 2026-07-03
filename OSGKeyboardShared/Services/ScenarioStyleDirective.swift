// ScenarioStyleDirective.swift
// OSGKeyboard · Shared
//
// Shared output-format rules for each polish scenario. Injected into
// both `ScenarioPrompt` (polish-only) and `TranslationPrompt`
// (translate-and-polish) so the two pipelines stay aligned.
//
// Directives emphasize STRUCTURE (bullets, paragraphs, checklists)
// over tone adjectives — structure is what users notice on short ASR
// transcripts.

import Foundation

public enum ScenarioStyleDirective {

    /// Format rules for the given scenario, written in the provider's
    /// primary instruction language (Chinese-native vs English-native).
    public static func make(
        scenarioId: String,
        providerId: String,
        uiLanguage: AppUILanguage? = nil
    ) -> String {
        let id = PolishScenarioCatalog.resolve(scenarioId).id
        let lang = uiLanguage ?? AppGroupStore().uiLanguage
        let isChineseNative = ["zhipu", "moonshot", "qwen", "deepseek"].contains(providerId)
        return isChineseNative
            ? chinese(id: id, uiLanguage: lang)
            : english(id: id, uiLanguage: lang)
    }

    // MARK: - Chinese directives

    private static func chinese(id: String, uiLanguage: AppUILanguage) -> String {
        let englishPlatformNames = uiLanguage.resolvedLanguageCode() != "zh-Hans"
        switch id {
        case "work":
            return """
            场景:工作沟通(邮件、钉钉、Slack)。
            格式(必须):
            - 若有 2 个及以上独立事项/请求/问题,必须用 markdown「- 」列表,每条一行;禁止揉进一段。
            - 仅 1 件事:可用 1～2 句短段落;必要时「称呼 + 正文」。
            - 每条 action 清晰;称呼得体;不过度敬语。
            允许:为列表组织内容,不必强行压成单句。
            禁止:把多项内容合并成一个长句或一整段散文。
            """
        case "todo":
            return """
            场景:TODO/备忘清单。
            格式(必须):
            - 输出必须是 markdown「- 」列表,每条一行。
            - 每条以动词开头;一条一事;不写称呼、不写解释、不扩写。
            禁止:段落 prose、寒暄、背景说明。
            """
        case "social_lifestyle":
            if englishPlatformNames {
                return """
                场景:社交网络生活分享帖(Social Network)。
                格式:
                - 内容≥2 句时必须用空行分段;第一人称;可读性强。
                - 可适度 emoji;不写广告腔;不编造体验。
                """
            }
            return """
            场景:小红书生活分享帖。
            格式:
            - 内容≥2 句时必须用空行分段;第一人称;可读性强。
            - 可适度 emoji 与语气词;不写广告腔;不编造体验。
            """
        case "social_short":
            if englishPlatformNames {
                return """
                场景:Instagram 短 caption。
                格式:句子短、开头抓人、信息密度高;控制总长度;不臆测标签或热点。
                """
            }
            return """
            场景:微博短帖。
            格式:句子短、开头抓人、信息密度高;控制总长度;不臆测标签或热点。
            """
        case "goofy":
            return """
            场景:轻松聊天(逗比风格)。
            格式:自然短句;措辞略俏皮。
            禁止:新增情节、编段子、捏造态度;严肃内容(请假/道歉/投诉)不要强行搞笑。
            """
        case "document":
            return """
            场景:文档/长文笔记。
            格式:
            - 完整句;≥2 个主题时用空行分段。
            - 枚举或步骤用 markdown「- 」列表;可用 `##` 小标题(仅当内容够长)。
            - 少网络用语;比工作沟通更适合长文叙述。
            """
        case "daily_chat", PolishScenarioCatalog.customId:
            fallthrough
        default:
            return """
            场景:日常聊天(IM/私聊)。
            格式:自然短句,像真人发消息;标点轻松;可保留极少量口语感。
            禁止:公文腔、报告体、强行列表(除非口述本身在枚举)。
            """
        }
    }

    // MARK: - English directives

    private static func english(id: String, uiLanguage: AppUILanguage) -> String {
        let englishPlatformNames = uiLanguage.resolvedLanguageCode() != "zh-Hans"
        switch id {
        case "work":
            return """
            Scenario: workplace message (email, Slack, Teams).
            Format (required):
            - If there are 2+ distinct items/requests/questions, you MUST use markdown "- " bullets, one per line; never merge into one paragraph.
            - Single item only: 1–2 short sentences; optional greeting + body.
            - Clear action per item; polite but not overly formal.
            Allowed: list layout instead of forcing a single dense paragraph.
            Forbidden: cramming multiple points into one long sentence or prose block.
            """
        case "todo":
            return """
            Scenario: TODO / checklist note.
            Format (required):
            - Output MUST be markdown "- " bullets, one item per line.
            - Each line starts with a verb; one task per line; no greeting, no explanation.
            Forbidden: prose paragraphs, filler, background context.
            """
        case "social_lifestyle":
            if englishPlatformNames {
                return """
                Scenario: social network lifestyle post.
                Format: if ≥2 sentences, separate paragraphs with blank lines; first person; light emoji ok; no ad-speak; do not invent experiences.
                """
            }
            return """
            Scenario: Xiaohongshu-style lifestyle share.
            Format: if ≥2 sentences, separate paragraphs with blank lines; first person; light emoji ok; no ad-speak; do not invent experiences.
            """
        case "social_short":
            if englishPlatformNames {
                return """
                Scenario: short Instagram caption.
                Format: concise, punchy opening; high density; keep brief; no invented hashtags or trends.
                """
            }
            return """
            Scenario: Weibo-style short post.
            Format: concise, punchy opening; high density; keep brief; no invented hashtags or trends.
            """
        case "goofy":
            return """
            Scenario: playful chat (goofy tone).
            Format: natural short sentences; slightly witty wording only.
            Forbidden: new facts, invented jokes, forced humor on serious topics (leave/apology/complaint).
            """
        case "document":
            return """
            Scenario: document / long-form notes.
            Format: complete sentences; blank lines between topics when ≥2 themes; use "- " bullets for steps/enumerations; `##` headings only when content is long enough; minimal slang.
            """
        case "daily_chat", PolishScenarioCatalog.customId:
            fallthrough
        default:
            return """
            Scenario: everyday chat (IM/DM).
            Format: natural short sentences like texting; relaxed punctuation; very light colloquial tone ok.
            Forbidden: memo/report tone; forced bullets unless the speaker is enumerating.
            """
        }
    }
}

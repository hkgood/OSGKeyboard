// TranslationPrompt.swift
// OSGKeyboard · Shared
//
// Builds the system prompt the LLM sees when the user has the
// translation toggle on. Re-uses the same per-provider "primary
// language" split as `PolishingService.buildPrompt` so Chinese-native
// LLMs get a Chinese prompt and English-native LLMs get an English one.
//
// The "translate AND polish" blend is intentional: ASR transcripts are
// noisy, so the prompt asks the model to clean the noise while translating.
// Style follows the auto-detected `AppContext` (same as the polish path).
// Structure (paragraphs / lists) is an explicit contract with few-shot
// examples: abstract rules alone are not enough for models that flatten
// multi-point ASR into one paragraph.

import Foundation

public enum TranslationPrompt {

    /// Build the translate-and-polish system prompt.
    public static func make(
        target: TranslationLanguage,
        providerId: String,
        appContext: AppContext = .unknown,
        sourceText: String = ""
    ) -> String {
        let useChinese = PolishingService.shouldUseChineseGuidance(
            inputText: sourceText,
            providerId: providerId
        )
        let contextGuideline = appContext.translationGuideline
        return useChinese
            ? chinesePrompt(target: target, contextGuideline: contextGuideline)
            : englishPrompt(target: target, contextGuideline: contextGuideline)
    }

    // MARK: - Chinese prompt (for DeepSeek / Qwen / GLM / Moonshot)

    private static func chinesePrompt(target: TranslationLanguage, contextGuideline: String) -> String {
        """
        你是一位语音输入翻译与润色助手。用户用 ASR 转写了一段可能含噪声的口述:
        1) 先识别原话的主要语言(若不确定则按用户给定的方向处理);
        2) 将内容翻译为「\(target.promptLanguageName)」,保留原意,不增删事实、不臆测;
        3) 顺带修复 ASR 噪声(同音错字、漏字、断句错乱),让译文读起来自然;
        4) 去掉无意义的口头禅(嗯、啊、那个);篇幅不超过原文约 1.5 倍——简洁是去噪声,不是压平结构;
        5) 结构硬规则(与意思同等重要,必须遵守):
           - 输入若已有空行、换行或列表,译文必须对应保留;禁止把多段合成一段;
           - 输入几乎无换行、但出现「第N点/首先/其次/三件事」等列举信号,或有多个独立要点时:
             · 用空行分段;
             · 列举必须用行首编号列表「1. 2. 3.」(或目标语等价写法),禁止写成同一段里的 First,/Second,/Third,;
             · 禁止把整段输出成没有换行的单段;
           - 短文本或单一意图保持一段,不为好看硬换行;
        6) 只输出译文正文,不要解释、不要加引号、不要前缀"以下是翻译"。

        # 示例(格式必须像「正确」,不要像「错误」)
        输入(平铺 ASR): 嗯那个今天开会说了三件事第一点是修登录崩溃第二点加冒烟测试第三点通知客服另外周一十点再同步
        错误(禁止): Today's meeting covered three things. First, fix the login crash. Second, add smoke tests. Third, notify support. Also sync Monday at 10.
        正确:
        Today's meeting covered three items:

        1. Fix the login crash.
        2. Add smoke tests.
        3. Notify support.

        Also, sync again Monday at 10.

        输入(已有分段):
        今天有两件事。

        第一点是发版。

        第二点是写纪要。
        正确:
        There are two items today.

        1. Ship the release.
        2. Write the meeting notes.

        输入(短句): 好的收到
        正确: Okay, got it.

        当前输入场景：\(contextGuideline)
        """
    }

    // MARK: - English prompt (for OpenAI / OpenAI-compatible non-Chinese)

    private static func englishPrompt(target: TranslationLanguage, contextGuideline: String) -> String {
        """
        You are a voice-input translation and polishing assistant. The user has spoken informally and the transcript may contain ASR noise:
        1) Identify the input language; if unclear, assume the user wants translation INTO \(target.promptLanguageName);
        2) Translate the content INTO \(target.promptLanguageName), preserving meaning; do not invent facts or omit content;
        3) Fix ASR noise (homophone errors, missing characters, broken segmentation) so the translation reads naturally;
        4) Drop filler words (um, uh, like); stay within ~1.5x spoken length — concise means remove noise, not flatten structure;
        5) Hard structure rules (as important as meaning; must follow):
           - If the input already has blank lines, line breaks, or lists, preserve that structure; never merge multiple paragraphs into one;
           - If the input is nearly unbroken but has enumeration cues ("first/second", "three things", "point one") or multiple independent points:
             · split with blank lines;
             · use a leading numbered list "1. 2. 3." (or target-language equivalent); do NOT write First,/Second,/Third, inside one paragraph;
             · never output the whole result as a single newline-free block;
           - Keep short or single-intent text in one paragraph; do not add decorative breaks;
        6) Output ONLY the translation. No quotes, no preamble, no explanation.

        # Examples (match CORRECT format; never match WRONG)
        Input (flat ASR): um today meeting three things first fix login crash second add smoke tests third notify support also sync Monday at ten
        WRONG: Today's meeting covered three things. First, fix the login crash. Second, add smoke tests. Third, notify support. Also sync Monday at 10.
        CORRECT:
        Today's meeting covered three items:

        1. Fix the login crash.
        2. Add smoke tests.
        3. Notify support.

        Also, sync again Monday at 10.

        Input (already paragraphed):
        Two things today.

        First, ship the release.

        Second, write the notes.
        CORRECT:
        Two things today.

        1. Ship the release.
        2. Write the notes.

        Input (short): okay got it
        CORRECT: Okay, got it.

        Current input context: \(contextGuideline)
        """
    }
}

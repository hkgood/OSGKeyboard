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

import Foundation

public enum TranslationPrompt {

    /// Build the translate-and-polish system prompt.
    public static func make(
        target: TranslationLanguage,
        providerId: String,
        appContext: AppContext = .unknown
    ) -> String {
        let isChineseNative = ["zhipu", "moonshot", "qwen", "deepseek"].contains(providerId)
        let contextGuideline = appContext.polishGuideline
        return isChineseNative
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
        4) 简洁;不超过原文 1.5 倍;去掉无意义的口头禅(嗯、啊、那个);
        5) 只输出译文正文,不要解释、不要加引号、不要前缀"以下是翻译"。

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
        4) Stay concise; do not exceed 1.5x the spoken length; drop filler words (um, uh, like);
        5) Output ONLY the translation. No quotes, no preamble, no explanation.

        Current input context: \(contextGuideline)
        """
    }
}

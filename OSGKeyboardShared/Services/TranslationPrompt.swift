// TranslationPrompt.swift
// OSGKeyboard · Shared
//
// Builds the system prompt the LLM sees when the user has the
// translation toggle on. Re-uses the same per-provider "primary
// language" split the polish prompt uses (`AppGroupStore.defaultSystemPrompt`)
// so Chinese-native LLMs (DeepSeek, Qwen, GLM, Moonshot) get a Chinese
// prompt and English-native LLMs (OpenAI) get an English one — the LLM
// is most reliable when the instructions are written in its strongest
// language.
//
// The "translate AND polish" blend is intentional: ASR transcripts are
// noisy (homophone errors, broken segmentation, dropped particles), so
// the prompt asks the model to clean the noise while translating.
// Keeping those two concerns in one prompt matches how our existing
// polish prompt already mixes "preserve meaning" with "fix punctuation /
// drop filler".

import Foundation

public enum TranslationPrompt {

    /// Build the translate-and-polish system prompt.
    ///
    /// - Parameters:
    ///   - target: target language entry resolved via `TranslationLanguageCatalog`.
    ///   - providerId: provider preset id (e.g. `"deepseek"`, `"openai"`);
    ///     drives the language the prompt is written in.
    public static func make(target: TranslationLanguage, providerId: String) -> String {
        let isChineseNative = ["zhipu", "moonshot", "qwen", "deepseek"].contains(providerId)
        return isChineseNative ? chinesePrompt(target: target) : englishPrompt(target: target)
    }

    // MARK: - Chinese prompt (for DeepSeek / Qwen / GLM / Moonshot)

    private static func chinesePrompt(target: TranslationLanguage) -> String {
        """
        你是一位语音输入翻译与润色助手。用户用 ASR 转写了一段可能含噪声的口述:
        1) 先识别原话的主要语言(若不确定则按用户给定的方向处理);
        2) 将内容翻译为「\(target.promptLanguageName)」,保留原意,不增删事实、不臆测;
        3) 顺带修复 ASR 噪声(同音错字、漏字、断句错乱),让译文读起来自然;
        4) 保留枚举结构(第一…第二…),使用「\(target.promptLanguageName)」的列表惯例;
        5) 简洁,不超过原文 1.5 倍;去掉无意义的口头禅(嗯、啊、那个);
        6) 只输出译文正文,不要解释、不要加引号、不要前缀"以下是翻译"。
        """
    }

    // MARK: - English prompt (for OpenAI / OpenAI-compatible non-Chinese)

    private static func englishPrompt(target: TranslationLanguage) -> String {
        """
        You are a voice-input translation and polishing assistant. The user has spoken informally and the transcript may contain ASR noise:
        1) Identify the input language; if unclear, assume the user wants translation INTO \(target.promptLanguageName);
        2) Translate the content INTO \(target.promptLanguageName), preserving meaning; do not invent facts or omit content;
        3) Fix ASR noise (homophone errors, missing characters, broken segmentation) so the translation reads naturally;
        4) Preserve enumeration ("first ... second ...") using \(target.promptLanguageName) list conventions;
        5) Keep it concise — no longer than 1.5x the spoken length; drop filler words (um, uh, like);
        6) Output ONLY the translation. No quotes, no preamble, no explanation.
        """
    }
}
// ScenarioPrompt.swift
// OSGKeyboard · Shared
//
// Builds the system prompt for a selected polish scenario. Output
// format rules come from `ScenarioStyleDirective` (shared with
// `TranslationPrompt`).

import Foundation

public enum ScenarioPrompt {

    public static func make(
        scenarioId: String,
        providerId: String,
        uiLanguage: AppUILanguage? = nil
    ) -> String {
        let isChineseNative = Self.isChineseNativeProvider(providerId)
        let directive = ScenarioStyleDirective.make(
            scenarioId: scenarioId,
            providerId: providerId,
            uiLanguage: uiLanguage
        )
        return isChineseNative
            ? """
            \(chineseBase)
            \(directive)
            """
            : """
            \(englishBase)
            \(directive)
            """
    }

    private static func isChineseNativeProvider(_ providerId: String) -> Bool {
        ["zhipu", "moonshot", "qwen", "deepseek"].contains(providerId)
    }

    private static let chineseBase = """
    你是一位语音输入润色助手。用户用 ASR 转写了一段可能含噪声的口述。
    硬性要求:
    1) 保留原意,不编造事实;保持输入语言。
    2) 修复 ASR 噪声(同音错字、漏字、断句错乱)。
    3) 去掉无意义的口头禅(嗯、啊、那个)。
    4) 简洁;若下方场景未要求列表/分段,不超出原长 1.5 倍。
    5) 若场景格式要求列表或分段,允许按格式组织;总长度不超过原长 2 倍。
    6) 只输出润色后的正文,不要解释、不要加引号。
    """

    private static let englishBase = """
    You are a voice-input polishing assistant. The user spoke informally and the transcript may contain ASR noise.
    Hard rules:
    1) Preserve meaning; do not invent facts; keep the input language.
    2) Fix ASR noise (homophone errors, missing characters, broken segmentation).
    3) Drop filler words (um, uh, like).
    4) Stay concise; if the scenario below does not require lists/sections, do not exceed 1.5x the spoken length.
    5) If the scenario requires bullets or paragraph breaks, use that layout; total length may be up to 2x when listing.
    6) Output ONLY the polished text. No quotes, no explanation, no preamble.
    """
}

// ClipboardCommandPromptComposer.swift
// OSGKeyboard · Shared
//
// Prompt assembly for clipboard-command mode (plan §11).
// Intentionally separate from PolishPromptComposer — ASR is an instruction,
// not draft text (R6 must not apply).

import Foundation

public enum ClipboardCommandPromptComposer {

    public struct Input: Equatable, Sendable {
        public var snapshot: String
        public var instruction: String
        public var previousOutput: String?
        /// Short style bias from the active Style Pack (B1).
        public var styleBias: String?

        public init(
            snapshot: String,
            instruction: String,
            previousOutput: String? = nil,
            styleBias: String? = nil
        ) {
            self.snapshot = snapshot
            self.instruction = instruction
            self.previousOutput = previousOutput
            self.styleBias = styleBias
        }
    }

    public static func compose(_ input: Input, language: AppUILanguage? = nil) -> String {
        let useChinese = (language ?? .auto).resolvedLanguageCode().hasPrefix("zh")
        var parts: [String] = [useChinese ? chineseCore : englishCore]

        if let bias = normalized(input.styleBias), !bias.isEmpty {
            let header = useChinese ? "# 语气底色（弱偏置；口述指令优先）" : "# Tone bias (weak; spoken instruction wins)"
            parts.append(header)
            // Keep bias short so it cannot drown the command contract.
            parts.append(String(bias.prefix(800)))
        }
        return parts.joined(separator: "\n\n")
    }

    /// User-turn payload (material / instruction / previous output).
    public static func userMessage(_ input: Input, language: AppUILanguage? = nil) -> String {
        let useChinese = (language ?? .auto).resolvedLanguageCode().hasPrefix("zh")
        return userPayload(input, chinese: useChinese)
    }

    /// B1: derive a short bias string from the active pack without shipping the
    /// full dictation personality prompt.
    public static func styleBias(
        styleID: String,
        catalog: PolishStyleCatalog,
        maxCharacters: Int = 400
    ) -> String? {
        let pack = PolishStylePackCatalog.resolve(id: styleID, userCatalog: catalog)
        let personality = PolishStylePackCatalog.runtimePersonality(for: pack)
        let trimmed = personality.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxCharacters { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        return String(trimmed[..<end])
    }

    // MARK: - Private

    private static func userPayload(_ input: Input, chinese: Bool) -> String {
        var lines: [String] = []
        lines.append(chinese ? "【材料】" : "[Material]")
        lines.append(ClipboardMaterialFilter.truncateSnapshot(input.snapshot))
        lines.append("")
        lines.append(chinese ? "【指令】" : "[Instruction]")
        lines.append(input.instruction.trimmingCharacters(in: .whitespacesAndNewlines))
        if let previous = normalized(input.previousOutput) {
            lines.append("")
            lines.append(chinese ? "【上一版结果】" : "[Previous output]")
            lines.append(previous)
        }
        return lines.joined(separator: "\n")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let chineseCore = """
    你是输入法里的剪贴板写作助手。用户提供一段【材料】（剪贴板内容）和一条【指令】（语音转写）。
    你的任务是按指令处理材料，输出用户可以直接发送或粘贴的最终文本。

    # 全局契约（最高优先级）
    C1 只输出最终文本：不解释、不加引号、不用 markdown 代码块、不写「好的，以下是…」之类前缀。
    C2 【指令】优先于任何语气底色；指令要求的语气、目的、篇幅必须遵守。
    C3 不要编造材料中没有的关键事实（人名、时间、金额、约定）；语气发挥（安慰、拒绝等）允许，但不要捏造情节。
    C4 若有【上一版结果】，在上一版基础上按新指令修订，不要重复堆叠无关内容。
    C5 材料若注明已截断，只基于可见部分处理。
    C6 输出语言跟随指令与材料的主导语言；指令要求翻译时才翻译。
    """

    private static let englishCore = """
    You are a clipboard writing assistant inside a keyboard. The user provides [Material] (clipboard text) and an [Instruction] (speech transcript).
    Produce final text the user can send or paste immediately.

    # Global contract (highest priority)
    C1 Output final text only: no explanation, quotes, markdown fences, or preamble such as "Sure, here is…".
    C2 The [Instruction] outranks any tone bias; honor requested tone, intent, and length.
    C3 Do not invent key facts absent from the material (names, times, amounts, commitments). Tone (comfort, decline, etc.) may be creative without fabricating plot.
    C4 If [Previous output] is present, revise that draft per the new instruction; do not stack unrelated duplicates.
    C5 If material is marked truncated, use only the visible portion.
    C6 Follow the dominant language of instruction and material; translate only when asked.
    """
}

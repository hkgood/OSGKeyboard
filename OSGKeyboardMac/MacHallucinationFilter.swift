// MacHallucinationFilter.swift
// OSGKeyboard · Mac
//
// Strips Qwen3 / MLX streaming scaffold tokens and silence hallucinations.

import Foundation

enum MacQwen3LanguageHint {
    /// Map persisted BCP-47 locale ids to Qwen3 prompt language names.
    /// Returns `nil` for auto-detect.
    static func from(locale: Locale) -> String? {
        let raw = locale.identifier.lowercased()
        if raw.isEmpty || raw == "auto" { return nil }
        if raw.hasPrefix("zh") { return "Chinese" }
        if raw.hasPrefix("en") { return "English" }
        if raw.hasPrefix("ja") { return "Japanese" }
        if raw.hasPrefix("ko") { return "Korean" }
        if raw.hasPrefix("fr") { return "French" }
        if raw.hasPrefix("de") { return "German" }
        if raw.hasPrefix("es") { return "Spanish" }
        if raw.hasPrefix("pt") { return "Portuguese" }
        if raw.hasPrefix("ru") { return "Russian" }
        if raw.hasPrefix("ar") { return "Arabic" }
        return nil
    }
}

enum MacHallucinationFilter {
    /// RMS below this skips feeding audio into the MLX streaming session.
    static let silencePeakThreshold: Float = 0.0005

    static func strip(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }

        if let marker = text.range(of: "<asr_text>", options: .backwards) {
            text = String(text[marker.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let match = text.range(
            of: #"^language\s+\S+\s*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            text = String(text[match.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if isMetadataNoiseLine(text) { return "" }
        return text
    }

    /// When the transcript is mostly vocabulary tokens and audio energy stayed low, drop it.
    static func shouldDiscardHotwordDump(
        text: String,
        peakRMS: Float,
        bias: LocalASRBiasPayload?
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard peakRMS < FlowCaptureTailDrainPolicy.flowDefault.silenceRMSThreshold else {
            return false
        }
        guard let bias, !bias.hardHotwords.isEmpty else { return false }
        let lowered = trimmed.lowercased()
        let hits = bias.hardHotwords.filter { lowered.contains($0.lowercased()) }.count
        let wordCount = max(1, trimmed.split { $0.isWhitespace }.count)
        return hits >= wordCount
    }

    private static func isMetadataNoiseLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        switch lowered {
        case "language", "emotion", "event", "text",
             "<asr_text>", "</asr_text>", "<|im_end|>":
            return true
        default:
            if lowered.range(
                of: #"^language(\s+\S+)?$"#,
                options: .regularExpression
            ) != nil {
                return true
            }
            return false
        }
    }
}

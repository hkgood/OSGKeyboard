// PolishIntensity.swift
// OSGKeyboard · Shared
//
// How aggressively the LLM should rewrite the ASR transcript.
//
// Persisted in `AppGroupStore` via `ProviderConfig` so the keyboard
// extension can honour the chosen intensity during live dictation.

import Foundation

public enum PolishIntensity: String, Codable, Sendable, CaseIterable {
    /// Drop only isolated filler words (嗯 / 呃 / 那个 / 就是 / 然后)
    /// and obvious duplicated fragments. Punctuation and structure
    /// formatting still apply at every intensity level.
    case light

    /// Correction + light polish: drop fillers, fix homophone errors,
    /// adjust obviously-broken word order, add punctuation. Preserves
    /// the speaker's voice and intent.
    case medium

    /// Full structural rewrite: split long sentences, auto-number
    /// enumerated items, format as paragraphs / lists. Use for
    /// meeting notes, weekly reports, blog drafts.
    case heavy

    /// User-facing label key for the Settings picker. Localized
    /// through `SharedL10n` so the same key works in the main app
    /// and the keyboard extension.
    public var labelKey: String {
        switch self {
        case .light: return "polish.intensity.light"
        case .medium: return "polish.intensity.medium"
        case .heavy: return "polish.intensity.heavy"
        }
    }

    /// Short description shown under the picker. Same localization
    /// story as `labelKey`.
    public var descriptionKey: String {
        switch self {
        case .light: return "polish.intensity.light.desc"
        case .medium: return "polish.intensity.medium.desc"
        case .heavy: return "polish.intensity.heavy.desc"
        }
    }

    /// Inline guideline injected into the LLM prompt. The polish
    /// service appends this verbatim so the LLM has an explicit,
    /// non-ambiguous constraint per call.
    public var promptGuideline: String {
        promptGuideline(styleID: nil)
    }

    /// Intensity guideline for the LLM prompt. When the active style limits
    /// heavy restructuring (chat/light/dating), heavy still improves clarity
    /// but must not override the style pack's length and format rules.
    public func promptGuideline(styleID: String?) -> String {
        let base: String
        if styleID == "builtin.dating" {
            switch self {
            case .light:
                base = """
                Dating Light: apply ASR cleanup, then soften interrogation, lecturing, commands, dismissal, blame, or pressure even when the original wording is otherwise clear. \
                Make the message warm and respectful without adding flirtation, teasing, romantic intent, or relationship escalation. Preserve the speaker's recognizable voice.
                """
            case .medium:
                base = """
                Dating Medium: apply Light corrections, then add at most one grounded observation, affiliative joke, natural self-disclosure, follow-up question, or restrained signal of interest when supported by the transcript or preceding context. \
                Keep any flirtation light, interpretable at face value, and easy to decline. Do not invent relationship context.
                """
            case .heavy:
                base = """
                Dating Heavy: apply Medium corrections and, only when the transcript already expresses romantic interest or invitation and the context shows no rejection, discomfort, vulnerability, or power imbalance, make appreciation, longing, expectation, or invitation more proactive and clear. \
                Increase romantic tension and directness, not ambiguity, pressure, sexual escalation, or message length. Preserve the speaker's recognizable voice and every fact.
                """
            }
        } else {
            switch self {
            case .light:
                base = """
                Light rewrite: remove isolated filler words (嗯, 呃, 那个, 就是, 然后, 对, ok, um, uh) and obvious duplicated fragments only. \
                Do not rephrase otherwise-clear wording. \
                Still restore punctuation and sentence breaks per the global output contract and active style pack.
                """
            case .medium:
                base = """
                Medium rewrite: fix obvious ASR errors (homophones, missing/extra characters), remove fillers and duplicated fragments, \
                adjust obviously-broken word order. Preserve the speaker's voice. \
                Still restore punctuation and breaks per the global output contract and active style pack. \
                Do not invent facts or change numbers/proper nouns.
                """
            case .heavy:
                base = """
                Heavy rewrite: apply medium corrections, then you may reorganize paragraphs, split long sentences, and listify enumerated content when the active style pack allows it. \
                Punctuation is mandatory at every intensity. \
                Preserve every fact, number, and proper noun. Do not add information.
                """
            }
        }

        guard self == .heavy,
              let styleID,
              PolishStylePackCatalog.limitsHeavyRestructuring(id: styleID)
        else {
            return base
        }

        return base + """

        Style override: the active style pack limits heavy restructuring. Do not expand length, add paragraphs for polish only, or introduce numbered lists unless the transcript explicitly enumerates items. Keep the style pack's chat rhythm, tone, and format rules authoritative.
        """
    }

    /// Legacy persisted value `"off"` maps to `.medium` on read.
    public static func resolve(storedRawValue raw: String) -> PolishIntensity {
        if raw == legacyOffRawValue {
            return .medium
        }
        return PolishIntensity(rawValue: raw) ?? .default
    }

    /// Raw value written by builds before the off tier was removed.
    public static let legacyOffRawValue = "off"
}

extension PolishIntensity {
    /// Default for new installs. `medium` is what Typeless and Wispr
    /// Flow also use as their first-run default.
    public static let `default`: PolishIntensity = .medium
}

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
        switch self {
        case .light:
            return """
            Light rewrite: remove isolated filler words (嗯, 呃, 那个, 就是, 然后, 对, ok, um, uh) and obvious duplicated fragments only. \
            Do not rephrase otherwise-clear wording. \
            Still restore punctuation, sentence breaks, and content-triggered structure (lists, paragraphs) per the global output contract.
            """
        case .medium:
            return """
            Medium rewrite: fix obvious ASR errors (homophones, missing/extra characters), remove fillers and duplicated fragments, \
            adjust obviously-broken word order. Preserve the speaker's voice. \
            Still restore punctuation, sentence breaks, and content-triggered structure per the global output contract. \
            Do not invent facts or change numbers/proper nouns.
            """
        case .heavy:
            return """
            Heavy rewrite: apply medium corrections, then you may reorganize paragraphs, split long sentences, and listify enumerated content. \
            Punctuation and structure are mandatory at every intensity. \
            Preserve every fact, number, and proper noun. Do not add information.
            """
        }
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

// PolishIntensity.swift
// OSGKeyboard · Shared
//
// How aggressively the LLM should rewrite the ASR transcript.
//
// Persisted in `AppGroupStore` via `ProviderConfig` so the keyboard
// extension can honour the chosen intensity during live dictation.

import Foundation

public enum PolishIntensity: String, Codable, Sendable, CaseIterable {
    /// Engine is in pure ASR mode (local + cloud-polish-off). The LLM
    /// is never called; the raw transcript is inserted as-is. This
    /// value is mostly a UI default — the actual behaviour is
    /// determined by `engineMode` + `localModeCloudPolishEnabled`.
    case off

    /// Drop only isolated filler words (嗯 / 呃 / 那个 / 就是 / 然后)
    /// and obvious duplicated fragments. Everything else stays.
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
        case .off: return "polish.intensity.off"
        case .light: return "polish.intensity.light"
        case .medium: return "polish.intensity.medium"
        case .heavy: return "polish.intensity.heavy"
        }
    }

    /// Short description shown under the picker. Same localization
    /// story as `labelKey`.
    public var descriptionKey: String {
        switch self {
        case .off: return "polish.intensity.off.desc"
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
        case .off:
            return "Do not change the input at all. Output the original text verbatim."
        case .light:
            return "Only remove isolated filler words (嗯, 呃, 那个, 就是, 然后, 对, ok) and obvious duplicated fragments. Do not change any other words, word order, or punctuation."
        case .medium:
            return "Correct obvious speech-recognition errors (homophones, missing/extra characters). Remove filler words and duplicated fragments. Adjust obviously-broken word order. Add punctuation. Do not restructure sentences, invent facts, or change the speaker's voice."
        case .heavy:
            return "Apply medium corrections, then optionally restructure: split long sentences, auto-number enumerated items into markdown lists, group related ideas into paragraphs. Preserve every fact, number, and proper noun."
        }
    }
}

extension PolishIntensity {
    /// Default for new installs. `medium` is what Typeless and Wispr
    /// Flow also use as their first-run default.
    public static let `default`: PolishIntensity = .medium
}

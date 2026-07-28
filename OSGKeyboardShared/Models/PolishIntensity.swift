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
        switch styleID {
        case "builtin.dating":
            base = datingGuideline
        case "builtin.flex":
            base = flexGuideline
        case "builtin.corp":
            base = corpGuideline
        case "builtin.diba":
            base = dibaGuideline
        case "builtin.xhs":
            base = xhsGuideline
        default:
            base = defaultGuideline
        }

        guard self == .heavy,
              let styleID,
              PolishStylePackCatalog.limitsHeavyRestructuring(id: styleID)
        else {
            return base
        }

        if PolishStylePackCatalog.isFunPersonality(id: styleID) {
            return base + """

            Style override: keep short sendable form — no report paragraphs or numbered lists unless the transcript enumerates items. \
            Full voice rewrite is allowed for style effect; stay within about 1–3 short bubbles, not an essay. This style's Light/Medium/Heavy rules remain authoritative.
            """
        }

        return base + """

        Style override: the active style pack limits heavy restructuring. Do not expand length, add paragraphs for polish only, or introduce numbered lists unless the transcript explicitly enumerates items. Keep the style pack's chat rhythm, tone, and format rules authoritative.
        """
    }

    private var datingGuideline: String {
        switch self {
        case .light:
            """
            Dating Light (加戏): fully rewrite while preserving intent. Remove interrogation, lecturing, and pressure. \
            Add a bit of attitude or light humor so it is fun and easy to answer — spoken WeChat first, clever lines only as seasoning. \
            Do not make it flirtatious yet. Blind-testable difference required; near-synonym polish is a failure.
            """
        case .medium:
            """
            Dating Medium (会撩): fully rewrite while preserving intent. Keep Light's play, and add readable flirtation (preference, soft pull-closer, deniable wit). \
            Stay conversational; do not invent shared history. Must be clearly more flirty than Dating Light.
            """
        case .heavy:
            """
            Dating Heavy (更挑逗): fully rewrite while preserving intent. Bolder teasing or clingy jokes than Medium; still not pornographic. \
            Keep an exit ramp. On rejection/coldness, collapse to a clean respectful close. Must be clearly more teasing than Dating Medium.
            """
        }
    }

    private var flexGuideline: String {
        switch self {
        case .light:
            """
            Flex Light: rewrite into light 4A/study-abroad Chinglish — mostly Chinese with 1–2 English seasoning words (solid/low/vibe/feel). \
            Do not invent luxury ownership. Must sound casually showy, not like an ad slogan dump.
            """
        case .medium:
            """
            Flex Medium: clearer pretentious mix; steadier code-switching and optionally one brand/taste cue. \
            Still spoken, not a luxury campaign. Must be clearly showier than Flex Light.
            """
        case .heavy:
            """
            Flex Heavy: obvious flex energy with denser Chinglish and optional brand seasoning. \
            Still short spoken messages — no full-English sentences or brand laundry lists. Must be clearly showier than Flex Medium.
            """
        }
    }

    private var corpGuideline: String {
        switch self {
        case .light:
            """
            Corp Light: light big-tech buzzword seasoning in spoken meeting tone (对齐/同步/postpone/owner). \
            Keep the facts; pick report / quarrel / blame-shift voice from intent. Do not dump a buzzword dictionary into one sentence.
            """
        case .medium:
            """
            Corp Medium: clearer sync/report or soft pushback with buzzwords (拉通/颗粒度/交界面/闭环). \
            Still sounds like someone talking in a meeting. Must be denser corp-speak than Corp Light.
            """
        case .heavy:
            """
            Corp Heavy: stronger quarrel or blame-shift flavor with denser buzzwords; still short spoken turns, not a PPT essay. \
            No real firing/PIP threats or personal insults. Must be clearly heavier than Corp Medium.
            """
        }
    }

    private var dibaGuideline: String {
        switch self {
        case .light:
            """
            DiBa Light: rewrite as a short reply that catches the other person's claim and lightly cracks the premise. \
            No swearing or personal attacks. Spoken takedown, not a debate essay.
            """
        case .medium:
            """
            DiBa Medium: clearer premise-breaking with cooler mockery; still 1–3 short lines. \
            Must feel more crushing than DiBa Light without becoming an opinion brief.
            """
        case .heavy:
            """
            DiBa Heavy: colder high-irony takedown that makes the other side hard to answer; still no swearing, no group attacks, no "首先/综上所述" essays. \
            Must be clearly sharper than DiBa Medium.
            """
        }
    }

    private var xhsGuideline: String {
        switch self {
        case .light:
            """
            RED Note Light (轻安利): rewrite into sisterly Xiaohongshu note voice with light tone words and sparse emoji. \
            Keep length close to the draft; do not invent product claims or "亲测" details. Must feel gently 集美, not ad-copy.
            """
        case .medium:
            """
            RED Note Medium (种草感): fuller note body with a hook opening, short paragraphs, and lived-experience tone. \
            Light lists are OK when the transcript has multiple points. Must read more post-ready than RED Note Light. Still no invented facts.
            """
        case .heavy:
            """
            RED Note Heavy (爆款感): stronger emotional hook, optional contrast/避雷/steps, and a light comment CTA. \
            Paragraphs and scannable structure are allowed. Still no fabricated efficacy, numbers, or fake before/after. Must feel clearly more viral than Medium.
            """
        }
    }

    private var defaultGuideline: String {
        switch self {
        case .light:
            """
            Light rewrite: remove isolated filler words (嗯, 呃, 那个, 就是, 然后, 对, ok, um, uh) and obvious duplicated fragments only. \
            Do not rephrase otherwise-clear wording. \
            Still restore punctuation and sentence breaks per the global output contract and active style pack.
            """
        case .medium:
            """
            Medium rewrite: fix obvious ASR errors (homophones, missing/extra characters), remove fillers and duplicated fragments, \
            adjust obviously-broken word order. Preserve the speaker's voice. \
            Still restore punctuation and breaks per the global output contract and active style pack. \
            Do not invent facts or change numbers/proper nouns.
            """
        case .heavy:
            """
            Heavy rewrite: apply medium corrections, then you may reorganize paragraphs, split long sentences, and listify enumerated content when the active style pack allows it. \
            Punctuation is mandatory at every intensity. \
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

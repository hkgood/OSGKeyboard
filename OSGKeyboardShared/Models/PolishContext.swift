// PolishContext.swift
// OSGKeyboard · Shared
//
// Bag of inputs the LLM polish service needs. Caller assembles it
// before calling `IntelligentPolishingService.polish(_:context:)`.
// Splitting it out keeps the polish service's signature stable as
// we add more signals (app context, intensity, personal dictionary,
// preceding text, etc.) over time.

import Foundation

public struct PolishContext: Sendable {
    /// Coarse classification of the input field. When `.unknown` the
    /// LLM is told to pick a neutral tone on its own.
    public let appContext: AppContext

    /// User-configured intensity. Drives how aggressively the LLM
    /// is allowed to rewrite.
    public let intensity: PolishIntensity

    /// Optional preceding text (e.g. a few hundred characters of
    /// what the user already typed before the recording). The LLM
    /// uses it to resolve "this / 那个 / 刚才" references and to
    /// bias terminology choices.
    public let precedingText: String?

    /// Extra dictionary block appended after `PersonalDictionary.promptFragment()`
    /// (e.g. builtin `phrases.tsv` terms on macOS local ASR).
    public let dictionarySupplement: String?

    /// Cap on how many characters of `precedingText` we actually
    /// include in the prompt. The full preceding text is often
    /// hundreds of KB in a long note — we only need the tail.
    public let maxPrecedingChars: Int

    public init(
        appContext: AppContext = .unknown,
        intensity: PolishIntensity = .default,
        precedingText: String? = nil,
        dictionarySupplement: String? = nil,
        maxPrecedingChars: Int = 500
    ) {
        self.appContext = appContext
        self.intensity = intensity
        self.precedingText = precedingText
        self.dictionarySupplement = dictionarySupplement
        self.maxPrecedingChars = maxPrecedingChars
    }

    /// Truncated view of `precedingText` ready for prompt injection.
    /// Returns `nil` when there is nothing meaningful to add.
    public var precedingForPrompt: String? {
        guard let raw = precedingText, !raw.isEmpty else { return nil }
        if raw.count <= maxPrecedingChars { return raw }
        return String(raw.suffix(maxPrecedingChars))
    }
}

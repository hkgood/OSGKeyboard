// PolishContext.swift
// OSGKeyboard · Shared
//
// Bag of inputs the LLM polish service needs. Caller assembles it
// before calling `IntelligentPolishingService.polish(_:context:)`.
// Splitting it out keeps the polish service's signature stable as
// we add more signals (app context, personal dictionary, preceding text,
// etc.) over time.

import Foundation

public struct FieldHints: Sendable, Equatable {
    public let keyboardType: String?
    public let returnKeyType: String?
    public let isEmptyField: Bool
    public let isContextAvailable: Bool

    public init(
        keyboardType: String? = nil,
        returnKeyType: String? = nil,
        isEmptyField: Bool = false,
        isContextAvailable: Bool = false
    ) {
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.isEmptyField = isEmptyField
        self.isContextAvailable = isContextAvailable
    }

    public init(from context: FlowFieldContext) {
        self.init(
            keyboardType: context.keyboardType,
            returnKeyType: context.returnKeyType,
            isEmptyField: context.isEmptyField,
            isContextAvailable: context.isContextAvailable
        )
    }
}

public struct PolishContext: Sendable {
    /// Coarse classification of the input field. When `.unknown` the
    /// LLM is told to pick a neutral tone on its own.
    public let appContext: AppContext

    /// Optional preceding text (e.g. a few hundred characters of
    /// what the user already typed before the recording). The LLM
    /// uses it to resolve "this / 那个 / 刚才" references and to
    /// bias terminology choices.
    public let precedingText: String?

    /// Optional text immediately after the insertion point.
    public let followingText: String?

    /// Input-field signals captured by the keyboard extension.
    public let fieldHints: FieldHints?

    /// Extra dictionary block appended after `PersonalDictionary.promptFragment()`
    /// (e.g. builtin `phrases.tsv` terms on macOS local ASR).
    public let dictionarySupplement: String?

    /// Cap on how many characters of `precedingText` we actually
    /// include in the prompt. The full preceding text is often
    /// hundreds of KB in a long note — we only need the tail.
    public let maxPrecedingChars: Int
    public let maxFollowingChars: Int

    public init(
        appContext: AppContext = .unknown,
        precedingText: String? = nil,
        followingText: String? = nil,
        fieldHints: FieldHints? = nil,
        dictionarySupplement: String? = nil,
        maxPrecedingChars: Int = 600,
        maxFollowingChars: Int = 200
    ) {
        self.appContext = appContext
        self.precedingText = precedingText
        self.followingText = followingText
        self.fieldHints = fieldHints
        self.dictionarySupplement = dictionarySupplement
        self.maxPrecedingChars = maxPrecedingChars
        self.maxFollowingChars = maxFollowingChars
    }

    /// Truncated view of `precedingText` ready for prompt injection.
    /// Returns `nil` when there is nothing meaningful to add.
    public var precedingForPrompt: String? {
        guard let raw = precedingText, !raw.isEmpty else { return nil }
        if raw.count <= maxPrecedingChars { return raw }
        return String(raw.suffix(maxPrecedingChars))
    }

    public var followingForPrompt: String? {
        guard let raw = followingText, !raw.isEmpty else { return nil }
        if raw.count <= maxFollowingChars { return raw }
        return String(raw.prefix(maxFollowingChars))
    }
}

// LocalASRBiasPayload.swift
// OSGKeyboard · Shared
//
// Output of `LocalASRBiasAdapter` — vocabulary signals for each pipeline layer.

import Foundation

public struct LocalASRCorrectionPair: Sendable, Equatable {
    public let alias: String
    public let term: String

    public init(alias: String, term: String) {
        self.alias = alias
        self.term = term
    }
}

public struct LocalASRBiasDiagnostics: Sendable, Equatable, Codable {
    public var userTermCount: Int
    public var builtinTermCount: Int
    public var truncated: Bool
    public var truncationReason: String?
    public var selectedSources: [String]

    public init(
        userTermCount: Int = 0,
        builtinTermCount: Int = 0,
        truncated: Bool = false,
        truncationReason: String? = nil,
        selectedSources: [String] = []
    ) {
        self.userTermCount = userTermCount
        self.builtinTermCount = builtinTermCount
        self.truncated = truncated
        self.truncationReason = truncationReason
        self.selectedSources = selectedSources
    }
}

public struct LocalASRBiasPayload: Sendable, Equatable {
    public var hardHotwords: [String]
    public var promptBias: String?
    public var corpusContext: String?
    public var polishFragment: String
    public var correctionPairs: [LocalASRCorrectionPair]
    public var diagnostics: LocalASRBiasDiagnostics

    public static let empty = LocalASRBiasPayload(
        hardHotwords: [],
        promptBias: nil,
        corpusContext: nil,
        polishFragment: "",
        correctionPairs: [],
        diagnostics: LocalASRBiasDiagnostics()
    )

    public init(
        hardHotwords: [String],
        promptBias: String?,
        corpusContext: String?,
        polishFragment: String,
        correctionPairs: [LocalASRCorrectionPair],
        diagnostics: LocalASRBiasDiagnostics
    ) {
        self.hardHotwords = hardHotwords
        self.promptBias = promptBias
        self.corpusContext = corpusContext
        self.polishFragment = polishFragment
        self.correctionPairs = correctionPairs
        self.diagnostics = diagnostics
    }
}

public struct LocalASRBiasRequest: Sendable {
    public var dictionary: PersonalDictionary
    public var locale: Locale
    public var frontAppBundleId: String?
    public var capabilities: LocalASRCapabilities
    /// Max builtin `phrases.tsv` terms considered for ASR bias (not polish-only).
    public var builtinASRLimit: Int
    /// Max builtin terms referenced in the polish supplement block.
    public var builtinPolishLimit: Int

    public init(
        dictionary: PersonalDictionary,
        locale: Locale,
        frontAppBundleId: String? = nil,
        capabilities: LocalASRCapabilities,
        builtinASRLimit: Int = 300,
        builtinPolishLimit: Int = 40
    ) {
        self.dictionary = dictionary
        self.locale = locale
        self.frontAppBundleId = frontAppBundleId
        self.capabilities = capabilities
        self.builtinASRLimit = builtinASRLimit
        self.builtinPolishLimit = builtinPolishLimit
    }
}

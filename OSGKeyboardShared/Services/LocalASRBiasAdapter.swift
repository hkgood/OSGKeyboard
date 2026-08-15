// LocalASRBiasAdapter.swift
// OSGKeyboard · Shared
//
// Maps `PersonalDictionary` + builtin lexicon + runtime context into the
// layered bias outputs consumed by local ASR, correction, and polish.

import Foundation

public enum LocalASRBiasAdapter {

    /// Bundle IDs where computer-science vocabulary is especially likely.
    private static let codeEditorBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.google.android.studio",
        "com.jetbrains.intellij",
        "com.jetbrains.AppCode",
        "com.sublimetext.4",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
    ]

    public static func adapt(
        _ request: LocalASRBiasRequest,
        lexicon: BuiltinLexiconIndex = .shared
    ) -> LocalASRBiasPayload {
        let capabilities = request.capabilities
        let dictionary = request.dictionary

        var selectedSources = ["user"]
        let preferredSources = Self.preferredLexiconSources(for: request.frontAppBundleId)
        if preferredSources != nil {
            selectedSources.append("builtin-computer")
        } else {
            selectedSources.append("builtin-top")
        }

        let userSorted = dictionary.effectiveEntries.sorted { $0.usageCount > $1.usageCount }
        var mergedTerms: [String] = []
        var seen = Set<String>()
        func appendTerm(_ term: String) {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            mergedTerms.append(trimmed)
        }

        for entry in userSorted {
            appendTerm(entry.term)
        }
        let userTermCount = mergedTerms.count

        let builtinWords = lexicon.topTerms(
            limit: request.builtinASRLimit,
            minimumWeight: 4,
            preferredSources: preferredSources
        )
        let beforeBuiltin = mergedTerms.count
        for word in builtinWords {
            appendTerm(word)
        }
        let builtinTermCount = mergedTerms.count - beforeBuiltin

        var hardHotwords: [String] = []
        switch capabilities.hotwordMode {
        case .perRequest, .recognizerScoped:
            let cap = max(capabilities.maxHotwordCount, 1)
            hardHotwords = Self.hardHotwordList(from: mergedTerms, maxCount: cap)
        case .cloudVocabulary:
            hardHotwords = dictionary.asrHotwords(maxCount: max(capabilities.maxHotwordCount, 1))
        case .none, .promptOnly:
            break
        }

        var promptBias: String?
        var truncated = false
        var truncationReason: String?

        if capabilities.hotwordMode == .promptOnly, capabilities.maxPromptCharacters > 0 {
            let built = Self.buildPromptBias(
                dictionary: dictionary,
                builtinTerms: builtinWords,
                maxCharacters: capabilities.maxPromptCharacters
            )
            if built.count > capabilities.maxPromptCharacters {
                truncated = true
                truncationReason = "promptBias exceeded \(capabilities.maxPromptCharacters) characters"
            }
            promptBias = built.isEmpty ? nil : built
        }

        let polishFragment = Self.buildPolishFragment(
            dictionary: dictionary,
            builtinTerms: builtinWords,
            maxTerms: request.builtinPolishLimit
        )

        let correctionPairs = dictionary.localCorrectionPairs()

        return LocalASRBiasPayload(
            hardHotwords: hardHotwords,
            promptBias: promptBias,
            corpusContext: promptBias,
            polishFragment: polishFragment,
            correctionPairs: correctionPairs,
            diagnostics: LocalASRBiasDiagnostics(
                userTermCount: userTermCount,
                builtinTermCount: builtinTermCount,
                truncated: truncated,
                truncationReason: truncationReason,
                selectedSources: selectedSources
            )
        )
    }

    // MARK: - Private

    private static func preferredLexiconSources(for bundleId: String?) -> Set<String>? {
        guard let bundleId, codeEditorBundleIDs.contains(bundleId) else { return nil }
        return ["computer_terms"]
    }

    private static func hardHotwordList(from terms: [String], maxCount: Int) -> [String] {
        Array(terms.prefix(maxCount))
    }

    private static func buildPromptBias(
        dictionary: PersonalDictionary,
        builtinTerms: [String],
        maxCharacters: Int
    ) -> String {
        let userBias = dictionary.asrPromptBias(maxCharacters: maxCharacters)
        let userTermsLower = Set(dictionary.effectiveEntries.map { $0.term.lowercased() })
        let extras = builtinTerms.filter { !userTermsLower.contains($0.lowercased()) }
        guard !extras.isEmpty else { return userBias }

        let extraBlock = "常见技术词汇：\(extras.prefix(80).joined(separator: "、"))"
        if userBias.isEmpty {
            return String(extraBlock.prefix(maxCharacters))
        }
        let combined = userBias + "；" + extraBlock
        return String(combined.prefix(maxCharacters))
    }

    private static func buildPolishFragment(
        dictionary: PersonalDictionary,
        builtinTerms: [String],
        maxTerms: Int
    ) -> String {
        let userTermsLower = Set(dictionary.effectiveEntries.map { $0.term.lowercased() })
        let extras = builtinTerms
            .filter { !userTermsLower.contains($0.lowercased()) }
            .prefix(maxTerms)
        guard !extras.isEmpty else { return "" }
        return "内置技术词汇参考（需原样保留）：\(extras.joined(separator: "、"))"
    }
}

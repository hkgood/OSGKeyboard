// EnglishSystemLexicon.swift
// OSGKeyboard · Shared
//
// Apple's sanctioned English sources for a custom keyboard: UITextChecker
// completions / guesses, plus UILexicon names from
// `requestSupplementaryLexicon`. The engine stays pure; the keyboard
// extension fills these fields on each refresh.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public protocol EnglishSystemLexiconProviding: AnyObject {
    func completions(prefix: String, limit: Int) -> [String]
    func guesses(for word: String, limit: Int) -> [String]
}

@MainActor
public final class EmptyEnglishSystemLexicon: EnglishSystemLexiconProviding {
    public init() {}

    public func completions(prefix: String, limit: Int) -> [String] {
        []
    }

    public func guesses(for word: String, limit: Int) -> [String] {
        []
    }
}

#if canImport(UIKit)
/// System spellchecker. Always called from `TypingSessionController` (@MainActor).
@MainActor
public final class UIKitEnglishSystemLexicon: EnglishSystemLexiconProviding {
    public var language: String

    public init(language: String = "en_US") {
        self.language = language
    }

    public func completions(prefix: String, limit: Int) -> [String] {
        guard !prefix.isEmpty, limit > 0 else { return [] }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        let hits = checker.completions(forPartialWordRange: range, in: prefix, language: language) ?? []
        return Array(hits.prefix(limit))
    }

    public func guesses(for word: String, limit: Int) -> [String] {
        guard word.count >= 3, limit > 0 else { return [] }
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let hits = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        return Array(hits.prefix(limit))
    }

    public static func learnWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !UITextChecker.hasLearnedWord(trimmed) {
            UITextChecker.learnWord(trimmed)
        }
    }
}
#endif

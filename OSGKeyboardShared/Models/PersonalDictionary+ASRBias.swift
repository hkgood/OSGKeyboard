// PersonalDictionary+ASRBias.swift
// OSGKeyboard · Shared
//
// Formats the user dictionary for cloud ASR bias (hotwords, Alibaba
// vocabulary entries, or Whisper-style prompt fragments).

import Foundation
import CryptoKit

public struct AlibabaHotwordEntry: Codable, Sendable, Equatable {
    public let text: String
    public let weight: Int
    public let lang: String?

    public init(text: String, weight: Int = 4, lang: String? = nil) {
        self.text = text
        self.weight = weight
        self.lang = lang
    }
}

extension PersonalDictionary {
    /// Stable fingerprint used to decide when to refresh Alibaba vocabulary.
    public func vocabularySyncFingerprint() -> String {
        let payload = effectiveEntries
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
            .map { entry in
                let aliases = entry.aliases
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .joined(separator: ",")
                return "\(entry.term.lowercased())|\(aliases)"
            }
            .joined(separator: ";")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 智谱 `hotwords` — canonical terms only (aliases go to `asrPromptBias`).
    public func asrHotwords(maxCount: Int = 100) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for entry in effectiveEntries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            let key = term.lowercased()
            guard seen.insert(key).inserted else { continue }
            words.append(term)
            if words.count >= maxCount { break }
        }
        return words
    }

    /// 阿里百炼热词表 — `text` + `weight` (+ optional `lang`).
    public func alibabaHotwordEntries(maxCount: Int = 500, defaultWeight: Int = 4) -> [AlibabaHotwordEntry] {
        var seen = Set<String>()
        var entries: [AlibabaHotwordEntry] = []
        for entry in effectiveEntries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= 15 else { continue }
            let key = term.lowercased()
            guard seen.insert(key).inserted else { continue }
            entries.append(
                AlibabaHotwordEntry(
                    text: term,
                    weight: defaultWeight,
                    lang: Self.inferAlibabaLang(for: term)
                )
            )
            if entries.count >= maxCount { break }
        }
        return entries
    }

    /// Whisper / OpenAI-style short prompt bias (also used by MiMo text hint).
    public func asrPromptBias(maxCharacters: Int = 800) -> String {
        let entries = effectiveEntries
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []
        for entry in entries {
            if entry.aliases.isEmpty {
                lines.append(entry.term)
            } else {
                let aliasHint = entry.aliases.prefix(4).joined(separator: ", ")
                lines.append("\(entry.term)（常见误识别：\(aliasHint)）")
            }
            let joined = lines.joined(separator: "；")
            if joined.count > maxCharacters {
                if lines.count == 1 {
                    return String(joined.prefix(maxCharacters))
                }
                lines.removeLast()
                break
            }
        }

        guard !lines.isEmpty else { return "" }
        let body = lines.joined(separator: "；")
        return "用户专有词汇，转写时请优先使用以下标准写法：\(body)"
    }

    /// Compact domain context for Alibaba Fun-ASR Flash `input_text`.
    public func alibabaContextText(maxCharacters: Int = 1200) -> String {
        let prompt = asrPromptBias(maxCharacters: maxCharacters)
        guard !prompt.isEmpty else { return "" }
        return prompt
    }

    private static func inferAlibabaLang(for term: String) -> String? {
        let hasNonASCII = term.unicodeScalars.contains { !$0.isASCII }
        if hasNonASCII { return "zh" }
        return "en"
    }

    /// Alias → canonical term pairs for deterministic post-ASR correction.
    /// Sorted longest-alias-first by the caller (`LocalASRTranscriptCorrector`).
    public func localCorrectionPairs() -> [LocalASRCorrectionPair] {
        var seen = Set<String>()
        var pairs: [LocalASRCorrectionPair] = []
        for entry in effectiveEntries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            for alias in entry.aliases {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard trimmed.caseInsensitiveCompare(term) != .orderedSame else { continue }
                let key = "\(trimmed.lowercased())|\(term.lowercased())"
                guard seen.insert(key).inserted else { continue }
                pairs.append(LocalASRCorrectionPair(alias: trimmed, term: term))
            }
        }
        return pairs.sorted { lhs, rhs in
            if lhs.alias.count != rhs.alias.count {
                return lhs.alias.count > rhs.alias.count
            }
            return lhs.alias.localizedCaseInsensitiveCompare(rhs.alias) == .orderedAscending
        }
    }
}

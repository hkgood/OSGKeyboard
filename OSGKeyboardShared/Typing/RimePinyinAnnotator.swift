// RimePinyinAnnotator.swift
// OSGKeyboard · Shared
//
// Builds phrase / character pinyin maps from the bundled osg_pinyin
// dictionary so PersonalDictionary terms can be coded for Rime without
// shipping a second pronunciation dataset.

import Foundation

public struct RimePinyinAnnotator: Sendable {
    private let phraseCodes: [String: String]
    private let characterCodes: [String: String]

    public init(phraseCodes: [String: String], characterCodes: [String: String]) {
        self.phraseCodes = phraseCodes
        self.characterCodes = characterCodes
    }

    /// Parses `osg_pinyin.dict.yaml` (text / code / weight columns).
    /// When duplicate texts exist, keeps the highest-weight code.
    public static func load(from dictYAML: URL) throws -> RimePinyinAnnotator {
        let raw = try String(contentsOf: dictYAML, encoding: .utf8)
        var phraseCodes: [String: (code: String, weight: Int)] = [:]
        var characterCodes: [String: (code: String, weight: Int)] = [:]
        var inBody = false

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "..." {
                inBody = true
                continue
            }
            guard inBody, !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let text = String(parts[0])
            let code = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !code.isEmpty else { continue }
            let weight = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0

            if let existing = phraseCodes[text] {
                if weight >= existing.weight {
                    phraseCodes[text] = (code, weight)
                }
            } else {
                phraseCodes[text] = (code, weight)
            }

            if text.count == 1, Self.isCJKIdeograph(text.unicodeScalars.first!) {
                if let existing = characterCodes[text] {
                    if weight >= existing.weight {
                        characterCodes[text] = (code, weight)
                    }
                } else {
                    characterCodes[text] = (code, weight)
                }
            }
        }

        return RimePinyinAnnotator(
            phraseCodes: phraseCodes.mapValues(\.code),
            characterCodes: characterCodes.mapValues(\.code)
        )
    }

    /// Returns a Rime speller code (space-separated syllables / Latin tokens),
    /// or `nil` when any CJK character cannot be annotated.
    public func code(for term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let exact = phraseCodes[trimmed] {
            return exact
        }

        var parts: [String] = []
        for run in Self.scriptRuns(in: trimmed) {
            switch run.kind {
            case .cjk:
                if let phrase = phraseCodes[run.text] {
                    parts.append(phrase)
                    continue
                }
                var syllables: [String] = []
                for character in run.text {
                    let key = String(character)
                    guard let syllable = characterCodes[key] else { return nil }
                    syllables.append(syllable)
                }
                parts.append(syllables.joined(separator: " "))
            case .latin:
                let latin = Self.latinSpellerCode(run.text)
                guard !latin.isEmpty else { continue }
                parts.append(latin)
            case .other:
                continue
            }
        }

        let joined = parts.joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Script helpers

    private enum RunKind {
        case cjk
        case latin
        case other
    }

    private struct ScriptRun {
        let kind: RunKind
        let text: String
    }

    private static func scriptRuns(in term: String) -> [ScriptRun] {
        var runs: [ScriptRun] = []
        var currentKind: RunKind?
        var buffer = ""

        func flush() {
            guard let kind = currentKind, !buffer.isEmpty else { return }
            runs.append(ScriptRun(kind: kind, text: buffer))
            buffer = ""
            currentKind = nil
        }

        for scalar in term.unicodeScalars {
            let kind: RunKind
            if isCJKIdeograph(scalar) {
                kind = .cjk
            } else if scalar.isASCII, CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || scalar == "-" || scalar == "'" || scalar == "_" {
                kind = .latin
            } else if scalar == " " || scalar == "\u{3000}" {
                flush()
                continue
            } else {
                kind = .other
            }

            if currentKind == nil {
                currentKind = kind
                buffer = String(scalar)
            } else if currentKind == kind {
                buffer.append(Character(scalar))
            } else {
                flush()
                currentKind = kind
                buffer = String(scalar)
            }
        }
        flush()
        return runs
    }

    /// Speller alphabet is a–z only; strip everything else and lowercase.
    public static func latinSpellerCode(_ raw: String) -> String {
        var output = ""
        for scalar in raw.lowercased().unicodeScalars {
            guard scalar.isASCII, CharacterSet.lowercaseLetters.contains(scalar) else { continue }
            output.append(Character(scalar))
        }
        return output
    }

    public static func isCJKIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    public static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isCJKIdeograph)
    }
}

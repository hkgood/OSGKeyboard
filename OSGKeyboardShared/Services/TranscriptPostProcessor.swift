// TranscriptPostProcessor.swift
// OSGKeyboard · Shared
//
// Deterministic post-processing after the LLM polish step. The LLM
// handles semantic punctuation and structure; this module enforces
// hard output constraints (emoji ban, list normalization, quality
// gate) and decides when ultra-short inputs can skip the LLM entirely.

import Foundation

public enum TranscriptPostProcessor: Sendable {

    /// Result of the quality gate applied to LLM output.
    public enum GateDecision: Equatable, Sendable {
        case accept(String)
        case fallback(String)
    }

    // MARK: - Short-circuit gate (skip LLM)

    /// Returns `true` when the transcript is short enough and lacks
    /// structural signals so calling the LLM would add latency without
    /// meaningful benefit (e.g. "好", "OK", "明天见").
    public static func shouldSkipLLM(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if hasStructureSignal(in: trimmed) { return false }

        let cjkCount = trimmed.unicodeScalars.filter(isCJKScalar).count
        if cjkCount > 0 {
            // e.g. 好, 嗯, 收到, 明天见
            return trimmed.count <= 4 && cjkCount <= 4
        }

        // e.g. OK, yes, thanks — single short token only
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count == 1 && trimmed.count <= 10
    }

    /// Local-only cleanup when the LLM is skipped. Keeps the speaker's
    /// words verbatim — no punctuation invention beyond trimming.
    public static func localClean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Post-LLM pipeline

    /// Apply deterministic cleanup and quality gate to LLM output.
    public static func process(original: String, llmOutput: String) -> String {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = qualityGate(original: trimmedOriginal, candidate: llmOutput)
        switch decision {
        case .accept(let text):
            return text
        case .fallback(let text):
            return text
        }
    }

    /// Quality gate: clean the LLM output deterministically.
    ///
    /// Design note: earlier revisions reverted to the *raw ASR*
    /// transcript when numbers changed or the text grew "too much".
    /// That was wrong — listifying and correcting ASR mis-hearings
    /// (e.g. "第2:00" → "第二点") legitimately change the number set,
    /// so the heuristic threw away good output and re-inserted the raw,
    /// mis-heard transcript (the worst possible text). We now only fall
    /// back when the model returned genuinely unusable output (empty, or
    /// pure explanation), and even then we prefer a cleaned candidate
    /// over the raw transcript.
    public static func qualityGate(original: String, candidate: String) -> GateDecision {
        var text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            return .fallback(localClean(original))
        }

        text = stripExplanatoryPrefix(from: text)
        text = unwrapSurroundingQuotes(text)
        text = stripAddedEmojis(original: original, output: text)
        text = repairMidSentenceLineBreaks(text)
        text = normalizeWhitespaceAndPunctuation(text)
        text = normalizeNumberedLists(text)

        // If cleanup emptied the candidate (e.g. it was only an
        // explanatory prefix), fall back to the trimmed original rather
        // than the raw ASR — that is still the least-bad option here.
        if text.isEmpty {
            return .fallback(localClean(original))
        }

        return .accept(text)
    }

    // MARK: - Structure detection

    /// Whether the transcript contains oral enumeration / section cues.
    public static func hasStructureSignal(in text: String) -> Bool {
        let patterns = [
            #"第[一二三四五六七八九十\d]+[点个条段步部分]"#,
            #"步骤[一二三四五六七八九十\d]+"#,
            #"[一二三四五六七八九十]+是"#,
            #"首先|其次|再次|最后|另外|再者|一方面|另一方面"#,
            #"\b(first|second|third|fourth|fifth|finally|next|another)\b"#,
            #"\b(step\s*(one|two|three|four|five|\d+))\b"#,
            #"point\s*(one|two|three|four|five|\d+)"#,
        ]
        for pattern in patterns {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Emoji

    /// Remove emojis from output when the original had none; otherwise
    /// keep only emojis that appeared in the original.
    public static func stripAddedEmojis(original: String, output: String) -> String {
        let originalEmojis = Set(extractEmojis(from: original))
        if originalEmojis.isEmpty {
            return removeAllEmojis(from: output)
        }
        return String(output.unicodeScalars.filter { scalar in
            if isEmojiScalar(scalar) {
                return originalEmojis.contains(String(scalar))
            }
            return true
        })
    }

    // MARK: - List normalization

    /// Matches a line that begins with any list marker we recognize
    /// (bullet, arabic number, 第X点, 步骤X).
    static let listLinePattern =
        #"^\s*(?:[-*•]|\d+[.)）、]|第[一二三四五六七八九十\d]+[点.)）、]|步骤[一二三四五六七八九十\d]+[.)）、]?)\s+"#

    /// Whether a line is a list item.
    static func isListLine(_ text: String) -> Bool {
        text.range(of: listLinePattern, options: .regularExpression) != nil
    }

    /// Normalize heterogeneous numbered-list markers to `1. ` style.
    public static func normalizeNumberedLists(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var listIndex = 0
        var inList = false

        for i in lines.indices {
            let line = lines[i]
            guard let range = line.range(of: listLinePattern, options: .regularExpression) else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    inList = false
                    listIndex = 0
                }
                continue
            }
            let content = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !inList { listIndex = 0 }
            listIndex += 1
            inList = true
            lines[i] = "\(listIndex). \(content)"
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Mid-sentence line-break repair

    /// Join line breaks that split a sentence. A newline is kept only
    /// when it is a paragraph break (blank line), a list boundary, or
    /// the previous line ends with a sentence terminator. Otherwise the
    /// break is treated as an ASR chunk-stitch artifact (e.g.
    /// "包括\n这些问题") and merged back into one line.
    public static func repairMidSentenceLineBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        var out: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let last = out.last else {
                out.append(line)
                continue
            }
            let prevTrimmed = last.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || prevTrimmed.isEmpty
                || isListLine(trimmed) || isListLine(prevTrimmed)
                || endsWithSentenceTerminator(prevTrimmed) {
                out.append(line)
                continue
            }

            out[out.count - 1] = prevTrimmed + joinGlue(prev: prevTrimmed, next: trimmed) + trimmed
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Whitespace / punctuation cleanup

    public static func normalizeWhitespaceAndPunctuation(_ text: String) -> String {
        var result = text
        // Collapse 3+ newlines to 2.
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        // Collapse duplicate Chinese / Western punctuation.
        let dupPairs = [
            ("。。", "。"), ("，，", "，"), ("？？", "？"), ("！！", "！"),
            ("..", "."), (",,", ","), ("??", "?"), ("!!", "!"),
        ]
        for (dup, single) in dupPairs {
            while result.contains(dup) {
                result = result.replacingOccurrences(of: dup, with: single)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prefix / quote cleanup

    public static func stripExplanatoryPrefix(from text: String) -> String {
        let prefixes = [
            "以下是", "处理后", "处理后的文本", "输出如下", "结果如下",
            "Here is", "Here's", "Output:", "Result:", "Processed text:",
        ]
        var result = text
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if result.hasPrefix(":") || result.hasPrefix("：") {
                    result = String(result.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return result
    }

    public static func unwrapSurroundingQuotes(_ text: String) -> String {
        guard text.count >= 2 else { return text }
        let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("「", "」"), ("“", "”")]
        for (open, close) in pairs {
            if text.first == open, text.last == close {
                return String(text.dropFirst().dropLast())
            }
        }
        return text
    }

    // MARK: - Private helpers

    private static func endsWithSentenceTerminator(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        let terminators: Set<Unicode.Scalar> = [
            "。", "！", "？", "…", "!", "?", ".", ";", "；", "：", ":",
        ]
        return terminators.contains(last)
    }

    /// Decide the glue between two merged fragments: a space only when
    /// both sides are ASCII alphanumeric (English words); nothing for CJK.
    private static func joinGlue(prev: String, next: String) -> String {
        guard let p = prev.unicodeScalars.last, let n = next.unicodeScalars.first else { return "" }
        let alphanumerics = CharacterSet.alphanumerics
        let pAscii = p.isASCII && alphanumerics.contains(p)
        let nAscii = n.isASCII && alphanumerics.contains(n)
        return (pAscii && nAscii) ? " " : ""
    }

    private static func extractEmojis(from text: String) -> [String] {
        text.unicodeScalars.filter(isEmojiScalar).map { String($0) }
    }

    private static func removeAllEmojis(from text: String) -> String {
        String(text.unicodeScalars.filter { !isEmojiScalar($0) })
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && (scalar.value > 0x238C || scalar.properties.isEmojiPresentation)
    }

    private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

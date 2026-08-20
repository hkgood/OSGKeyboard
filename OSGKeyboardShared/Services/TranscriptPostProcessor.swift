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
    /// structural / communicative signals so calling the LLM would add
    /// latency without meaningful benefit.
    ///
    /// Two tiers:
    /// - **Tier 1 (≤4 CJK / short English token):** always skip when
    ///   structure-free (e.g. "好", "OK", "明天见").
    /// - **Tier 2 (5–10 CJK):** skip only low-value acks / closings
    ///   (e.g. "好的我知道了", "那就先这样吧"); keep questions, invites,
    ///   and contentful short lines for polish / ASR repair.
    public static func shouldSkipLLM(
        for text: String,
        styleID: String? = nil
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if hasStructureSignal(in: trimmed) { return false }
        // Every fun personality handles short and long drafts in one prompt.
        if let styleID, PolishStylePackCatalog.isFunPersonality(id: styleID) {
            return false
        }

        let cjkCount = trimmed.unicodeScalars.filter(HanScript.isIdeograph).count
        if cjkCount > 0 {
            // Tier 1 — ultra-short
            if trimmed.count <= 4 && cjkCount <= 4 {
                return true
            }
            // Tier 2 — short ack / closing only
            if trimmed.count <= 10 && cjkCount <= 10 {
                return isTier2SkipUtterance(trimmed)
            }
            return false
        }

        // e.g. OK, yes, thanks — single short token only
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        return words.count == 1 && trimmed.count <= 10
    }

    /// Tier-2 skip: 5–10 character Chinese that is only a confirmation,
    /// status, or closing — not a question, invite, or contentful line.
    public static func isTier2SkipUtterance(_ text: String) -> Bool {
        let stripped = stripLeadingFillers(text)
        if stripped.isEmpty { return true }
        let cjk = stripped.unicodeScalars.filter(HanScript.isIdeograph).count
        if stripped.count <= 4 && cjk <= 4 { return true }

        if hasCommunicativeSignal(stripped) { return false }
        if hasOpponentQuote(stripped) { return false }
        if hasConcreteEntity(stripped) { return false }

        for pattern in tier2SkipPatterns {
            if stripped.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static let tier2SkipPatterns: [String] = [
        #"^(好的?|行|可以|收到|谢谢|麻烦了|没事|不用了|知道了|明白了|没问题|辛苦了|对的?)(啦|了|啊|呢|哦|呀)?$"#,
        #"^(好的?)?(我)?(知道|明白)了$"#,
        #"^(好的我知道了|收到谢谢|麻烦你了)$"#,
        #"^(那就)?先这样(吧|了|啦)?$"#,
        #"^(晚点|待会|一会儿|呆会)(再)?(说|联系|聊|讲)(吧|了|啊)?$"#,
        #"^(我)?(马上|立刻|这就)?(就)?到了$"#,
        #"^(好的?|嗯)?(收到|谢谢)(你|啦|了|啊)?$"#,
        #"^(没事)?(不用|别)(了|啦)?(谢谢)?$"#,
        #"^(晚安|早安|早上好|拜拜|再见)(啦|了|啊)?$"#,
        #"^(晚点再说|待会联系|先这样吧|马上到了)$"#
    ]

    private static func hasCommunicativeSignal(_ text: String) -> Bool {
        if text.contains("？") || text.contains("?") { return true }
        let patterns = [
            #"吗|么|怎么|什么|哪|谁|为何|为什么|为啥"#,
            #"能不能|可不可以|要不要|行不行"#,
            #"回他|回她"#,
            #"约|见面|吃饭|电影"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func hasOpponentQuote(_ text: String) -> Bool {
        let markers = ["回他", "回她", "对方", "他说", "她说", "你说的", "你这叫", "大家都"]
        return markers.contains { text.contains($0) }
    }

    private static func hasConcreteEntity(_ text: String) -> Bool {
        let entities = [
            "面膜", "防晒", "口红", "粉底", "洗发", "咖啡", "火锅", "酒店", "餐厅",
            "方案", "接口", "测试", "Key", "老板", "电影", "地铁", "快递", "会议",
            "周报", "加班", "机票", "医院", "课程", "健身", "外卖", "微信", "项目",
            "发布", "文档", "密码", "充电器", "门卡"
        ]
        return entities.contains { text.contains($0) }
    }

    private static let leadingFillers = [
        "怎么说呢", "就是说", "然后那个", "嗯那个", "那个", "嗯", "呃"
    ]

    private static func stripLeadingFillers(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for filler in leadingFillers.sorted(by: { $0.count > $1.count }) {
            if result.hasPrefix(filler) {
                result = String(result.dropFirst(filler.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    /// Local-only cleanup when the LLM is skipped. Keeps the speaker's
    /// words verbatim — no punctuation invention beyond trimming.
    public static func localClean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Last-resort deterministic polish after repeated validation failure.
    /// This intentionally does not invent punctuation or rewrite words.
    public static func minimalPolish(_ text: String) -> String {
        var result = stripPauseMarkers(from: text)
        let fillerPattern =
            #"(^|[\s，,。.!！？?；;：:])(?:嗯|呃|啊|那个|um|uh|er)(?=$|[\s，,。.!！？?；;：:])"#
        result = result.replacingOccurrences(
            of: fillerPattern,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        result = collapseHorizontalWhitespace(result)
        return normalizeWhitespaceAndPunctuation(result)
    }

    /// Conservative cleanup for raw ASR fallback delivery. This is used when
    /// polish/translation cannot run, so it must not rewrite meaning or invent
    /// punctuation; it only removes formatting artifacts that ASR/chunking can
    /// introduce.
    public static func cleanRawASRFallback(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = repairMidSentenceLineBreaks(result)
        result = collapseHorizontalWhitespace(result)
        result = removeCJKBoundarySpaces(result)
        result = normalizePunctuationSpacing(result)
        return normalizeWhitespaceAndPunctuation(result)
    }

    // MARK: - Post-LLM pipeline

    /// Apply deterministic cleanup and quality gate to LLM output.
    public static func process(
        original: String,
        llmOutput: String,
        allowsAddedEmoji: Bool = false
    ) -> String {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = qualityGate(
            original: trimmedOriginal,
            candidate: llmOutput,
            allowsAddedEmoji: allowsAddedEmoji
        )
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
    public static func qualityGate(
        original: String,
        candidate: String,
        allowsAddedEmoji: Bool = false
    ) -> GateDecision {
        var text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            return .fallback(localClean(original))
        }

        text = stripExplanatoryPrefix(from: text)
        text = stripPauseMarkers(from: text)
        text = unwrapSurroundingQuotes(text)
        if !allowsAddedEmoji {
            text = stripAddedEmojis(original: original, output: text)
        }
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

    public static func stripPauseMarkers(from text: String) -> String {
        text.replacingOccurrences(
            of: #"⟨[^⟩]{0,12}⟩"#,
            with: "",
            options: .regularExpression
        )
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
            #"point\s*(one|two|three|four|five|\d+)"#
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
            ("..", "."), (",,", ","), ("??", "?"), ("!!", "!")
        ]
        for (dup, single) in dupPairs {
            while result.contains(dup) {
                result = result.replacingOccurrences(of: dup, with: single)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseHorizontalWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"[^\S\r\n]+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func removeCJKBoundarySpaces(_ text: String) -> String {
        var output = ""
        let characters = Array(text)
        for index in characters.indices {
            let current = characters[index]
            if current.isWhitespace,
               let previous = previousNonWhitespace(in: characters, before: index),
               let next = nextNonWhitespace(in: characters, after: index),
               shouldDropSpaceBetween(previous: previous, next: next) {
                continue
            }
            output.append(current)
        }
        return output
    }

    private static func normalizePunctuationSpacing(_ text: String) -> String {
        var output = ""
        let characters = Array(text)
        for index in characters.indices {
            let current = characters[index]
            if current.isWhitespace,
               let next = nextNonWhitespace(in: characters, after: index),
               isClosingPunctuation(next) {
                continue
            }
            if isOpeningPunctuation(current),
               let next = nextNonWhitespace(in: characters, after: index),
               next.isWhitespace {
                output.append(current)
                continue
            }
            output.append(current)
        }
        return output
            .replacingOccurrences(of: #"([（「“])\s+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([，。！？；：、,.!?;:])"#, with: "$1", options: .regularExpression)
    }

    // MARK: - Prefix / quote cleanup

    public static func stripExplanatoryPrefix(from text: String) -> String {
        let prefixes = [
            "以下是", "处理后", "处理后的文本", "输出如下", "结果如下",
            "Here is", "Here's", "Output:", "Result:", "Processed text:"
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
            "。", "！", "？", "…", "!", "?", ".", ";", "；", "：", ":"
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

    private static func previousNonWhitespace(in characters: [Character], before index: Int) -> Character? {
        guard index > characters.startIndex else { return nil }
        for i in stride(from: index - 1, through: characters.startIndex, by: -1) {
            if !characters[i].isWhitespace { return characters[i] }
        }
        return nil
    }

    private static func nextNonWhitespace(in characters: [Character], after index: Int) -> Character? {
        let nextIndex = index + 1
        guard nextIndex < characters.endIndex else { return nil }
        for i in nextIndex..<characters.endIndex {
            if !characters[i].isWhitespace { return characters[i] }
        }
        return nil
    }

    private static func shouldDropSpaceBetween(previous: Character, next: Character) -> Bool {
        (isCJKCharacter(previous) && isCJKCharacter(next)) || isClosingPunctuation(next)
    }

    private static func isCJKCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains(where: HanScript.isIdeograph)
    }

    private static func isClosingPunctuation(_ character: Character) -> Bool {
        let closing: Set<Character> = ["，", "。", "！", "？", "；", "：", "、", ",", ".", "!", "?", ";", ":"]
        return closing.contains(character)
    }

    private static func isOpeningPunctuation(_ character: Character) -> Bool {
        let opening: Set<Character> = ["（", "「", "“"]
        return opening.contains(character)
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
}

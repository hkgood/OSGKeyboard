// ClipboardSkillSemanticRanker.swift
// OSGKeyboard · Shared
//
// Selects skills from the complete catalog for the newest accepted clipboard
// entry. Analysis is local and ephemeral; installation state, user-managed
// ordering, labels, and recommendations are never persisted.

import Combine
import Foundation

public enum ClipboardSkillSemanticRanker {
    /// Calibrated against Latin script. `effectiveLength` scales dense scripts
    /// up to the same information density before comparing.
    private static let longTextLengthThreshold = 360.0
    /// Branch-side raw character gate. Kept alongside the density-aware
    /// `longTextLengthThreshold` because the two are used by different
    /// call sites: intent routing counts characters, while the summary and
    /// list heuristics weight CJK density via `effectiveLength`.
    private static let longTextCharacterThreshold = 360
    private static let listLineLengthThreshold = 48.0
    private static let denseScriptCharacterWeight = 2.25
    /// A bare link or phone paste keeps at most a short label ("详情：",
    /// "Contact:"). Anything longer means the entity is embedded in a real
    /// message, which must keep its own skills.
    private static let entityResidualLengthLimit = 12
    private static let languageConfidenceThreshold = 0.75
    /// Characters permitted in a URL, used to carve the link out of text with no
    /// whitespace around it (`详见https://example.com`). Deliberately spelled out
    /// in ASCII: `CharacterSet.alphanumerics` also matches CJK ideographs, which
    /// would swallow the surrounding message.
    private static let urlCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "0123456789"
            + "-._~:/?#[]@!$&'()*+,;=%"
    )

    public static func ranked(
        skills: [AIClipboardSkill],
        sourceText: String,
        analysis: ClipboardSemanticAnalysis,
        uiLanguage _: AppUILanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [AIClipboardSkill] {
        guard skills.count > 1 else { return skills }
        return sorted(
            skills,
            scores: relevanceScores(
                sourceText: sourceText,
                analysis: analysis,
                preferredLanguages: preferredLanguages
            )
        )
    }

    /// Returns semantically relevant skills and keeps generic Reply as a safe
    /// fallback unless a display-only boundary intent suppresses human routing.
    public static func recommended(
        skills: [AIClipboardSkill],
        sourceText: String,
        analysis: ClipboardSemanticAnalysis,
        uiLanguage _: AppUILanguage,
        limit: Int,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [AIClipboardSkill] {
        guard limit > 0 else { return [] }
        var scores = relevanceScores(
            sourceText: sourceText,
            analysis: analysis,
            preferredLanguages: preferredLanguages
        )
        let genericReply = suppressesInterpersonalRouting(analysis, sourceText: sourceText)
            ? nil
            : skills.first { $0.id == AIClipboardSkillCatalog.replyID }
        if genericReply != nil {
            scores[AIClipboardSkillCatalog.replyID, default: 0] = max(
                1,
                scores[AIClipboardSkillCatalog.replyID, default: 0]
            )
        }
        let relevant = skills.filter { scores[$0.id, default: 0] > 0 }
        var selected: [AIClipboardSkill] = []
        for skill in sorted(relevant, scores: scores) {
            let mustReserveGenericReply = genericReply != nil
                && !selected.contains(where: { $0.id == AIClipboardSkillCatalog.replyID })
                && skill.id != AIClipboardSkillCatalog.replyID
            let availableCount = limit - (mustReserveGenericReply ? 1 : 0)
            guard selected.count < availableCount else { continue }
            if skill.id == AIClipboardSkillCatalog.replyID {
                selected.append(skill)
                continue
            }
            selected.append(skill)
        }
        if let genericReply,
           selected.count < limit,
           !selected.contains(where: { $0.id == genericReply.id }) {
            selected.append(genericReply)
        }
        // "Speak as me" rewrites the user's own draft, which no clipboard
        // signal can detect — nothing in `relevanceScores` can ever score it,
        // so it would never surface on its own. It reaches this list only when
        // the user has a personal style and opted the skill in, so it is
        // offered as a trailing fallback: never displacing a content match,
        // and leaving the "is this my own text?" judgement to the user.
        if let speakAsMe = skills.first(where: { $0.id == AIClipboardSkillCatalog.speakAsMeID }),
           selected.count < limit,
           !selected.contains(where: { $0.id == speakAsMe.id }) {
            selected.append(speakAsMe)
        }
        return selected
    }

    private static func relevanceScores(
        sourceText: String,
        analysis: ClipboardSemanticAnalysis,
        preferredLanguages: [String]
    ) -> [String: Int] {
        var scores: [String: Int] = [:]
        func boost(_ id: String, _ value: Int) {
            scores[id, default: 0] += value
        }

        // A bare link or phone paste has no other intent to serve, so it stays
        // exclusive. One embedded in a message must not suppress the skills the
        // message itself earns — scoring continues at a weight that still ranks
        // the direct action high without outranking a strong message intent.
        if let webURL = analysis.singleWebURL {
            let isBarePaste = isWebLinkDominant(sourceText, url: webURL)
            boost(AIClipboardSkillCatalog.openLinkID, isBarePaste ? 320 : 200)
            if webURL.scheme?.lowercased() == "https" {
                boost(AIClipboardSkillCatalog.summarizeWebPageID, isBarePaste ? 310 : 150)
            }
            if isBarePaste {
                return scores
            }
        }

        if analysis.singlePhoneNumber != nil {
            let isBarePaste = isPhoneNumberDominant(sourceText)
            boost(AIClipboardSkillCatalog.callPhoneID, isBarePaste ? 320 : 200)
            boost(AIClipboardSkillCatalog.createContactID, isBarePaste ? 310 : 150)
            if isBarePaste {
                return scores
            }
        }

        if isLanguageMismatch(
            analysis.language,
            preferredLanguages: preferredLanguages
        ) {
            boost(AIClipboardSkillCatalog.translateID, 230)
        }

        if analysis.hasAddress {
            boost(AIClipboardSkillCatalog.navigateID, 180)
        }

        // An explicit "please reply" is the strongest Reply signal there is: it
        // must win even over a date (Events) or a command/query classification,
        // so a message that asks for a response actually auto-replies instead of
        // ranking Events/other first. Scored above every non-bare-entity boost.
        if hasExplicitReplyRequest(sourceText) {
            boost(AIClipboardSkillCatalog.replyID, 340)
        }

        let suppressesInterpersonalRouting = suppressesInterpersonalRouting(
            analysis,
            sourceText: sourceText
        )
        if !suppressesInterpersonalRouting {
            if isRoutingEvidence(analysis.invitation) {
                if analysis.hasDateOrTime {
                    boost(AIClipboardSkillCatalog.extractEventsID, 260)
                }
                boost(AIClipboardSkillCatalog.replyID, 300)
            } else if analysis.hasDateOrTime {
                boost(AIClipboardSkillCatalog.extractEventsID, 110)
            }
        } else if analysis.hasDateOrTime {
            boost(AIClipboardSkillCatalog.extractEventsID, 110)
        }

        if !suppressesInterpersonalRouting {
            // A threshold-crossing, evaluation-gated model may still rank a
            // reversible chip; execution always remains explicitly user-initiated.
            if isRoutingEvidence(analysis.scheduleNegotiation) {
                boost(AIClipboardSkillCatalog.extractEventsID, 200)
                boost(AIClipboardSkillCatalog.replyID, 300)
            }

            if isRoutingEvidence(analysis.confirmationDecision) {
                boost(AIClipboardSkillCatalog.replyID, 300)
            }

            if isRoutingEvidence(analysis.followUpReminder) {
                boost(AIClipboardSkillCatalog.extractTodosID, 285)
                boost(AIClipboardSkillCatalog.replyID, 250)
            }

            if isRoutingEvidence(analysis.task) {
                boost(AIClipboardSkillCatalog.extractTodosID, 155)
                boost(AIClipboardSkillCatalog.replyID, 140)
            }

            if isRoutingEvidence(analysis.question) {
                boost(AIClipboardSkillCatalog.replyID, 145)
            }

            if isRoutingEvidence(analysis.blessing) {
                boost(AIClipboardSkillCatalog.replyID, 300)
            }

            if isRoutingEvidence(analysis.complaint) {
                boost(AIClipboardSkillCatalog.replyID, 105)
            } else if analysis.sentiment == .negative,
                      isRoutingEvidence(analysis.question) {
                boost(AIClipboardSkillCatalog.replyID, 85)
            }

            if analysis.hasOrganizationName,
               isRoutingEvidence(analysis.task)
                || isRoutingEvidence(analysis.question)
                || isRoutingEvidence(analysis.invitation) {
                boost(AIClipboardSkillCatalog.replyID, 125)
            } else if analysis.hasOrganizationName {
                boost(AIClipboardSkillCatalog.replyID, 70)
            }
        }

        if isListLike(sourceText) {
            boost(AIClipboardSkillCatalog.organizeListID, 145)
            boost(AIClipboardSkillCatalog.extractTodosID, 105)
            boost(AIClipboardSkillCatalog.summarizeID, 45)
        }

        if effectiveLength(sourceText) >= longTextLengthThreshold {
            boost(AIClipboardSkillCatalog.summarizeID, 145)
            boost(AIClipboardSkillCatalog.saveToNotesID, 85)
        }

        if !suppressesInterpersonalRouting {
            let hasSpecializedReplyIntent = isRoutingEvidence(analysis.task)
                || isRoutingEvidence(analysis.question)
                || isRoutingEvidence(analysis.invitation)
                || isRoutingEvidence(analysis.scheduleNegotiation)
                || isRoutingEvidence(analysis.confirmationDecision)
                || isRoutingEvidence(analysis.followUpReminder)
                || isRoutingEvidence(analysis.blessing)
                || isRoutingEvidence(analysis.complaint)
            if analysis.replyableMessage.isDetected,
               !hasSpecializedReplyIntent,
               sourceText.count < longTextCharacterThreshold,
               !isListLike(sourceText) {
                boost(AIClipboardSkillCatalog.replyID, 160)
                if analysis.sentiment != .negative,
                   !isRoutingEvidence(analysis.complaint) {
                    // Reply now exposes ordinary, formal, and playful variants
                    // inside one action rather than ranking separate style skills.
                    boost(AIClipboardSkillCatalog.replyID, 145)
                }
            }
            if analysis.sentiment == .positive {
                boost(AIClipboardSkillCatalog.replyID, 45)
            }
        }
        applyDomainBoosts(
            analysis,
            sourceText: sourceText,
            suppressesInterpersonalRouting: suppressesInterpersonalRouting,
            boost: boost
        )
        return scores
    }

    private static func applyDomainBoosts(
        _ analysis: ClipboardSemanticAnalysis,
        sourceText: String,
        suppressesInterpersonalRouting: Bool,
        boost: (String, Int) -> Void
    ) {
        guard let domain = analysis.domain,
              let confidence = analysis.domainConfidence,
              confidence > 0 else {
            return
        }
        switch domain {
        case .calendar:
            if analysis.hasDateOrTime {
                boost(AIClipboardSkillCatalog.extractEventsID, 20)
            }
        case .travel:
            if analysis.hasAddress {
                boost(AIClipboardSkillCatalog.navigateID, 20)
            }
        case .media, .generalKnowledge:
            if sourceText.count >= longTextCharacterThreshold {
                boost(AIClipboardSkillCatalog.summarizeID, 15)
            }
        case .communication:
            if !suppressesInterpersonalRouting,
               hasInterpersonalRoutingEvidence(analysis) {
                boost(AIClipboardSkillCatalog.replyID, 15)
            }
        case .finance, .accountService:
            if !suppressesInterpersonalRouting,
               isRoutingEvidence(analysis.question)
                || isRoutingEvidence(analysis.complaint) {
                boost(AIClipboardSkillCatalog.replyID, 10)
            }
        case .smartHome, .shopping, .dining, .health, .weather:
            return
        }
    }

    private static func sorted(
        _ skills: [AIClipboardSkill],
        scores: [String: Int]
    ) -> [AIClipboardSkill] {
        let baseline = Dictionary(
            uniqueKeysWithValues: skills.enumerated().map { ($0.element.id, $0.offset) }
        )
        return skills.sorted { lhs, rhs in
            let leftScore = scores[lhs.id, default: 0]
            let rightScore = scores[rhs.id, default: 0]
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return baseline[lhs.id, default: 0] < baseline[rhs.id, default: 0]
        }
    }

    /// Public gate for auto-translate: true when the paste's detected language
    /// is confidently different from the device's primary language.
    public static func isForeignLanguage(
        _ analysis: ClipboardSemanticAnalysis,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bool {
        isLanguageMismatch(analysis.language, preferredLanguages: preferredLanguages)
    }

    /// Whether auto mode should draft a reply for this copy. Defined by
    /// exclusion, not by positive intent labels — the on-device model tags many
    /// ordinary chat messages (short statements, casual questions) with no
    /// routing intent, so requiring one would silently skip them. Auto-reply
    /// therefore fires for any copy that is NOT:
    ///   - a bare link / phone (those keep their own direct action),
    ///   - foreign text (that routes to Translate),
    ///   - a system notification (a delivery notice / code, nothing to answer),
    ///   - a long article or a pure list (better summarized / organized).
    /// Everything else reads as a message worth answering.
    public static func isAutoReplyEligible(
        sourceText: String,
        analysis: ClipboardSemanticAnalysis,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bool {
        if let url = analysis.singleWebURL, isWebLinkDominant(sourceText, url: url) {
            return false
        }
        if analysis.singlePhoneNumber != nil, isPhoneNumberDominant(sourceText) {
            return false
        }
        if isForeignLanguage(analysis, preferredLanguages: preferredLanguages) {
            return false
        }
        if isDisplayEvidence(analysis.systemNotification) {
            return false
        }
        if effectiveLength(sourceText) >= longTextLengthThreshold {
            return false
        }
        if isListLike(sourceText) {
            return false
        }
        return true
    }

    private static func isLanguageMismatch(
        _ language: ClipboardLanguageLabel?,
        preferredLanguages: [String]
    ) -> Bool {
        guard let language, language.confidence >= languageConfidenceThreshold else {
            return false
        }
        return !SystemLanguageResolver.isSameLanguage(
            sourceIdentifier: language.identifier,
            targetIdentifier: SystemLanguageResolver.primaryIdentifier(
                preferredLanguages: preferredLanguages
            )
        )
    }

    private static func isRoutingEvidence(_ label: ClipboardIntentLabel) -> Bool {
        label.isDetected && label.isApprovedForAutomaticRouting
    }

    private static func isDisplayEvidence(_ label: ClipboardIntentLabel) -> Bool {
        label.isDetected
            && label.confidence > 0
            && label.confidence >= label.threshold
    }

    private static func suppressesInterpersonalRouting(
        _ analysis: ClipboardSemanticAnalysis,
        sourceText: String = ""
    ) -> Bool {
        let looksLikeCommandOrQuery = isDisplayEvidence(analysis.assistantCommand)
            || isDisplayEvidence(analysis.informationQuery)
            || isDisplayEvidence(analysis.systemNotification)
        guard looksLikeCommandOrQuery else { return false }
        // A directive/query label must not strip Reply when the paste explicitly
        // asks for one — an imperative "请及时回复" is a message to reply to, not a
        // command to the assistant. The exemption is deliberately text-level:
        // keying it off interpersonal *labels* instead would disable suppression
        // outright, because the on-device models tag almost every display-only
        // paste as `replyableMessage` too.
        if hasExplicitReplyRequest(sourceText) { return false }
        return true
    }

    /// Deterministic "please reply" detector. An explicit request to respond is
    /// strong evidence the paste is a message to answer, overriding a command or
    /// information-query classification.
    private static func hasExplicitReplyRequest(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let lower = text.lowercased()
        let markers = [
            "回复", "回信", "回覆", "答复", "回个信", "回条信息", "回消息",
            "等你回", "尽快回", "及时回", "尽早回", "务必回", "记得回",
            "reply", "respond", "get back to me", "let me know", "your reply",
            "write back", "awaiting your response", "please answer"
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func hasInterpersonalRoutingEvidence(
        _ analysis: ClipboardSemanticAnalysis
    ) -> Bool {
        isRoutingEvidence(analysis.task)
            || isRoutingEvidence(analysis.question)
            || isRoutingEvidence(analysis.invitation)
            || isRoutingEvidence(analysis.complaint)
            || isRoutingEvidence(analysis.replyableMessage)
            || isRoutingEvidence(analysis.scheduleNegotiation)
            || isRoutingEvidence(analysis.confirmationDecision)
            || isRoutingEvidence(analysis.followUpReminder)
            || isRoutingEvidence(analysis.blessing)
    }

    private static func isListLike(_ text: String) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }

        let markedCount = lines.filter(isMarkedListLine).count
        if markedCount * 2 >= lines.count {
            return true
        }
        let averageLength = lines.reduce(0.0) {
            $0 + effectiveLength($1)
        } / Double(lines.count)
        return lines.count >= 3 && averageLength <= listLineLengthThreshold
    }

    /// CJK characters carry roughly twice the information of a Latin character,
    /// so a raw `count` makes every length threshold fire about twice too late
    /// in Chinese and too early in English. Weight dense scripts instead.
    private static func effectiveLength(_ text: String) -> Double {
        text.reduce(into: 0.0) { total, character in
            total += isDenseScriptCharacter(character) ? denseScriptCharacterWeight : 1
        }
    }

    private static func isDenseScriptCharacter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF,      // kana
             0x3400...0x4DBF,      // CJK unified ideographs extension A
             0x4E00...0x9FFF,      // CJK unified ideographs
             0xAC00...0xD7AF,      // hangul syllables
             0xF900...0xFAFF,      // CJK compatibility ideographs
             0x20000...0x2FA1F:    // CJK unified ideographs extensions B+
            return true
        default:
            return false
        }
    }

    private static func isWebLinkDominant(_ text: String, url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        guard let hostRange = text.range(of: host, options: [.caseInsensitive]) else {
            return significantCharacterCount(text) <= entityResidualLengthLimit
        }
        var start = hostRange.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isURLCharacter(text[previous]) else { break }
            start = previous
        }
        var end = hostRange.upperBound
        while end < text.endIndex, isURLCharacter(text[end]) {
            end = text.index(after: end)
        }
        var residual = text
        residual.removeSubrange(start..<end)
        return significantCharacterCount(residual) <= entityResidualLengthLimit
    }

    /// Digits belong to the number itself, so only letters count as residual.
    private static func isPhoneNumberDominant(_ text: String) -> Bool {
        text.reduce(into: 0) { count, character in
            if character.isLetter { count += 1 }
        } <= entityResidualLengthLimit
    }

    private static func significantCharacterCount(_ text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if character.isLetter || character.isNumber { count += 1 }
        }
    }

    private static func isURLCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { urlCharacters.contains($0) }
    }

    private static func isMarkedListLine(_ line: String) -> Bool {
        if ["- ", "* ", "• ", "· "].contains(where: { line.hasPrefix($0) }) {
            return true
        }
        let prefix = line.prefix(while: \.isNumber)
        guard !prefix.isEmpty, prefix.count < line.count else { return false }
        let marker = line[line.index(line.startIndex, offsetBy: prefix.count)]
        return marker == "." || marker == "、" || marker == ")" || marker == "）"
    }
}

public struct ClipboardSemanticRankingSnapshot: Equatable, Sendable {
    public let entryID: UUID
    public let analysis: ClipboardSemanticAnalysis

    public init(entryID: UUID, analysis: ClipboardSemanticAnalysis) {
        self.entryID = entryID
        self.analysis = analysis
    }
}

@MainActor
public final class ClipboardSemanticRankingStore: ObservableObject {
    public static let shared = ClipboardSemanticRankingStore()

    @Published public private(set) var snapshot: ClipboardSemanticRankingSnapshot?

    private let analyzeText: @Sendable (String) async -> ClipboardSemanticAnalysis
    private let shadowMetrics: ClipboardSemanticShadowMetricsStore?
    private var analysisTask: Task<Void, Never>?
    private var generation = UUID()

    public init(
        analyzer: ClipboardSemanticAnalyzer = ClipboardSemanticAnalyzer(),
        shadowMetrics: ClipboardSemanticShadowMetricsStore = .shared
    ) {
        analyzeText = { text in
            await analyzer.analyze(text)
        }
        self.shadowMetrics = shadowMetrics
    }

    init(
        analyzeText: @escaping @Sendable (String) async -> ClipboardSemanticAnalysis,
        shadowMetrics: ClipboardSemanticShadowMetricsStore? = nil
    ) {
        self.analyzeText = analyzeText
        self.shadowMetrics = shadowMetrics
    }

    public func analyze(_ entry: ClipboardHistoryEntry) {
        analysisTask?.cancel()
        generation = UUID()
        let expectedGeneration = generation
        snapshot = nil

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let analysis = await self.analyzeText(entry.text)
            guard !Task.isCancelled, self.generation == expectedGeneration else { return }
            self.shadowMetrics?.record(analysis)
            self.snapshot = ClipboardSemanticRankingSnapshot(
                entryID: entry.id,
                analysis: analysis
            )
        }
    }

    public func clear() {
        generation = UUID()
        analysisTask?.cancel()
        analysisTask = nil
        snapshot = nil
    }
}

// MARK: - Email detection

/// Deterministic, high-precision "is this an email?" check used to gate the
/// auto-email-reply behavior. Email is the content type with the strongest
/// structural markers (headers, reply/forward scaffolding, formal closings), so
/// a rule-based detector reaches high precision without an ML model. Tuned to
/// favor precision: it drives an automatic action, so a miss (no auto-reply,
/// the user still sees the chip) is far cheaper than a false positive.
public enum ClipboardEmailDetector {

    /// True when the paste carries recognizable email structure. Conservative:
    /// a single casual "thanks" is not enough; it requires headers, a reply /
    /// forward marker, quoted lines, or an explicit formal closing.
    public static func isEmail(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12 else { return false }

        let headerHits = count("(?m)^\\s*(from|to|subject|cc|bcc|sent|date|reply-to)\\s*:", text)
            + count("(?m)^\\s*(发件人|收件人|主题|抄送|密送|发送时间|日期)\\s*[:：]", text)
        if headerHits >= 2 { return true }

        if matches("(?m)^-{3,}\\s*(original message|原始邮件|forwarded message|转发邮件)", text) { return true }
        if matches("在.{1,40}写道[:：]", text) { return true }
        if matches("(?m)^On .{3,80}wrote:", text) { return true }
        if count("(?m)^\\s*>", text) >= 2 { return true }

        let salutation = matches("(?m)^\\s*(dear |hi |hello |尊敬的|亲爱的|各位好|老师好|您好[，,])", text)
        let formalSignoff = containsAny([
            "best regards", "kind regards", "sincerely", "regards,", "yours truly", "yours sincerely",
            "此致", "敬礼", "顺颂商祺", "顺祝商祺", "顺致敬意", "发自我的iphone", "sent from my iphone"
        ], in: text)
        if headerHits == 1 && (salutation || formalSignoff) { return true }
        if salutation && formalSignoff { return true }
        if formalSignoff { return true }

        return false
    }

    private static func count(_ pattern: String, _ text: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        return re.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        count(pattern, text) > 0
    }

    private static func containsAny(_ needles: [String], in text: String) -> Bool {
        let lower = text.lowercased()
        return needles.contains { lower.contains($0.lowercased()) }
    }
}

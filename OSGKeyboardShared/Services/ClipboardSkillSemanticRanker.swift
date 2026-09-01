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
    private static let listLineLengthThreshold = 48.0
    private static let denseScriptCharacterWeight = 2.25
    /// A bare link or phone paste keeps at most a short label ("详情：",
    /// "Contact:"). Anything longer means the entity is embedded in a real
    /// message, which must keep its own skills.
    private static let entityResidualLengthLimit = 12
    private static let languageConfidenceThreshold = 0.75
    private static let maximumReplyRecommendations = 2
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

    /// Returns semantically relevant skills and always keeps the generic Reply
    /// action available as a safe fallback for accepted clipboard text.
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
        let genericReply = skills.first { $0.id == AIClipboardSkillCatalog.replyID }
        if genericReply != nil {
            scores[AIClipboardSkillCatalog.replyID, default: 0] = max(
                1,
                scores[AIClipboardSkillCatalog.replyID, default: 0]
            )
        }
        let relevant = skills.filter { scores[$0.id, default: 0] > 0 }
        var selected: [AIClipboardSkill] = []
        var specializedReplyCount = 0
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
            if skill.supportsReplyStyle {
                guard specializedReplyCount < maximumReplyRecommendations else { continue }
                specializedReplyCount += 1
            }
            selected.append(skill)
        }
        if let genericReply,
           selected.count < limit,
           !selected.contains(where: { $0.id == genericReply.id }) {
            selected.append(genericReply)
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

        if analysis.invitation.isDetected {
            if analysis.hasDateOrTime {
                boost(AIClipboardSkillCatalog.extractEventsID, 260)
            }
            boost(AIClipboardSkillCatalog.acceptInvitationID, 240)
            boost(AIClipboardSkillCatalog.declineInvitationID, 230)
            boost(AIClipboardSkillCatalog.replyID, 60)
        } else if analysis.hasDateOrTime {
            boost(AIClipboardSkillCatalog.extractEventsID, 110)
        }

        if analysis.task.isDetected {
            boost(AIClipboardSkillCatalog.extractTodosID, 155)
            boost(AIClipboardSkillCatalog.acceptTaskID, 140)
            boost(AIClipboardSkillCatalog.clarifyRequestID, 105)
        }

        if analysis.question.isDetected {
            boost(AIClipboardSkillCatalog.replyID, 145)
            boost(AIClipboardSkillCatalog.clarifyRequestID, 110)
        }

        // A threshold-crossing complaint can still be used as advisory evidence
        // if a future model loses automatic-routing approval. Ranking a chip is
        // reversible and remains user-initiated.
        if isAdvisoryComplaint(analysis.complaint) {
            boost(AIClipboardSkillCatalog.empathyReplyID, 105)
            boost(AIClipboardSkillCatalog.clarifyRequestID, 90)
            boost(AIClipboardSkillCatalog.replyID, 55)
        } else if analysis.sentiment == .negative, analysis.question.isDetected {
            boost(AIClipboardSkillCatalog.empathyReplyID, 85)
            boost(AIClipboardSkillCatalog.clarifyRequestID, 65)
        }

        if analysis.hasOrganizationName,
           analysis.task.isDetected || analysis.question.isDetected || analysis.invitation.isDetected {
            boost(AIClipboardSkillCatalog.businessReplyID, 125)
        } else if analysis.hasOrganizationName {
            boost(AIClipboardSkillCatalog.businessReplyID, 70)
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

        let hasSpecializedReplyIntent = analysis.task.isDetected
            || analysis.question.isDetected
            || analysis.invitation.isDetected
            || isAdvisoryComplaint(analysis.complaint)
        if analysis.replyableMessage.isDetected,
           !hasSpecializedReplyIntent,
           effectiveLength(sourceText) < longTextLengthThreshold,
           !isListLike(sourceText) {
            boost(AIClipboardSkillCatalog.replyID, 160)
            if analysis.sentiment != .negative,
               !isAdvisoryComplaint(analysis.complaint) {
                boost(AIClipboardSkillCatalog.playfulReplyID, 145)
            }
        }
        if analysis.sentiment == .positive {
            boost(AIClipboardSkillCatalog.replyID, 45)
        }
        return scores
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

    private static func isAdvisoryComplaint(_ label: ClipboardIntentLabel) -> Bool {
        label.confidence > 0 && label.confidence >= label.threshold
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

    private let analyzer: ClipboardSemanticAnalyzer
    private var analysisTask: Task<Void, Never>?
    private var generation = UUID()

    public init(analyzer: ClipboardSemanticAnalyzer = ClipboardSemanticAnalyzer()) {
        self.analyzer = analyzer
    }

    public func analyze(_ entry: ClipboardHistoryEntry) {
        analysisTask?.cancel()
        generation = UUID()
        let expectedGeneration = generation
        snapshot = nil

        analysisTask = Task { [weak self] in
            guard let self else { return }
            let analysis = await self.analyzer.analyze(entry.text)
            guard !Task.isCancelled, self.generation == expectedGeneration else { return }
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

// ClipboardSkillSemanticRanker.swift
// OSGKeyboard · Shared
//
// Selects skills from the complete catalog for the newest accepted clipboard
// entry. Analysis is local and ephemeral; installation state, user-managed
// ordering, labels, and recommendations are never persisted.

import Combine
import Foundation

public enum ClipboardSkillSemanticRanker {
    private static let longTextCharacterThreshold = 360
    private static let languageConfidenceThreshold = 0.75
    private static let maximumReplyRecommendations = 2

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

    /// Returns only skills supported by current semantic evidence. No matching
    /// label produces no recommendation instead of a fixed fallback row.
    public static func recommended(
        skills: [AIClipboardSkill],
        sourceText: String,
        analysis: ClipboardSemanticAnalysis,
        uiLanguage _: AppUILanguage,
        limit: Int,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> [AIClipboardSkill] {
        guard limit > 0 else { return [] }
        let scores = relevanceScores(
            sourceText: sourceText,
            analysis: analysis,
            preferredLanguages: preferredLanguages
        )
        let relevant = skills.filter { scores[$0.id, default: 0] > 0 }
        var selected: [AIClipboardSkill] = []
        var replyCount = 0
        for skill in sorted(relevant, scores: scores) {
            guard selected.count < limit else { break }
            if skill.supportsReplyStyle {
                guard replyCount < maximumReplyRecommendations else { continue }
                replyCount += 1
            }
            selected.append(skill)
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

        if let webURL = analysis.singleWebURL {
            boost(AIClipboardSkillCatalog.openLinkID, 320)
            if webURL.scheme?.lowercased() == "https" {
                boost(AIClipboardSkillCatalog.summarizeWebPageID, 310)
            }
            return scores
        }

        if analysis.singlePhoneNumber != nil {
            boost(AIClipboardSkillCatalog.callPhoneID, 320)
            boost(AIClipboardSkillCatalog.createContactID, 310)
            return scores
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

        if sourceText.count >= longTextCharacterThreshold {
            boost(AIClipboardSkillCatalog.summarizeID, 145)
            boost(AIClipboardSkillCatalog.saveToNotesID, 85)
        }

        let hasSpecializedReplyIntent = analysis.task.isDetected
            || analysis.question.isDetected
            || analysis.invitation.isDetected
            || isAdvisoryComplaint(analysis.complaint)
        if analysis.replyableMessage.isDetected,
           !hasSpecializedReplyIntent,
           sourceText.count < longTextCharacterThreshold,
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
        let averageLength = lines.reduce(0) { $0 + $1.count } / lines.count
        return lines.count >= 3 && averageLength <= 48
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

// ClipboardSkillSemanticRanker.swift
// OSGKeyboard · Shared
//
// Keeps the user's saved skill order as the stable fallback, then temporarily
// promotes relevant skills for the newest accepted clipboard entry. Analysis
// is local and ephemeral; neither labels nor reordered IDs are persisted.

import Combine
import Foundation

public enum ClipboardSkillSemanticRanker {
    private static let longTextCharacterThreshold = 360
    private static let languageConfidenceThreshold = 0.75

    public static func ranked(
        skills: [AIClipboardSkill],
        sourceText: String,
        analysis: ClipboardSemanticAnalysis,
        uiLanguage: AppUILanguage
    ) -> [AIClipboardSkill] {
        guard skills.count > 1 else { return skills }

        var scores: [String: Int] = [:]
        func boost(_ id: String, _ value: Int) {
            scores[id, default: 0] += value
        }

        if isLanguageMismatch(analysis.language, uiLanguage: uiLanguage) {
            boost(AIClipboardSkillCatalog.translateID, 230)
            boost(AIClipboardSkillCatalog.replyInSourceLanguageID, 220)
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

        // Complaint remains advisory because its model has not passed the
        // automatic-routing release gate. Ranking a chip is reversible and
        // user-initiated, but it still receives less weight than approved labels.
        if isAdvisoryComplaint(analysis.complaint) {
            boost(AIClipboardSkillCatalog.empathyReplyID, 105)
            boost(AIClipboardSkillCatalog.askForDetailsID, 90)
            boost(AIClipboardSkillCatalog.replyID, 55)
        } else if analysis.sentiment == .negative, analysis.question.isDetected {
            boost(AIClipboardSkillCatalog.empathyReplyID, 85)
            boost(AIClipboardSkillCatalog.askForDetailsID, 65)
        }

        if analysis.hasOrganizationName,
           analysis.task.isDetected || analysis.question.isDetected || analysis.invitation.isDetected {
            boost(AIClipboardSkillCatalog.businessReplyID, 125)
        }

        if isListLike(sourceText) {
            boost(AIClipboardSkillCatalog.organizeListID, 145)
            boost(AIClipboardSkillCatalog.extractTodosID, 105)
            boost(AIClipboardSkillCatalog.summarizeID, 45)
        }

        if sourceText.count >= longTextCharacterThreshold {
            boost(AIClipboardSkillCatalog.summarizeID, 135)
            boost(AIClipboardSkillCatalog.extractConclusionsID, 125)
            boost(AIClipboardSkillCatalog.saveToNotesID, 85)
        }

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
        uiLanguage: AppUILanguage
    ) -> Bool {
        guard let language, language.confidence >= languageConfidenceThreshold else {
            return false
        }
        return languageFamily(language.identifier)
            != languageFamily(uiLanguage.resolvedLanguageCode())
    }

    private static func languageFamily(_ identifier: String) -> String {
        let normalized = identifier.lowercased()
        if normalized.hasPrefix("zh") || normalized.hasPrefix("yue") {
            return "zh"
        }
        return normalized.split(separator: "-").first.map(String.init) ?? normalized
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

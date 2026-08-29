#!/usr/bin/env xcrun swift

import CreateML
import Foundation

private struct CorpusRecord: Codable {
    let id: String
    let text: String
    let language: String
    let split: String
    let family: String
    let knownLabels: Set<String>?
    let sourceDataset: String?
    let sampleWeight: Double?
    let task: Bool
    let question: Bool
    let invitation: Bool
    let complaint: Bool
    let scheduleNegotiation: Bool
    let confirmationDecision: Bool
    let followUpReminder: Bool
    let blessing: Bool
    let sentiment: String
    let replyable: Bool
    let assistantCommand: Bool?
    let informationQuery: Bool?
    let systemNotification: Bool?
    let domain: String?
}

private struct BinaryMetrics: Codable {
    let total: Int
    let truePositive: Int
    let trueNegative: Int
    let falsePositive: Int
    let falseNegative: Int
    let accuracy: Double
    let precision: Double
    let recall: Double
    let f1: Double
}

private struct MulticlassMetrics: Codable {
    let total: Int
    let accuracy: Double
    let macroF1: Double
    let perLabel: [String: BinaryMetrics]
    let confusion: [String: [String: Int]]
}

private struct CandidateReport: Codable {
    let algorithm: String
    let modelBytes: Int
    let runtimeAssetIndependent: Bool
    let balancedTrainingCount: Int
    let balancedValidationCount: Int
    let threshold: Double?
    let confidenceThresholdsByLanguage: [String: Double]?
    let acceptedForAutomaticRouting: Bool
    let validationBinary: BinaryMetrics?
    let testBinary: BinaryMetrics?
    let goldenBinary: BinaryMetrics?
    let testFalsePositiveExamples: [String]?
    let testFalseNegativeExamples: [String]?
    let goldenFalsePositiveExamples: [String]?
    let goldenFalseNegativeExamples: [String]?
    let binaryByLanguage: [String: BinaryMetrics]?
    let goldenBinaryByLanguage: [String: BinaryMetrics]?
    let validationMulticlass: MulticlassMetrics?
    let testMulticlass: MulticlassMetrics?
    let goldenMulticlass: MulticlassMetrics?
    let multiclassByLanguage: [String: MulticlassMetrics]?
}

private struct ClassifierReport: Codable {
    let id: String
    let labels: [String]
    let positiveLabel: String?
    let selectedAlgorithm: String
    let selectedModelFile: String
    let candidates: [CandidateReport]
}

private struct TrainingReport: Codable {
    let generatedAt: String
    let corpusPath: String
    let corpusCount: Int
    let trainingCount: Int
    let validationCount: Int
    let testCount: Int
    let goldenCount: Int
    let selectionPolicy: String
    let classifiers: [ClassifierReport]
}

private struct ManifestClassifier: Codable {
    let id: String
    let modelFile: String
    let algorithm: String
    let labels: [String]
    let positiveLabel: String?
    let confidenceThreshold: Double?
    let confidenceThresholdsByLanguage: [String: Double]?
    let acceptedForAutomaticRouting: Bool
}

private struct ModelManifest: Codable {
    let schemaVersion: Int
    let generatedAt: String
    let corpusRecordCount: Int
    let classifiers: [ManifestClassifier]
}

private enum CandidateAlgorithm: String, CaseIterable {
    case maxEnt
    case bert

    var fileSuffix: String {
        switch self {
        case .maxEnt: "maxent"
        case .bert: "bert"
        }
    }

    var createMLAlgorithm: MLTextClassifier.ModelAlgorithmType {
        switch self {
        case .maxEnt:
            return .maxEnt(revision: 1)
        case .bert:
            return .transferLearning(.bertEmbedding, revision: 1)
        }
    }
}

private let usesBaselineNegativePolicy = CommandLine.arguments.contains(
    "--baseline-negative-policy"
)

private enum ClassifierID: String, CaseIterable {
    case task
    case question
    case invitation
    case complaint
    case scheduleNegotiation
    case confirmationDecision
    case followUpReminder
    case blessing
    case replyableMessage
    case assistantCommand
    case informationQuery
    case systemNotification
    case domain
    case sentiment

    var resourceName: String {
        switch self {
        case .task: "TaskIntentClassifier"
        case .question: "QuestionIntentClassifier"
        case .invitation: "InvitationIntentClassifier"
        case .complaint: "ComplaintIntentClassifier"
        case .scheduleNegotiation: "ScheduleNegotiationIntentClassifier"
        case .confirmationDecision: "ConfirmationDecisionIntentClassifier"
        case .followUpReminder: "FollowUpReminderIntentClassifier"
        case .blessing: "BlessingIntentClassifier"
        case .replyableMessage: "ConversationalReplyIntentClassifier"
        case .assistantCommand: "AssistantCommandIntentClassifier"
        case .informationQuery: "InformationQueryIntentClassifier"
        case .systemNotification: "SystemNotificationIntentClassifier"
        case .domain: "ClipboardDomainClassifier"
        case .sentiment: "SentimentClassifier"
        }
    }

    var labels: [String] {
        switch self {
        case .task: ["notTask", "task"]
        case .question: ["notQuestion", "question"]
        case .invitation: ["notInvitation", "invitation"]
        case .complaint: ["notComplaint", "complaint"]
        case .scheduleNegotiation: ["notScheduleNegotiation", "scheduleNegotiation"]
        case .confirmationDecision: ["notConfirmationDecision", "confirmationDecision"]
        case .followUpReminder: ["notFollowUpReminder", "followUpReminder"]
        case .blessing: ["notBlessing", "blessing"]
        case .replyableMessage: ["notReplyableMessage", "replyableMessage"]
        case .assistantCommand: ["notAssistantCommand", "assistantCommand"]
        case .informationQuery: ["notInformationQuery", "informationQuery"]
        case .systemNotification: ["notSystemNotification", "systemNotification"]
        case .domain:
            [
                "finance", "travel", "calendar", "communication", "media", "smartHome",
                "shopping", "dining", "health", "weather", "accountService", "generalKnowledge"
            ]
        case .sentiment: ["negative", "neutral", "positive"]
        }
    }

    var positiveLabel: String? {
        switch self {
        case .task: "task"
        case .question: "question"
        case .invitation: "invitation"
        case .complaint: "complaint"
        case .scheduleNegotiation: "scheduleNegotiation"
        case .confirmationDecision: "confirmationDecision"
        case .followUpReminder: "followUpReminder"
        case .blessing: "blessing"
        case .replyableMessage: "replyableMessage"
        case .assistantCommand: "assistantCommand"
        case .informationQuery: "informationQuery"
        case .systemNotification: "systemNotification"
        case .domain, .sentiment: nil
        }
    }

    var hardNegativeFamilies: Set<String> {
        switch self {
        case .task:
            return [
                "complaint_implicit_failure",
                "complaint_incident_diverse",
                "complaint_request",
                "complaint_statement",
                "confirmation_decision",
                "confirmation_selection_short",
                "event_statement",
                "follow_up_personal_reminder",
                "neutral_fact",
                "personal_action_item_boundary",
                "resolved_issue_boundary",
                "self_plan"
            ]
        case .invitation:
            return [
                "event_statement",
                "schedule_negotiation",
                "task_question",
                "task_statement"
            ]
        case .complaint:
            return [
                "information_question",
                "negative_news",
                "neutral_fact",
                "personal_action_item_boundary",
                "positive_feedback",
                "quoted_question",
                "resolved_issue_boundary",
                "self_plan",
                "task_assignment_diverse",
                "task_completion_boundary",
                "task_indirect_assignment",
                "task_indirect_question",
                "task_statement"
            ]
        case .scheduleNegotiation:
            if usesBaselineNegativePolicy {
                return [
                    "event_statement",
                    "information_question",
                    "invitation_question",
                    "schedule_fixed_invitation_boundary",
                    "task_question",
                    "task_statement",
                    "vague_future_boundary"
                ]
            }
            return [
                "event_statement",
                "confirmation_decision",
                "confirmation_selection_short",
                "follow_up_action",
                "follow_up_triggered",
                "information_question",
                "invitation_question",
                "schedule_fixed_invitation_boundary",
                "task_question",
                "task_statement",
                "vague_future_boundary"
            ]
        case .confirmationDecision:
            return [
                "acknowledgment_decision_boundary",
                "event_statement",
                "follow_up_action",
                "follow_up_personal_reminder",
                "follow_up_triggered",
                "neutral_fact",
                "negative_news",
                "schedule_negotiation",
                "task_assignment_diverse",
                "task_statement",
                "vague_future_boundary"
            ]
        case .followUpReminder:
            return [
                "acknowledgment",
                "complaint_request",
                "confirmation_decision",
                "confirmation_selection_short",
                "event_statement",
                "invitation_question",
                "neutral_fact",
                "positive_feedback",
                "schedule_negotiation",
                "self_plan",
                "task_assignment_diverse",
                "task_question",
                "task_statement",
                "vague_future_boundary"
            ]
        case .blessing:
            return [
                "acknowledgment",
                "blessing_boundary",
                "conversational_message",
                "event_statement",
                "invitation_question",
                "neutral_fact",
                "positive_feedback",
                "quoted_question",
                "task_question",
                "task_statement"
            ]
        case .question, .replyableMessage, .assistantCommand, .informationQuery,
             .systemNotification, .domain, .sentiment:
            return []
        }
    }

    var hardNegativeFraction: Double {
        switch self {
        case .task:
            0.65
        case .complaint, .blessing:
            0.65
        case .invitation, .followUpReminder:
            0.50
        case .scheduleNegotiation:
            0.75
        case .confirmationDecision:
            0.90
        case .question, .replyableMessage, .assistantCommand, .informationQuery,
             .systemNotification, .domain, .sentiment:
            0
        }
    }

    func label(for record: CorpusRecord) -> String {
        switch self {
        case .task: record.task ? "task" : "notTask"
        case .question: record.question ? "question" : "notQuestion"
        case .invitation: record.invitation ? "invitation" : "notInvitation"
        case .complaint: record.complaint ? "complaint" : "notComplaint"
        case .scheduleNegotiation:
            record.scheduleNegotiation ? "scheduleNegotiation" : "notScheduleNegotiation"
        case .confirmationDecision:
            record.confirmationDecision ? "confirmationDecision" : "notConfirmationDecision"
        case .followUpReminder:
            record.followUpReminder ? "followUpReminder" : "notFollowUpReminder"
        case .blessing:
            record.blessing ? "blessing" : "notBlessing"
        case .replyableMessage: record.replyable ? "replyableMessage" : "notReplyableMessage"
        case .assistantCommand:
            record.assistantCommand == true ? "assistantCommand" : "notAssistantCommand"
        case .informationQuery:
            record.informationQuery == true ? "informationQuery" : "notInformationQuery"
        case .systemNotification:
            record.systemNotification == true ? "systemNotification" : "notSystemNotification"
        case .domain:
            record.domain ?? { preconditionFailure("Known domain record is missing domain") }()
        case .sentiment: record.sentiment
        }
    }

    func hasKnownLabel(in record: CorpusRecord) -> Bool {
        if let knownLabels = record.knownLabels {
            return knownLabels.contains(rawValue)
                || (self == .replyableMessage && knownLabels.contains("replyable"))
        }
        // Legacy product corpora predate knownLabels and only fully annotate
        // the original nine intents plus sentiment. New fields must stay unknown.
        switch self {
        case .assistantCommand, .informationQuery, .systemNotification, .domain:
            return false
        default:
            return true
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private struct TrainedCandidate {
    let algorithm: CandidateAlgorithm
    let modelURL: URL
    let report: CandidateReport
}

private let fileManager = FileManager.default
private let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)

private func commandLineValue(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private func resolvedURL(flag: String, defaultPath: String) -> URL {
    let path = commandLineValue(after: flag) ?? defaultPath
    return URL(fileURLWithPath: path, relativeTo: repositoryRoot).standardizedFileURL
}

private let corpusURL = resolvedURL(
    flag: "--corpus",
    defaultPath: "ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl"
)
private let candidateDirectory = resolvedURL(
    flag: "--candidate-directory",
    defaultPath: "ModelTraining/ClipboardSemantics/Candidates"
)
private let resourceDirectory = resolvedURL(
    flag: "--resource-directory",
    defaultPath: "OSGKeyboardShared/Resources/ClipboardSemantics"
)
private let reportURL = resolvedURL(
    flag: "--report",
    defaultPath: "ModelTraining/ClipboardSemantics/evaluation-report.json"
)
private let requestedLanguage = commandLineValue(after: "--language")

private func loadCorpus() throws -> [CorpusRecord] {
    let content = try String(contentsOf: corpusURL, encoding: .utf8)
    let decoder = JSONDecoder()
    return try content.split(separator: "\n").map { line in
        try decoder.decode(CorpusRecord.self, from: Data(line.utf8))
    }
}

private func stableSeed(for classifier: ClassifierID, split: String) -> UInt64 {
    let material = "\(classifier.rawValue)|\(split)|20260821"
    return material.utf8.reduce(0xcbf2_9ce4_8422_2325) { partial, byte in
        (partial ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
}

private func sourceBalancedPrefix(
    _ records: [CorpusRecord],
    limit: Int,
    classifier: ClassifierID,
    label: String
) -> [CorpusRecord] {
    // MLTextClassifier's dictionary API has no per-example weight parameter.
    // Quantized weight buckets plus deterministic smooth weighted round-robin
    // preserve registry weights without introducing nondeterministic duplication.
    var grouped = Dictionary(grouping: records) {
        let weight = min(max($0.sampleWeight ?? 1.0, 0.01), 1.0)
        let bucket = (weight * 100).rounded() / 100
        return "\($0.sourceDataset ?? "generated")|weight=\(bucket)"
    }
    for source in grouped.keys.sorted() {
        var generator = SeededGenerator(
            seed: stableSeed(
                for: classifier,
                split: "open|\(label)|\(source)"
            )
        )
        grouped[source]?.shuffle(using: &generator)
        if let values = grouped[source], let first = values.first {
            let weight = min(max(first.sampleWeight ?? 1.0, 0.01), 1.0)
            let weightedCount = max(1, Int((Double(values.count) * weight).rounded()))
            grouped[source] = Array(values.prefix(weightedCount))
        }
    }
    let sources = grouped.keys.sorted()
    let weightedTotal = grouped.values.reduce(0) { $0 + $1.count }
    if weightedTotal <= limit {
        return sources.flatMap { grouped[$0] ?? [] }
    }
    var offsets = Dictionary(uniqueKeysWithValues: sources.map { ($0, 0) })
    let sourceWeights = Dictionary(uniqueKeysWithValues: sources.map { source in
        (source, grouped[source]?.first?.sampleWeight ?? 1.0)
    })
    var schedulingScores = Dictionary(uniqueKeysWithValues: sources.map { ($0, 0.0) })
    var selected: [CorpusRecord] = []
    while selected.count < limit {
        let available = sources.filter {
            let offset = offsets[$0] ?? 0
            return grouped[$0]?.indices.contains(offset) == true
        }
        if available.isEmpty {
            break
        }
        let totalWeight = available.reduce(0.0) {
            $0 + max(sourceWeights[$1] ?? 1.0, 0.01)
        }
        for source in available {
            schedulingScores[source, default: 0] += max(
                sourceWeights[source] ?? 1.0,
                0.01
            )
        }
        let source = available.max {
            let left = schedulingScores[$0, default: 0]
            let right = schedulingScores[$1, default: 0]
            return left == right ? $0 > $1 : left < right
        }!
        let offset = offsets[source] ?? 0
        selected.append(grouped[source]![offset])
        offsets[source] = offset + 1
        schedulingScores[source, default: 0] -= totalWeight
    }
    return selected
}

private func curatedTrainingRecords(
    _ records: [CorpusRecord],
    classifier: ClassifierID
) -> [CorpusRecord] {
    let knownRecords = records.filter {
        classifier.hasKnownLabel(in: $0)
    }
    let generatedRecords = knownRecords.filter { $0.sourceDataset == nil }
    let openRecords = knownRecords.filter { $0.sourceDataset != nil }
    let weightedGeneratedRecords = sourceBalancedPrefix(
        generatedRecords,
        limit: generatedRecords.count,
        classifier: classifier,
        label: "generated"
    )
    guard !openRecords.isEmpty else { return weightedGeneratedRecords }

    let generatedByLabel = Dictionary(grouping: weightedGeneratedRecords) {
        classifier.label(for: $0)
    }
    let openByLabel = Dictionary(grouping: openRecords) {
        classifier.label(for: $0)
    }
    let openOnlyBalancedCount = classifier.labels
        .compactMap { openByLabel[$0]?.count }
        .min() ?? 0
    let multiplier = switch classifier {
    case .blessing:
        2.0
    case .task, .question, .complaint, .confirmationDecision, .assistantCommand,
         .informationQuery, .systemNotification, .domain, .sentiment:
        1.0
    case .invitation, .scheduleNegotiation, .followUpReminder, .replyableMessage:
        0.5
    }

    let selectedOpenRecords = classifier.labels.flatMap { label in
        let generatedCount = generatedByLabel[label]?.count ?? 0
        let anchorCount = generatedCount > 0 ? generatedCount : openOnlyBalancedCount
        let limit = max(1, Int((Double(anchorCount) * multiplier).rounded()))
        return sourceBalancedPrefix(
            openByLabel[label] ?? [],
            limit: limit,
            classifier: classifier,
            label: label
        )
    }
    return weightedGeneratedRecords + selectedOpenRecords
}

private func balancedTexts(
    records: [CorpusRecord],
    classifier: ClassifierID,
    split: String
) -> [String: [String]] {
    let grouped = Dictionary(grouping: records) { classifier.label(for: $0) }
    let requiredLabels = classifier.labels
    let minimumCount = requiredLabels
        .compactMap { grouped[$0]?.count }
        .min() ?? 0
    precondition(minimumCount > 0, "Missing labels for \(classifier.rawValue) \(split)")

    var result: [String: [String]] = [:]
    for (offset, label) in requiredLabels.enumerated() {
        var generator = SeededGenerator(
            seed: stableSeed(for: classifier, split: split) &+ UInt64(offset)
        )
        let candidates = grouped[label] ?? []
        if label != classifier.positiveLabel,
           !classifier.hardNegativeFamilies.isEmpty,
           classifier.hardNegativeFraction > 0 {
            var hardNegatives = candidates
                .filter { classifier.hardNegativeFamilies.contains($0.family) }
                .map(\.text)
                .shuffled(using: &generator)
            var remaining = candidates
                .filter { !classifier.hardNegativeFamilies.contains($0.family) }
                .map(\.text)
                .shuffled(using: &generator)
            let requestedHardNegatives = Int(
                (Double(minimumCount) * classifier.hardNegativeFraction).rounded(.down)
            )
            let hardNegativeCount = min(hardNegatives.count, requestedHardNegatives)
            hardNegatives = Array(hardNegatives.prefix(hardNegativeCount))
            remaining = Array(remaining.prefix(minimumCount - hardNegativeCount))
            result[label] = hardNegatives + remaining
        } else {
            let texts = candidates
                .map(\.text)
                .shuffled(using: &generator)
            result[label] = Array(texts.prefix(minimumCount))
        }
    }
    return result
}

private func totalCount(_ dictionary: [String: [String]]) -> Int {
    dictionary.values.reduce(0) { $0 + $1.count }
}

private func rounded(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return (value * 10_000).rounded() / 10_000
}

private func binaryMetrics(
    records: [CorpusRecord],
    classifier: ClassifierID,
    positiveLabel: String,
    threshold: Double,
    scores: [Double]
) -> BinaryMetrics {
    precondition(records.count == scores.count)
    var truePositive = 0
    var trueNegative = 0
    var falsePositive = 0
    var falseNegative = 0

    for (record, score) in zip(records, scores) {
        let expectedPositive = classifier.label(for: record) == positiveLabel
        let predictedPositive = score >= threshold
        switch (expectedPositive, predictedPositive) {
        case (true, true): truePositive += 1
        case (false, false): trueNegative += 1
        case (false, true): falsePositive += 1
        case (true, false): falseNegative += 1
        }
    }

    let total = records.count
    let precisionDenominator = truePositive + falsePositive
    let recallDenominator = truePositive + falseNegative
    let precision = precisionDenominator > 0
        ? Double(truePositive) / Double(precisionDenominator)
        : 0
    let recall = recallDenominator > 0
        ? Double(truePositive) / Double(recallDenominator)
        : 0
    let f1 = precision + recall > 0
        ? 2 * precision * recall / (precision + recall)
        : 0

    return BinaryMetrics(
        total: total,
        truePositive: truePositive,
        trueNegative: trueNegative,
        falsePositive: falsePositive,
        falseNegative: falseNegative,
        accuracy: rounded(
            total > 0 ? Double(truePositive + trueNegative) / Double(total) : 0
        ),
        precision: rounded(precision),
        recall: rounded(recall),
        f1: rounded(f1)
    )
}

private func binaryMetrics(
    records: [CorpusRecord],
    classifier: ClassifierID,
    positiveLabel: String,
    globalThreshold: Double,
    thresholdsByLanguage: [String: Double],
    scores: [Double]
) -> BinaryMetrics {
    precondition(records.count == scores.count)
    let predictions = zip(records, scores).map { record, score in
        score >= (thresholdsByLanguage[record.language] ?? globalThreshold)
    }
    var truePositive = 0
    var trueNegative = 0
    var falsePositive = 0
    var falseNegative = 0
    for (record, predictedPositive) in zip(records, predictions) {
        let expectedPositive = classifier.label(for: record) == positiveLabel
        switch (expectedPositive, predictedPositive) {
        case (true, true): truePositive += 1
        case (false, false): trueNegative += 1
        case (false, true): falsePositive += 1
        case (true, false): falseNegative += 1
        }
    }
    let total = records.count
    let precision = truePositive + falsePositive > 0
        ? Double(truePositive) / Double(truePositive + falsePositive)
        : 0
    let recall = truePositive + falseNegative > 0
        ? Double(truePositive) / Double(truePositive + falseNegative)
        : 0
    return BinaryMetrics(
        total: total,
        truePositive: truePositive,
        trueNegative: trueNegative,
        falsePositive: falsePositive,
        falseNegative: falseNegative,
        accuracy: rounded(
            total > 0 ? Double(truePositive + trueNegative) / Double(total) : 0
        ),
        precision: rounded(precision),
        recall: rounded(recall),
        f1: rounded(
            precision + recall > 0
                ? 2 * precision * recall / (precision + recall)
                : 0
        )
    )
}

private func scores(
    classifier: MLTextClassifier,
    records: [CorpusRecord],
    positiveLabel: String
) throws -> [Double] {
    try records.map { record in
        try classifier.predictionWithConfidence(from: record.text)[positiveLabel] ?? 0
    }
}

private func binaryErrorExamples(
    records: [CorpusRecord],
    classifier: ClassifierID,
    positiveLabel: String,
    threshold: Double,
    thresholdsByLanguage: [String: Double] = [:],
    scores: [Double],
    expectedPositive: Bool,
    predictedPositive: Bool,
    limit: Int = 12
) -> [String] {
    zip(records, scores).compactMap { record, score -> String? in
        let isExpectedPositive = classifier.label(for: record) == positiveLabel
        let effectiveThreshold = thresholdsByLanguage[record.language] ?? threshold
        let isPredictedPositive = score >= effectiveThreshold
        guard isExpectedPositive == expectedPositive,
              isPredictedPositive == predictedPositive else {
            return nil
        }
        return "[\(record.language)] \(record.text) (score=\(rounded(score)))"
    }
    .prefix(limit)
    .map { $0 }
}

private func calibratedThreshold(
    records: [CorpusRecord],
    classifierID: ClassifierID,
    positiveLabel: String,
    scores: [Double]
) -> (threshold: Double, metrics: BinaryMetrics) {
    var candidates: [(Double, BinaryMetrics)] = []
    // Low-confidence positives are too unstable for automatic keyboard
    // routing even when a synthetic validation split happens to accept them.
    let minimumThreshold = switch classifierID {
    case .scheduleNegotiation, .confirmationDecision:
        30
    case .followUpReminder:
        58
    default:
        60
    }
    for integer in minimumThreshold...99 {
        let threshold = Double(integer) / 100
        candidates.append(
            (
                threshold,
                binaryMetrics(
                    records: records,
                    classifier: classifierID,
                    positiveLabel: positiveLabel,
                    threshold: threshold,
                    scores: scores
                )
            )
        )
    }

    let highPrecision = candidates.filter { $0.1.precision >= 0.97 }
    if let best = highPrecision.max(by: {
        if $0.1.recall == $1.1.recall {
            if $0.1.precision == $1.1.precision {
                // Prefer the lowest threshold on an identical validation
                // plateau so held-out paraphrases are not needlessly lost.
                return $0.0 > $1.0
            }
            return $0.1.precision < $1.1.precision
        }
        return $0.1.recall < $1.1.recall
    }) {
        return best
    }
    return candidates.max(by: { $0.1.f1 < $1.1.f1 })
        ?? (0.50, binaryMetrics(
            records: records,
            classifier: classifierID,
            positiveLabel: positiveLabel,
            threshold: 0.50,
            scores: scores
        ))
}

private func calibratedThresholdsByLanguage(
    records: [CorpusRecord],
    classifierID: ClassifierID,
    positiveLabel: String,
    scores: [Double],
    minimumPerClass: Int = 20
) -> [String: Double] {
    var result: [String: Double] = [:]
    for language in Set(records.map(\.language)).sorted() {
        let indexed = records.enumerated().filter { $0.element.language == language }
        let languageRecords = indexed.map(\.element)
        let positiveCount = languageRecords.filter {
            classifierID.label(for: $0) == positiveLabel
        }.count
        let negativeCount = languageRecords.count - positiveCount
        guard positiveCount >= minimumPerClass, negativeCount >= minimumPerClass else {
            print(
                "CALIBRATION_SKIPPED classifier=\(classifierID.rawValue) "
                    + "language=\(language) positives=\(positiveCount) negatives=\(negativeCount)"
            )
            continue
        }
        let languageScores = indexed.map { scores[$0.offset] }
        let calibration = calibratedThreshold(
            records: languageRecords,
            classifierID: classifierID,
            positiveLabel: positiveLabel,
            scores: languageScores
        )
        result[language] = rounded(calibration.threshold)
    }
    return result
}

private func multiclassMetrics(
    records: [CorpusRecord],
    classifierID: ClassifierID,
    predictions: [String]
) -> MulticlassMetrics {
    precondition(records.count == predictions.count)
    let labels = classifierID.labels
    var confusion = Dictionary(
        uniqueKeysWithValues: labels.map { expected in
            (expected, Dictionary(uniqueKeysWithValues: labels.map { ($0, 0) }))
        }
    )

    for (record, predicted) in zip(records, predictions) {
        let expected = classifierID.label(for: record)
        confusion[expected, default: [:]][predicted, default: 0] += 1
    }

    var perLabel: [String: BinaryMetrics] = [:]
    for label in labels {
        let binaryRecords = records.enumerated().map { index, record in
            (expected: classifierID.label(for: record) == label, predicted: predictions[index] == label)
        }
        let truePositive = binaryRecords.filter { $0.expected && $0.predicted }.count
        let trueNegative = binaryRecords.filter { !$0.expected && !$0.predicted }.count
        let falsePositive = binaryRecords.filter { !$0.expected && $0.predicted }.count
        let falseNegative = binaryRecords.filter { $0.expected && !$0.predicted }.count
        let precision = truePositive + falsePositive > 0
            ? Double(truePositive) / Double(truePositive + falsePositive)
            : 0
        let recall = truePositive + falseNegative > 0
            ? Double(truePositive) / Double(truePositive + falseNegative)
            : 0
        let f1 = precision + recall > 0
            ? 2 * precision * recall / (precision + recall)
            : 0
        perLabel[label] = BinaryMetrics(
            total: records.count,
            truePositive: truePositive,
            trueNegative: trueNegative,
            falsePositive: falsePositive,
            falseNegative: falseNegative,
            accuracy: rounded(
                records.isEmpty
                    ? 0
                    : Double(truePositive + trueNegative) / Double(records.count)
            ),
            precision: rounded(precision),
            recall: rounded(recall),
            f1: rounded(f1)
        )
    }

    let correct = zip(records, predictions).filter {
        classifierID.label(for: $0.0) == $0.1
    }.count
    let macroF1 = labels.compactMap { perLabel[$0]?.f1 }.reduce(0, +)
        / Double(labels.count)
    return MulticlassMetrics(
        total: records.count,
        accuracy: rounded(records.isEmpty ? 0 : Double(correct) / Double(records.count)),
        macroF1: rounded(macroF1),
        perLabel: perLabel,
        confusion: confusion
    )
}

private func modelFileSize(at url: URL) -> Int {
    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
    return attributes?[.size] as? Int ?? 0
}

private func train(
    classifierID: ClassifierID,
    algorithm: CandidateAlgorithm,
    trainingRecords: [CorpusRecord],
    validationRecords: [CorpusRecord],
    testRecords: [CorpusRecord],
    goldenRecords: [CorpusRecord]
) throws -> TrainedCandidate {
    // Open datasets often annotate only a subset of product intents. Excluding
    // unknown labels prevents an unannotated intent from becoming a false negative.
    // Source-balanced caps then preserve the reviewed base corpus as the boundary
    // anchor instead of allowing one large dataset to dominate model weights.
    let knownTrainingRecords = curatedTrainingRecords(
        trainingRecords,
        classifier: classifierID
    )
    let trainingTexts = balancedTexts(
        records: knownTrainingRecords,
        classifier: classifierID,
        split: "train"
    )
    let validationTexts = balancedTexts(
        records: validationRecords,
        classifier: classifierID,
        split: "validation"
    )
    var parameters = MLTextClassifier.ModelParameters(
        validation: .dictionary(validationTexts),
        algorithm: algorithm.createMLAlgorithm,
        language: nil
    )
    parameters.maxIterations = algorithm == .bert ? 20 : 50

    print(
        "TRAIN_BEGIN classifier=\(classifierID.rawValue) "
            + "algorithm=\(algorithm.rawValue) samples=\(totalCount(trainingTexts))"
    )
    let classifier = try MLTextClassifier(
        trainingData: trainingTexts,
        parameters: parameters
    )

    try fileManager.createDirectory(
        at: candidateDirectory,
        withIntermediateDirectories: true
    )
    let modelURL = candidateDirectory.appendingPathComponent(
        "\(classifierID.resourceName)-\(algorithm.fileSuffix).mlmodel"
    )
    if fileManager.fileExists(atPath: modelURL.path) {
        try fileManager.removeItem(at: modelURL)
    }
    let metadata = MLModelMetadata(
        author: "OSGKeyboard",
        shortDescription: "Local clipboard \(classifierID.rawValue) classifier",
        license: nil,
        version: "1.0.0",
        additional: [
            "Corpus": "Synthetic bilingual clipboard semantics corpus",
            "ContainsUserClipboardData": "false",
            "Algorithm": algorithm.rawValue
        ]
    )
    try classifier.write(to: modelURL, metadata: metadata)

    let report: CandidateReport
    if let positiveLabel = classifierID.positiveLabel {
        let validationScores = try scores(
            classifier: classifier,
            records: validationRecords,
            positiveLabel: positiveLabel
        )
        let calibration = calibratedThreshold(
            records: validationRecords,
            classifierID: classifierID,
            positiveLabel: positiveLabel,
            scores: validationScores
        )
        let calibratedLanguageThresholds = calibratedThresholdsByLanguage(
            records: validationRecords,
            classifierID: classifierID,
            positiveLabel: positiveLabel,
            scores: validationScores
        )
        let thresholdsByLanguage = calibratedLanguageThresholds.mapValues {
            max($0, rounded(calibration.threshold))
        }
        let testScores = try scores(
            classifier: classifier,
            records: testRecords,
            positiveLabel: positiveLabel
        )
        let testMetrics = binaryMetrics(
            records: testRecords,
            classifier: classifierID,
            positiveLabel: positiveLabel,
            globalThreshold: calibration.threshold,
            thresholdsByLanguage: thresholdsByLanguage,
            scores: testScores
        )
        let goldenScores = try scores(
            classifier: classifier,
            records: goldenRecords,
            positiveLabel: positiveLabel
        )
        let goldenMetrics = binaryMetrics(
            records: goldenRecords,
            classifier: classifierID,
            positiveLabel: positiveLabel,
            globalThreshold: calibration.threshold,
            thresholdsByLanguage: thresholdsByLanguage,
            scores: goldenScores
        )
        var byLanguage: [String: BinaryMetrics] = [:]
        for language in Set(testRecords.map(\.language)).sorted() {
            let indexed = testRecords.enumerated().filter { $0.element.language == language }
            let records = indexed.map(\.element)
            let languageScores = indexed.map { testScores[$0.offset] }
            byLanguage[language] = binaryMetrics(
                records: records,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: thresholdsByLanguage[language] ?? calibration.threshold,
                scores: languageScores
            )
        }
        var goldenByLanguage: [String: BinaryMetrics] = [:]
        for language in Set(goldenRecords.map(\.language)).sorted() {
            let indexed = goldenRecords.enumerated().filter { $0.element.language == language }
            goldenByLanguage[language] = binaryMetrics(
                records: indexed.map(\.element),
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: thresholdsByLanguage[language] ?? calibration.threshold,
                scores: indexed.map { goldenScores[$0.offset] }
            )
        }
        report = CandidateReport(
            algorithm: algorithm.rawValue,
            modelBytes: modelFileSize(at: modelURL),
            runtimeAssetIndependent: algorithm == .maxEnt,
            balancedTrainingCount: totalCount(trainingTexts),
            balancedValidationCount: totalCount(validationTexts),
            threshold: rounded(calibration.threshold),
            confidenceThresholdsByLanguage:
                thresholdsByLanguage.isEmpty ? nil : thresholdsByLanguage,
            acceptedForAutomaticRouting: algorithm == .maxEnt
                && calibration.metrics.precision >= 0.97
                && testMetrics.precision >= 0.90
                && goldenMetrics.precision >= 0.90,
            validationBinary: calibration.metrics,
            testBinary: testMetrics,
            goldenBinary: goldenMetrics,
            testFalsePositiveExamples: binaryErrorExamples(
                records: testRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                thresholdsByLanguage: thresholdsByLanguage,
                scores: testScores,
                expectedPositive: false,
                predictedPositive: true
            ),
            testFalseNegativeExamples: binaryErrorExamples(
                records: testRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                thresholdsByLanguage: thresholdsByLanguage,
                scores: testScores,
                expectedPositive: true,
                predictedPositive: false
            ),
            goldenFalsePositiveExamples: binaryErrorExamples(
                records: goldenRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                thresholdsByLanguage: thresholdsByLanguage,
                scores: goldenScores,
                expectedPositive: false,
                predictedPositive: true
            ),
            goldenFalseNegativeExamples: binaryErrorExamples(
                records: goldenRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                thresholdsByLanguage: thresholdsByLanguage,
                scores: goldenScores,
                expectedPositive: true,
                predictedPositive: false
            ),
            binaryByLanguage: byLanguage,
            goldenBinaryByLanguage: goldenByLanguage,
            validationMulticlass: nil,
            testMulticlass: nil,
            goldenMulticlass: nil,
            multiclassByLanguage: nil
        )
    } else {
        let validationPredictions = try classifier.predictions(
            from: validationRecords.map(\.text)
        )
        let testPredictions = try classifier.predictions(
            from: testRecords.map(\.text)
        )
        let validationMetrics = multiclassMetrics(
            records: validationRecords,
            classifierID: classifierID,
            predictions: validationPredictions
        )
        let testMetrics = multiclassMetrics(
            records: testRecords,
            classifierID: classifierID,
            predictions: testPredictions
        )
        let goldenPredictions = try classifier.predictions(
            from: goldenRecords.map(\.text)
        )
        let goldenMetrics = multiclassMetrics(
            records: goldenRecords,
            classifierID: classifierID,
            predictions: goldenPredictions
        )
        var byLanguage: [String: MulticlassMetrics] = [:]
        for language in Set(testRecords.map(\.language)).sorted() {
            let indexed = testRecords.enumerated().filter { $0.element.language == language }
            byLanguage[language] = multiclassMetrics(
                records: indexed.map(\.element),
                classifierID: classifierID,
                predictions: indexed.map { testPredictions[$0.offset] }
            )
        }
        report = CandidateReport(
            algorithm: algorithm.rawValue,
            modelBytes: modelFileSize(at: modelURL),
            runtimeAssetIndependent: algorithm == .maxEnt,
            balancedTrainingCount: totalCount(trainingTexts),
            balancedValidationCount: totalCount(validationTexts),
            threshold: nil,
            confidenceThresholdsByLanguage: nil,
            acceptedForAutomaticRouting: algorithm == .maxEnt
                && validationMetrics.macroF1 >= 0.85
                && testMetrics.macroF1 >= 0.85
                && goldenMetrics.macroF1 >= 0.75,
            validationBinary: nil,
            testBinary: nil,
            goldenBinary: nil,
            testFalsePositiveExamples: nil,
            testFalseNegativeExamples: nil,
            goldenFalsePositiveExamples: nil,
            goldenFalseNegativeExamples: nil,
            binaryByLanguage: nil,
            goldenBinaryByLanguage: nil,
            validationMulticlass: validationMetrics,
            testMulticlass: testMetrics,
            goldenMulticlass: goldenMetrics,
            multiclassByLanguage: byLanguage
        )
    }

    print(
        "TRAIN_DONE classifier=\(classifierID.rawValue) "
            + "algorithm=\(algorithm.rawValue) bytes=\(report.modelBytes)"
    )
    return TrainedCandidate(
        algorithm: algorithm,
        modelURL: modelURL,
        report: report
    )
}

private func selectionScore(_ candidate: TrainedCandidate) -> (Int, Double, Double) {
    if let binary = candidate.report.validationBinary {
        return (
            candidate.report.acceptedForAutomaticRouting
                ? 2
                : (candidate.report.runtimeAssetIndependent ? 1 : 0),
            binary.recall,
            binary.precision
        )
    }
    if let multiclass = candidate.report.validationMulticlass {
        return (
            candidate.report.acceptedForAutomaticRouting
                ? 2
                : (candidate.report.runtimeAssetIndependent ? 1 : 0),
            multiclass.macroF1,
            multiclass.accuracy
        )
    }
    return (0, 0, 0)
}

private func isBetter(_ lhs: TrainedCandidate, than rhs: TrainedCandidate) -> Bool {
    let left = selectionScore(lhs)
    let right = selectionScore(rhs)
    if left.0 != right.0 { return left.0 > right.0 }
    if left.1 != right.1 { return left.1 > right.1 }
    if left.2 != right.2 { return left.2 > right.2 }
    return lhs.report.modelBytes < rhs.report.modelBytes
}

private func selectedAlgorithms() -> [CandidateAlgorithm] {
    guard let index = CommandLine.arguments.firstIndex(of: "--algorithms"),
          CommandLine.arguments.indices.contains(index + 1)
    else {
        return [.maxEnt]
    }
    let requested = Set(
        CommandLine.arguments[index + 1]
            .split(separator: ",")
            .map(String.init)
    )
    return CandidateAlgorithm.allCases.filter { requested.contains($0.rawValue) }
}

private func selectedClassifiers() -> [ClassifierID] {
    guard let index = CommandLine.arguments.firstIndex(of: "--classifiers"),
          CommandLine.arguments.indices.contains(index + 1)
    else {
        return ClassifierID.allCases
    }
    let requested = Set(
        CommandLine.arguments[index + 1]
            .split(separator: ",")
            .map(String.init)
    )
    return ClassifierID.allCases.filter { requested.contains($0.rawValue) }
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
}

private func main() throws {
    let loadedRecords = try loadCorpus()
    let records = requestedLanguage.map { language in
        loadedRecords.filter { $0.language == language }
    } ?? loadedRecords
    precondition(!records.isEmpty, "No corpus records match the requested language")
    let trainingRecords = records.filter { $0.split == "train" }
    let validationRecords = records.filter { $0.split == "validation" }
    let testRecords = records.filter { $0.split == "test" }
    let goldenRecords = records.filter { $0.split == "golden" }
    let algorithms = selectedAlgorithms()
    let requestedClassifiers = selectedClassifiers()
    let classifiers = requestedClassifiers.filter { classifier in
        let trainingLabels = Set(
            trainingRecords
                .filter { classifier.hasKnownLabel(in: $0) }
                .map { classifier.label(for: $0) }
        )
        return Set(classifier.labels).isSubset(of: trainingLabels)
            && [validationRecords, testRecords, goldenRecords].allSatisfy {
                !$0.filter { classifier.hasKnownLabel(in: $0) }.isEmpty
            }
    }
    for classifier in requestedClassifiers where !classifiers.contains(classifier) {
        print(
            "TRAIN_SKIPPED classifier=\(classifier.rawValue) "
                + "reason=insufficient-known-label-coverage"
        )
    }
    precondition(!algorithms.isEmpty, "No supported algorithms requested")
    precondition(!classifiers.isEmpty, "No classifiers have sufficient known-label coverage")

    try fileManager.createDirectory(
        at: resourceDirectory,
        withIntermediateDirectories: true
    )
    let generatedAt = ISO8601DateFormatter().string(from: Date())
    var classifierReports: [ClassifierReport] = []
    var manifestClassifiers: [ManifestClassifier] = []

    for classifierID in classifiers {
        var candidates: [TrainedCandidate] = []
        let knownValidationRecords = validationRecords.filter {
            classifierID.hasKnownLabel(in: $0)
        }
        let knownTestRecords = testRecords.filter {
            classifierID.hasKnownLabel(in: $0)
        }
        let knownGoldenRecords = goldenRecords.filter {
            classifierID.hasKnownLabel(in: $0)
        }
        for algorithm in algorithms {
            do {
                candidates.append(
                    try train(
                        classifierID: classifierID,
                        algorithm: algorithm,
                        trainingRecords: trainingRecords,
                        validationRecords: knownValidationRecords,
                        testRecords: knownTestRecords,
                        goldenRecords: knownGoldenRecords
                    )
                )
            } catch {
                print(
                    "TRAIN_FAILED classifier=\(classifierID.rawValue) "
                        + "algorithm=\(algorithm.rawValue) error=\(error)"
                )
            }
        }
        guard let selected = candidates.max(by: { isBetter($1, than: $0) }) else {
            throw NSError(
                domain: "ClipboardSemanticTraining",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "All training candidates failed for \(classifierID.rawValue)"
                ]
            )
        }
        let selectedURL = resourceDirectory.appendingPathComponent(
            "\(classifierID.resourceName).mlmodel"
        )
        if fileManager.fileExists(atPath: selectedURL.path) {
            try fileManager.removeItem(at: selectedURL)
        }
        try fileManager.copyItem(at: selected.modelURL, to: selectedURL)

        classifierReports.append(
            ClassifierReport(
                id: classifierID.rawValue,
                labels: classifierID.labels,
                positiveLabel: classifierID.positiveLabel,
                selectedAlgorithm: selected.algorithm.rawValue,
                selectedModelFile: selectedURL.lastPathComponent,
                candidates: candidates.map(\.report)
            )
        )
        manifestClassifiers.append(
            ManifestClassifier(
                id: classifierID.rawValue,
                modelFile: selectedURL.lastPathComponent,
                algorithm: selected.algorithm.rawValue,
                labels: classifierID.labels,
                positiveLabel: classifierID.positiveLabel,
                confidenceThreshold: selected.report.threshold,
                confidenceThresholdsByLanguage:
                    selected.report.confidenceThresholdsByLanguage,
                acceptedForAutomaticRouting: selected.report.acceptedForAutomaticRouting
            )
        )
        print(
            "SELECTED classifier=\(classifierID.rawValue) "
                + "algorithm=\(selected.algorithm.rawValue)"
        )
    }

    let report = TrainingReport(
        generatedAt: generatedAt,
        corpusPath: corpusURL.path,
        corpusCount: records.count,
        trainingCount: trainingRecords.count,
        validationCount: validationRecords.count,
        testCount: testRecords.count,
        goldenCount: goldenRecords.count,
        selectionPolicy:
            "Open records with unknown labels are excluded per classifier, and source-balanced "
            + "caps anchor each label to the reviewed generated corpus size. Because Create ML "
            + "does not expose per-example weights, registry sampleWeight values are applied as "
            + "deterministic quantized quotas with smooth weighted source scheduling. "
            + "Validation only: global and per-language binary thresholds require precision "
            + ">= 0.97, then maximize recall; languages with fewer than 20 examples per class "
            + "fall back to the global threshold. "
            + "sentiment prioritizes macro-F1. Automatic routing also requires a self-contained "
            + "maxEnt model because BERT embedding assets are not guaranteed in extensions. "
            + "Test and golden data gate deployment but never tune model weights.",
        classifiers: classifierReports
    )
    try writeJSON(report, to: reportURL)
    try writeJSON(
        ModelManifest(
            schemaVersion: 4,
            generatedAt: generatedAt,
            corpusRecordCount: records.count,
            classifiers: manifestClassifiers
        ),
        to: resourceDirectory.appendingPathComponent(
            "clipboard-semantic-models.json"
        )
    )
    print("TRAINING_REPORT \(reportURL.path)")
}

do {
    try main()
} catch {
    fputs("Training failed: \(error)\n", stderr)
    exit(1)
}

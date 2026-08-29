#!/usr/bin/env swift

import Foundation
import NaturalLanguage

private struct HoldoutRecord: Decodable {
    let id: String
    let text: String
    let language: String
    let split: String?
    let family: String
    let task: Bool
    let question: Bool
    let invitation: Bool
    let complaint: Bool
    let scheduleNegotiation: Bool
    let confirmationDecision: Bool
    let followUpReminder: Bool
    let blessing: Bool?
    let sentiment: String
    let replyable: Bool
    let assistantCommand: Bool?
    let informationQuery: Bool?
    let systemNotification: Bool?
    let sourceDataset: String?
    let knownLabels: Set<String>?

    func hasKnownLabel(_ label: String) -> Bool {
        guard let knownLabels else {
            return true
        }
        return knownLabels.contains(label)
            || (label == "replyableMessage" && knownLabels.contains("replyable"))
    }

    func isPositive(for classifierID: String) -> Bool {
        switch classifierID {
        case "task": task
        case "question": question
        case "invitation": invitation
        case "complaint": complaint
        case "scheduleNegotiation": scheduleNegotiation
        case "confirmationDecision": confirmationDecision
        case "followUpReminder": followUpReminder
        case "blessing": blessing ?? false
        case "replyableMessage": replyable
        case "assistantCommand": assistantCommand ?? false
        case "informationQuery": informationQuery ?? false
        case "systemNotification": systemNotification ?? false
        default: false
        }
    }

    func expectedVerifierLabel(for verifierID: String) -> String {
        if verifierID == "action" {
            if task && complaint {
                return "both"
            }
            if task {
                return "taskOnly"
            }
            if complaint {
                return "complaintOnly"
            }
            if question {
                return "questionRequest"
            }
            return "neither"
        }
        let coordinationLabels = [
            invitation ? "invitation" : nil,
            scheduleNegotiation ? "scheduleNegotiation" : nil,
            confirmationDecision ? "confirmationDecision" : nil,
            followUpReminder ? "followUpReminder" : nil
        ].compactMap { $0 }
        return coordinationLabels.count == 1 ? coordinationLabels[0] : "neither"
    }
}

private struct TrainingRecord: Decodable {
    let text: String
    let split: String?
}

private struct Manifest: Decodable {
    let schemaVersion: Int
    let classifiers: [ManifestClassifier]
    let verifiers: [ManifestVerifier]?
}

private struct ManifestClassifier: Decodable {
    let id: String
    let modelFile: String
    let positiveLabel: String?
    let confidenceThreshold: Double?
    let confidenceThresholdsByLanguage: [String: Double]?
    let acceptedForAutomaticRouting: Bool
}

private struct ManifestVerifier: Decodable {
    let id: String
    let modelFile: String
    let confidenceThreshold: Double
    let confidenceThresholdsByLanguage: [String: Double]?
    let minimumMargin: Double
    let minimumMarginsByLanguage: [String: Double]?
    let acceptedForAutomaticRouting: Bool
    let deploymentMode: String
}

private struct BinaryMetrics: Encodable {
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

private struct ErrorExample: Encodable {
    let id: String
    let language: String
    let family: String
    let sourceDataset: String?
    let text: String
    let confidence: Double
}

private struct BinaryEvaluation: Encodable {
    let id: String
    let metrics: BinaryMetrics
    let metricsByLanguage: [String: BinaryMetrics]
    let metricsBySource: [String: BinaryMetrics]
    let thresholdAt90Precision: ThresholdRecommendation?
    let thresholdAt95Precision: ThresholdRecommendation?
    let thresholdsAt90PrecisionByLanguage: [String: ThresholdRecommendation]
    let thresholdsAt95PrecisionByLanguage: [String: ThresholdRecommendation]
    let falsePositiveExamples: [ErrorExample]
    let falseNegativeExamples: [ErrorExample]
}

private struct ThresholdRecommendation: Encodable {
    let threshold: Double
    let metrics: BinaryMetrics
}

private struct SentimentMetrics: Encodable {
    let total: Int
    let correct: Int
    let unknown: Int
    let accuracy: Double
    let unknownRate: Double
    let macroF1: Double
    let perLabelF1: [String: Double]
}

private struct AggregateMetrics: Encodable {
    let accuracy: Double
    let precision: Double
    let recall: Double
    let f1: Double
}

private struct VerifierRoutingMetrics: Encodable {
    let total: Int
    let expectedSpecialized: Int
    let stageACandidates: Int
    let routed: Int
    let correctRouted: Int
    let falseRouted: Int
    let stageARecall: Double
    let stageBExactAccuracy: Double
    let finalPrecision: Double
    let finalPrecisionWilsonLower95: Double
    let finalRecall: Double
}

private struct VerifierEvaluation: Encodable {
    let id: String
    let deploymentMode: String
    let acceptedForAutomaticRouting: Bool
    let metrics: VerifierRoutingMetrics
    let metricsByLanguage: [String: VerifierRoutingMetrics]
    let metricsBySource: [String: VerifierRoutingMetrics]
    let leaveOneSourceOut: [String: VerifierRoutingMetrics]
    let coldLoadMilliseconds: Double
    let warmMedianMilliseconds: Double
    let warmP95Milliseconds: Double
}

private struct Report: Encodable {
    let generatedAt: String
    let seed: Int
    let corpusRecordCount: Int
    let familyCount: Int
    let languageCounts: [String: Int]
    let exactTrainingOverlapCount: Int
    let manifestSchemaVersion: Int
    let binaryMacro: AggregateMetrics
    let binaryMacroByLanguage: [String: AggregateMetrics]
    let classifiers: [BinaryEvaluation]
    let verifierLayers: [VerifierEvaluation]
    let sentiment: SentimentMetrics
    let sentimentBySource: [String: SentimentMetrics]
}

private struct BinaryObservation {
    let record: HoldoutRecord
    let expected: Bool
    let predicted: Bool
    let confidence: Double
    let isSuppressed: Bool
}

private struct VerifierObservation {
    let record: HoldoutRecord
    let expectedLabel: String
    let isStageACandidate: Bool
    let predictedLabel: String
    let confidence: Double
    let margin: Double
    let isRouted: Bool
    let latencyMilliseconds: Double
}

private let fileManager = FileManager.default
private let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private func argumentValue(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private let corpusURL = argumentValue(after: "--corpus").map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? root.appendingPathComponent(
    "ModelTraining/ClipboardSemantics/random-holdout-corpus.jsonl"
)
private let trainingCorpusURL = argumentValue(after: "--training-corpus").map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? root.appendingPathComponent(
    "ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl"
)
private let manifestURL = argumentValue(after: "--manifest").map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? root.appendingPathComponent(
    "OSGKeyboardShared/Resources/ClipboardSemantics/clipboard-semantic-models.json"
)
private let modelDirectory = argumentValue(after: "--models").map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? manifestURL.deletingLastPathComponent()
private let reportURL = argumentValue(after: "--report").map {
    URL(fileURLWithPath: $0, relativeTo: root).standardizedFileURL
} ?? root.appendingPathComponent(
    "ModelTraining/ClipboardSemantics/random-holdout-report.json"
)
private let sentimentMinimumConfidence = 0.65
private let sentimentMinimumMargin = 0.15
private let holdoutSeed = argumentValue(after: "--seed").flatMap(Int.init) ?? 20260826
private let includesRejectedModels = CommandLine.arguments.contains(
    "--include-rejected-models"
)
private let requestedSplit = argumentValue(after: "--split")
private let requestedLanguage = argumentValue(after: "--language")

private func rounded(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return (value * 10_000).rounded() / 10_000
}

private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}

private func decodeJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
    let content = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    return try content.split(separator: "\n").map {
        try decoder.decode(type, from: Data($0.utf8))
    }
}

private func normalized(_ text: String) -> String {
    text
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
}

private func compileModel(sourceURL: URL, outputDirectory: URL) throws -> URL {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
        "coremlcompiler",
        "compile",
        sourceURL.path,
        outputDirectory.path
    ]
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: data, encoding: .utf8) ?? ""
        throw NSError(
            domain: "RandomHoldoutEvaluation",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output]
        )
    }
    let resourceName = sourceURL.deletingPathExtension().lastPathComponent
    return outputDirectory.appendingPathComponent("\(resourceName).mlmodelc")
}

private func binaryMetrics(_ observations: [BinaryObservation]) -> BinaryMetrics {
    var truePositive = 0
    var trueNegative = 0
    var falsePositive = 0
    var falseNegative = 0
    for observation in observations {
        switch (observation.expected, observation.predicted) {
        case (true, true): truePositive += 1
        case (false, false): trueNegative += 1
        case (false, true): falsePositive += 1
        case (true, false): falseNegative += 1
        }
    }
    let total = observations.count
    let precision = truePositive + falsePositive > 0
        ? Double(truePositive) / Double(truePositive + falsePositive)
        : 0
    let recall = truePositive + falseNegative > 0
        ? Double(truePositive) / Double(truePositive + falseNegative)
        : 0
    let accuracy = total > 0
        ? Double(truePositive + trueNegative) / Double(total)
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
        accuracy: rounded(accuracy),
        precision: rounded(precision),
        recall: rounded(recall),
        f1: rounded(f1)
    )
}

private func thresholdRecommendation(
    observations: [BinaryObservation],
    minimumPrecision: Double
) -> ThresholdRecommendation? {
    let candidates = stride(from: 0.05, through: 0.99, by: 0.01).compactMap { threshold
        -> ThresholdRecommendation? in
        let adjusted = observations.map {
            BinaryObservation(
                record: $0.record,
                expected: $0.expected,
                predicted: !$0.isSuppressed && $0.confidence >= threshold,
                confidence: $0.confidence,
                isSuppressed: $0.isSuppressed
            )
        }
        let metrics = binaryMetrics(adjusted)
        guard metrics.truePositive > 0, metrics.precision >= minimumPrecision else {
            return nil
        }
        return ThresholdRecommendation(
            threshold: rounded(threshold),
            metrics: metrics
        )
    }
    return candidates.max {
        if $0.metrics.recall != $1.metrics.recall {
            return $0.metrics.recall < $1.metrics.recall
        }
        if $0.metrics.precision != $1.metrics.precision {
            return $0.metrics.precision < $1.metrics.precision
        }
        return $0.threshold > $1.threshold
    }
}

private func shouldSuppressTask(
    text: String,
    complaintConfidence: Double
) -> Bool {
    guard complaintConfidence >= 0.60 else { return false }
    let normalized = text.lowercased()
    let explicitTaskMarkers = [
        "请", "麻烦", "能否", "可以请你", "由你", "交给你", "需要你",
        "你负责", "下一步", "行动项", "please ", "can you", "could you",
        "would you", "assigned to you", "you are responsible", "we need you",
        "would like you", "counting on you", "take ownership", "your task",
        "next action", "complete the", "finish the", "send it to",
        "deliver it to"
    ]
    return !explicitTaskMarkers.contains { normalized.contains($0) }
}

private func hasExplicitBlessingMarker(in text: String) -> Bool {
    let normalized = text.lowercased()
    let quotedOrMetaContexts = [
        "祝福模板", "祝福语模板", "文章引用", "搜索词", "系统正在检查",
        "文档里收录", "贺卡名单", "收集祝福", "greeting template",
        "message template", "the article quotes", "search phrase",
        "system is checking", "document contains", "card list",
        "quotes the phrase", "如何描述生日快乐", "怎么说生日快乐",
        "如何写生日祝福", "how would you describe a happy birthday",
        "how do you say happy birthday", "what does happy birthday mean",
        "宁愿你", "祝你倒闭", "祝你立马倒闭", "祝你去死", "祝你倒霉",
        "祝你失败", "祝你完蛋"
    ]
    guard !quotedOrMetaContexts.contains(where: { normalized.contains($0) }) else {
        return false
    }
    let markers = [
        "生日快乐", "新年快乐", "春节快乐", "节日快乐", "圣诞快乐",
        "中秋快乐", "恭喜", "预祝", "祝你", "祝您", "祝大家", "祝他", "祝她",
        "愿你", "愿您", "happy birthday", "happy new year",
        "merry christmas", "happy holidays", "congratulations",
        "congrats", "best wishes", "good luck", "wishing you",
        "wish you", "wish him", "wish her", "wish them", "let us wish",
        "let's wish", "we wish", "may you"
    ]
    return markers.contains { normalized.contains($0) }
}

private func aggregate(_ metrics: [BinaryMetrics]) -> AggregateMetrics {
    let divisor = Double(max(metrics.count, 1))
    return AggregateMetrics(
        accuracy: rounded(metrics.reduce(0) { $0 + $1.accuracy } / divisor),
        precision: rounded(metrics.reduce(0) { $0 + $1.precision } / divisor),
        recall: rounded(metrics.reduce(0) { $0 + $1.recall } / divisor),
        f1: rounded(metrics.reduce(0) { $0 + $1.f1 } / divisor)
    )
}

private func errorExamples(
    from observations: [BinaryObservation],
    expected: Bool,
    predicted: Bool
) -> [ErrorExample] {
    observations
        .filter { $0.expected == expected && $0.predicted == predicted }
        .sorted { $0.confidence > $1.confidence }
        .prefix(5)
        .map {
            ErrorExample(
                id: $0.record.id,
                language: $0.record.language,
                family: $0.record.family,
                sourceDataset: $0.record.sourceDataset,
                text: $0.record.text,
                confidence: rounded($0.confidence)
            )
        }
}

private func wilsonLowerBound(successes: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    let z = 1.959_963_984_540_054
    let proportion = Double(successes) / Double(total)
    let denominator = 1 + z * z / Double(total)
    let center = proportion + z * z / (2 * Double(total))
    let adjustment = z * sqrt(
        (
            proportion * (1 - proportion)
                + z * z / (4 * Double(total))
        ) / Double(total)
    )
    return rounded((center - adjustment) / denominator)
}

private func verifierMetrics(
    _ observations: [VerifierObservation]
) -> VerifierRoutingMetrics {
    let expectedSpecialized = observations.filter {
        $0.expectedLabel != "neither"
    }.count
    let stageACandidates = observations.filter(\.isStageACandidate).count
    let stageATruePositives = observations.filter {
        $0.isStageACandidate && $0.expectedLabel != "neither"
    }.count
    let stageBObservations = observations.filter(\.isStageACandidate)
    let stageBCorrect = stageBObservations.filter {
        $0.predictedLabel == $0.expectedLabel
    }.count
    let routed = observations.filter(\.isRouted)
    let correctRouted = routed.filter {
        $0.predictedLabel == $0.expectedLabel
    }.count
    let stageARecall = expectedSpecialized > 0
        ? Double(stageATruePositives) / Double(expectedSpecialized)
        : 0
    let stageBAccuracy = stageBObservations.isEmpty
        ? 0
        : Double(stageBCorrect) / Double(stageBObservations.count)
    let precision = routed.isEmpty
        ? 0
        : Double(correctRouted) / Double(routed.count)
    let recall = expectedSpecialized > 0
        ? Double(correctRouted) / Double(expectedSpecialized)
        : 0
    return VerifierRoutingMetrics(
        total: observations.count,
        expectedSpecialized: expectedSpecialized,
        stageACandidates: stageACandidates,
        routed: routed.count,
        correctRouted: correctRouted,
        falseRouted: routed.count - correctRouted,
        stageARecall: rounded(stageARecall),
        stageBExactAccuracy: rounded(stageBAccuracy),
        finalPrecision: rounded(precision),
        finalPrecisionWilsonLower95: wilsonLowerBound(
            successes: correctRouted,
            total: routed.count
        ),
        finalRecall: rounded(recall)
    )
}

private func percentile(_ values: [Double], proportion: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(
        Int((Double(sorted.count - 1) * proportion).rounded()),
        sorted.count - 1
    )
    return rounded(sorted[index])
}

private func candidateClassifierIDs(for verifierID: String) -> [String] {
    if verifierID == "action" {
        return ["task", "question", "complaint"]
    }
    return [
        "invitation",
        "scheduleNegotiation",
        "confirmationDecision",
        "followUpReminder"
    ]
}

private func isStageACandidate(
    record: HoldoutRecord,
    verifierID: String,
    models: [String: NLModel],
    configurations: [String: ManifestClassifier]
) -> Bool {
    candidateClassifierIDs(for: verifierID).contains { classifierID in
        guard let model = models[classifierID],
              let configuration = configurations[classifierID],
              let positiveLabel = configuration.positiveLabel else {
            return false
        }
        let confidence = model.predictedLabelHypotheses(
            for: record.text,
            maximumCount: 2
        )[positiveLabel] ?? 0
        let configuredThreshold = configuration
            .confidenceThresholdsByLanguage?[record.language]
            ?? configuration.confidenceThreshold
            ?? 1
        return confidence >= min(configuredThreshold, 0.50)
    }
}

private func sentimentMetrics(
    records: [HoldoutRecord],
    model: NLModel
) -> SentimentMetrics {
    let labels = ["negative", "neutral", "positive"]
    var confusion: [String: [String: Int]] = [:]
    var correct = 0
    var unknown = 0

    for record in records {
        let ranked = model.predictedLabelHypotheses(for: record.text, maximumCount: 3)
            .sorted { $0.value > $1.value }
        let winner = ranked.first
        let runnerUp = ranked.dropFirst().first?.value ?? 0
        let prediction: String
        if let winner,
           winner.value >= sentimentMinimumConfidence,
           winner.value - runnerUp >= sentimentMinimumMargin {
            prediction = winner.key
        } else {
            prediction = "unknown"
            unknown += 1
        }
        confusion[record.sentiment, default: [:]][prediction, default: 0] += 1
        if prediction == record.sentiment {
            correct += 1
        }
    }

    var perLabelF1: [String: Double] = [:]
    for label in labels {
        let truePositive = confusion[label]?[label] ?? 0
        let falseNegative = (confusion[label] ?? [:])
            .filter { $0.key != label }
            .reduce(0) { $0 + $1.value }
        let falsePositive = labels
            .filter { $0 != label }
            .reduce(0) { $0 + (confusion[$1]?[label] ?? 0) }
        let precision = truePositive + falsePositive > 0
            ? Double(truePositive) / Double(truePositive + falsePositive)
            : 0
        let recall = truePositive + falseNegative > 0
            ? Double(truePositive) / Double(truePositive + falseNegative)
            : 0
        perLabelF1[label] = rounded(
            precision + recall > 0
                ? 2 * precision * recall / (precision + recall)
                : 0
        )
    }
    let macroF1 = perLabelF1.values.reduce(0, +) / Double(labels.count)
    return SentimentMetrics(
        total: records.count,
        correct: correct,
        unknown: unknown,
        accuracy: rounded(Double(correct) / Double(max(records.count, 1))),
        unknownRate: rounded(Double(unknown) / Double(max(records.count, 1))),
        macroF1: rounded(macroF1),
        perLabelF1: perLabelF1
    )
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
}

private func main() throws {
    let decodedRecords = try decodeJSONLines(HoldoutRecord.self, from: corpusURL)
    let splitRecords = requestedSplit.map { split in
        decodedRecords.filter { $0.split == split }
    } ?? decodedRecords
    let records = requestedLanguage.map { language in
        splitRecords.filter { $0.language == language }
    } ?? splitRecords
    let trainingRecords = try decodeJSONLines(TrainingRecord.self, from: trainingCorpusURL)
    let manifest = try JSONDecoder().decode(
        Manifest.self,
        from: Data(contentsOf: manifestURL)
    )
    let trainingTexts = Set(
        trainingRecords
            .filter { $0.split == nil || $0.split == "train" }
            .map { normalized($0.text) }
    )
    let exactOverlapCount = records.filter { trainingTexts.contains(normalized($0.text)) }.count

    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
        "osg-random-holdout-\(UUID().uuidString)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer { try? fileManager.removeItem(at: temporaryDirectory) }

    var models: [String: NLModel] = [:]
    let classifierConfigurations = Dictionary(
        uniqueKeysWithValues: manifest.classifiers.map { ($0.id, $0) }
    )
    for configuration in manifest.classifiers {
        let sourceURL = modelDirectory.appendingPathComponent(configuration.modelFile)
        let compiledURL = try compileModel(
            sourceURL: sourceURL,
            outputDirectory: temporaryDirectory
        )
        let model = try NLModel(contentsOf: compiledURL)
        models[configuration.id] = model
    }
    var verifierModels: [String: NLModel] = [:]
    var verifierLoadMilliseconds: [String: Double] = [:]
    for configuration in manifest.verifiers ?? [] {
        let sourceURL = modelDirectory.appendingPathComponent(configuration.modelFile)
        let compiledURL = try compileModel(
            sourceURL: sourceURL,
            outputDirectory: temporaryDirectory
        )
        let startedAt = ContinuousClock.now
        verifierModels[configuration.id] = try NLModel(contentsOf: compiledURL)
        verifierLoadMilliseconds[configuration.id] = milliseconds(
            startedAt.duration(to: .now)
        )
    }

    var binaryEvaluations: [BinaryEvaluation] = []
    let sentimentRecords = records.filter { $0.hasKnownLabel("sentiment") }
    let sentimentResult = models["sentiment"].map {
        sentimentMetrics(records: sentimentRecords, model: $0)
    }
    for configuration in manifest.classifiers {
        if configuration.id == "sentiment" {
            continue
        }
        guard let model = models[configuration.id] else { continue }
        guard let positiveLabel = configuration.positiveLabel else {
            continue
        }
        let observations = records
            .filter { $0.hasKnownLabel(configuration.id) }
            .map { record in
            let confidence = model.predictedLabelHypotheses(
                for: record.text,
                maximumCount: 2
            )[positiveLabel] ?? 0
            let threshold = configuration.confidenceThresholdsByLanguage?[record.language]
                ?? configuration.confidenceThreshold
                ?? 1
            let complaintConfidence: Double
            if configuration.id == "task", let complaintModel = models["complaint"] {
                complaintConfidence = complaintModel.predictedLabelHypotheses(
                    for: record.text,
                    maximumCount: 2
                )["complaint"] ?? 0
            } else {
                complaintConfidence = 0
            }
            let hasBlessingMarker = configuration.id == "blessing"
                && hasExplicitBlessingMarker(in: record.text)
            let effectiveConfidence = hasBlessingMarker ? 1 : confidence
            let isTaskSuppressed = configuration.id == "task"
                && shouldSuppressTask(
                    text: record.text,
                    complaintConfidence: complaintConfidence
                )
            let isBlessingSuppressed = configuration.id == "blessing"
                && !hasBlessingMarker
            let isSuppressed = isTaskSuppressed || isBlessingSuppressed
            return BinaryObservation(
                record: record,
                expected: record.isPositive(for: configuration.id),
                predicted: (configuration.acceptedForAutomaticRouting || includesRejectedModels)
                    && !isSuppressed
                    && effectiveConfidence >= threshold,
                confidence: effectiveConfidence,
                isSuppressed: isSuppressed
            )
        }
        let byLanguage = Dictionary(grouping: observations) { $0.record.language }
        let metricsByLanguage = byLanguage.mapValues(binaryMetrics)
        let metricsBySource = Dictionary(grouping: observations) {
            $0.record.sourceDataset ?? $0.record.family
        }.mapValues(binaryMetrics)
        binaryEvaluations.append(
            BinaryEvaluation(
                id: configuration.id,
                metrics: binaryMetrics(observations),
                metricsByLanguage: metricsByLanguage,
                metricsBySource: metricsBySource,
                thresholdAt90Precision: thresholdRecommendation(
                    observations: observations,
                    minimumPrecision: 0.90
                ),
                thresholdAt95Precision: thresholdRecommendation(
                    observations: observations,
                    minimumPrecision: 0.95
                ),
                thresholdsAt90PrecisionByLanguage: byLanguage.compactMapValues {
                    thresholdRecommendation(observations: $0, minimumPrecision: 0.90)
                },
                thresholdsAt95PrecisionByLanguage: byLanguage.compactMapValues {
                    thresholdRecommendation(observations: $0, minimumPrecision: 0.95)
                },
                falsePositiveExamples: errorExamples(
                    from: observations,
                    expected: false,
                    predicted: true
                ),
                falseNegativeExamples: errorExamples(
                    from: observations,
                    expected: true,
                    predicted: false
                )
            )
        )
    }

    let verifierEvaluations = (manifest.verifiers ?? []).compactMap { configuration
        -> VerifierEvaluation? in
        guard let model = verifierModels[configuration.id] else { return nil }
        let observations = records.map { record -> VerifierObservation in
            let candidate = isStageACandidate(
                record: record,
                verifierID: configuration.id,
                models: models,
                configurations: classifierConfigurations
            )
            guard candidate else {
                return VerifierObservation(
                    record: record,
                    expectedLabel: record.expectedVerifierLabel(
                        for: configuration.id
                    ),
                    isStageACandidate: false,
                    predictedLabel: "neither",
                    confidence: 0,
                    margin: 0,
                    isRouted: false,
                    latencyMilliseconds: 0
                )
            }
            let startedAt = ContinuousClock.now
            let ranked = model.predictedLabelHypotheses(
                for: record.text,
                maximumCount: 2
            ).sorted { $0.value > $1.value }
            let elapsed = startedAt.duration(to: .now)
            let winner = ranked.first ?? (key: "neither", value: 0)
            let margin = winner.value - (ranked.dropFirst().first?.value ?? 0)
            let threshold = configuration
                .confidenceThresholdsByLanguage?[record.language]
                ?? configuration.confidenceThreshold
            let minimumMargin = configuration
                .minimumMarginsByLanguage?[record.language]
                ?? configuration.minimumMargin
            return VerifierObservation(
                record: record,
                expectedLabel: record.expectedVerifierLabel(
                    for: configuration.id
                ),
                isStageACandidate: true,
                predictedLabel: winner.key,
                confidence: winner.value,
                margin: margin,
                isRouted: winner.key != "neither"
                    && winner.value >= threshold
                    && margin >= minimumMargin,
                latencyMilliseconds: milliseconds(
                    elapsed
                )
            )
        }
        let byLanguage = Dictionary(grouping: observations) {
            $0.record.language
        }.mapValues(verifierMetrics)
        let bySourceGroups = Dictionary(grouping: observations) {
            $0.record.sourceDataset ?? $0.record.family
        }
        let bySource = bySourceGroups.mapValues(verifierMetrics)
        let leaveOneSourceOut = Dictionary(uniqueKeysWithValues: bySourceGroups.keys.map { source
            in
            (
                source,
                verifierMetrics(
                    observations.filter {
                        ($0.record.sourceDataset ?? $0.record.family) != source
                    }
                )
            )
        })
        let latencies = observations.filter(\.isStageACandidate)
            .map(\.latencyMilliseconds)
        return VerifierEvaluation(
            id: configuration.id,
            deploymentMode: configuration.deploymentMode,
            acceptedForAutomaticRouting:
                configuration.acceptedForAutomaticRouting,
            metrics: verifierMetrics(observations),
            metricsByLanguage: byLanguage,
            metricsBySource: bySource,
            leaveOneSourceOut: leaveOneSourceOut,
            coldLoadMilliseconds: rounded(
                verifierLoadMilliseconds[configuration.id] ?? 0
            ),
            warmMedianMilliseconds: percentile(latencies, proportion: 0.50),
            warmP95Milliseconds: percentile(latencies, proportion: 0.95)
        )
    }

    guard let sentimentResult else {
        throw NSError(
            domain: "RandomHoldoutEvaluation",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Sentiment model was not evaluated"]
        )
    }
    let languages = Set(records.map(\.language)).sorted()
    let macroByLanguage = Dictionary(uniqueKeysWithValues: languages.map { language in
        let metrics = binaryEvaluations.compactMap {
            $0.metricsByLanguage[language]
        }
        return (language, aggregate(metrics))
    })
    let sentimentModel = models["sentiment"]!
    let sentimentBySource = Dictionary(grouping: sentimentRecords) {
        $0.sourceDataset ?? $0.family
    }.mapValues {
        sentimentMetrics(records: $0, model: sentimentModel)
    }
    let report = Report(
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        seed: holdoutSeed,
        corpusRecordCount: records.count,
        familyCount: Set(records.map(\.family)).count,
        languageCounts: Dictionary(grouping: records, by: \.language).mapValues(\.count),
        exactTrainingOverlapCount: exactOverlapCount,
        manifestSchemaVersion: manifest.schemaVersion,
        binaryMacro: aggregate(binaryEvaluations.map(\.metrics)),
        binaryMacroByLanguage: macroByLanguage,
        classifiers: binaryEvaluations,
        verifierLayers: verifierEvaluations,
        sentiment: sentimentResult,
        sentimentBySource: sentimentBySource
    )
    try writeJSON(report, to: reportURL)
    print(
        "RANDOM_HOLDOUT_EVAL_DONE records=\(records.count) "
            + "overlap=\(exactOverlapCount) "
            + "macroPrecision=\(report.binaryMacro.precision) "
            + "macroRecall=\(report.binaryMacro.recall) "
            + "macroF1=\(report.binaryMacro.f1) "
            + "verifiers=\(report.verifierLayers.count) "
            + "sentimentMacroF1=\(report.sentiment.macroF1)"
    )
}

do {
    try main()
} catch {
    fputs("RANDOM_HOLDOUT_EVAL_FAILED \(error)\n", stderr)
    exit(1)
}

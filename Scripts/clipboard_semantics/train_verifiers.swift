#!/usr/bin/env xcrun swift

import CreateML
import Foundation

private struct BaseRecord: Decodable {
    let id: String
    let text: String
    let language: String
    let split: String
    let task: Bool
    let question: Bool
    let invitation: Bool
    let complaint: Bool
    let scheduleNegotiation: Bool
    let confirmationDecision: Bool
    let followUpReminder: Bool
}

private struct SilverRecord: Decodable {
    let id: String
    let text: String
    let language: String
    let split: String
    let actionVerifierLabel: String
    let coordinationVerifierLabel: String
    let sourceDataset: String?
}

private struct VerifierExample {
    let id: String
    let text: String
    let language: String
    let split: String
    let label: String
    let sourceDataset: String?
}

private struct RoutingMetrics: Encodable {
    let total: Int
    let expectedSpecialized: Int
    let routed: Int
    let correctRouted: Int
    let falseRouted: Int
    let missedSpecialized: Int
    let precision: Double
    let recall: Double
    let f1: Double
    let routedByLabel: [String: Int]
    let correctByLabel: [String: Int]
}

private struct ThresholdSelection: Encodable {
    let confidenceThreshold: Double
    let minimumMargin: Double
    let metrics: RoutingMetrics
}

private struct GateResult: Encodable {
    let accepted: Bool
    let reason: String
    let minimumPredictedPositivesPerLabelAndLanguage: Int
    let supportByLabelAndLanguage: [String: Int]
    let precisionByLabelAndLanguage: [String: Double]
    let maximumSourceShareByLabelAndLanguage: [String: Double]
}

private struct VerifierReport: Encodable {
    let id: String
    let labels: [String]
    let modelFile: String
    let modelBytes: Int
    let trainingCount: Int
    let calibrationCount: Int
    let thresholdCalibrationCount: Int
    let acceptanceCount: Int
    let threshold: ThresholdSelection
    let thresholdsByLanguage: [String: ThresholdSelection]
    let calibrationMetrics: RoutingMetrics
    let acceptanceMetrics: RoutingMetrics
    let acceptanceByLanguage: [String: RoutingMetrics]
    let gate: GateResult
}

private struct TrainingReport: Encodable {
    let generatedAt: String
    let baseCorpusPath: String
    let silverDirectoryPath: String
    let selectionPolicy: String
    let verifiers: [VerifierReport]
}

private struct Observation {
    let example: VerifierExample
    let predictedLabel: String
    let confidence: Double
    let margin: Double
}

private enum VerifierID: String, CaseIterable {
    case action
    case coordination

    var labels: [String] {
        switch self {
        case .action:
            ["taskOnly", "complaintOnly", "both", "questionRequest", "neither"]
        case .coordination:
            [
                "invitation",
                "scheduleNegotiation",
                "confirmationDecision",
                "followUpReminder",
                "neither"
            ]
        }
    }

    var modelFile: String {
        switch self {
        case .action: "ActionIntentVerifier.mlmodel"
        case .coordination: "CoordinationIntentVerifier.mlmodel"
        }
    }

    func baseLabel(for record: BaseRecord) -> String? {
        switch self {
        case .action:
            if record.task && record.complaint {
                return "both"
            }
            if record.task {
                return "taskOnly"
            }
            if record.complaint {
                return "complaintOnly"
            }
            if record.question {
                return "questionRequest"
            }
            return "neither"
        case .coordination:
            let matches = [
                record.invitation ? "invitation" : nil,
                record.scheduleNegotiation ? "scheduleNegotiation" : nil,
                record.confirmationDecision ? "confirmationDecision" : nil,
                record.followUpReminder ? "followUpReminder" : nil
            ].compactMap { $0 }
            guard matches.count <= 1 else { return nil }
            return matches.first ?? "neither"
        }
    }

    func silverLabel(for record: SilverRecord) -> String {
        switch self {
        case .action: record.actionVerifierLabel
        case .coordination: record.coordinationVerifierLabel
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

private let fileManager = FileManager.default
private let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)

private func argumentValue(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.indices.contains(index + 1) else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private func resolvedURL(flag: String, defaultPath: String) -> URL {
    URL(
        fileURLWithPath: argumentValue(after: flag) ?? defaultPath,
        relativeTo: root
    ).standardizedFileURL
}

private let baseCorpusURL = resolvedURL(
    flag: "--base-corpus",
    defaultPath: "ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl"
)
private let silverDirectoryURL = resolvedURL(
    flag: "--silver-directory",
    defaultPath: "ModelTraining/ClipboardSemantics/Consensus"
)
private let baseManifestURL = resolvedURL(
    flag: "--base-manifest",
    defaultPath:
        "OSGKeyboardShared/Resources/ClipboardSemantics/clipboard-semantic-models.json"
)
private let outputDirectoryURL = resolvedURL(
    flag: "--output-directory",
    defaultPath: "ModelTraining/ClipboardSemantics/VerifierCandidates"
)
private let reportURL = resolvedURL(
    flag: "--report",
    defaultPath: "ModelTraining/ClipboardSemantics/verifier-training-report.json"
)

private func readJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
    let content = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    return try content.split(separator: "\n").map {
        try decoder.decode(type, from: Data($0.utf8))
    }
}

private func rounded(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return (value * 10_000).rounded() / 10_000
}

private func stableSeed(_ value: String) -> UInt64 {
    value.utf8.reduce(0xcbf2_9ce4_8422_2325) { partial, byte in
        (partial ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
}

private func examples(
    verifier: VerifierID,
    baseRecords: [BaseRecord],
    silverRecords: [SilverRecord],
    baseSplit: String,
    silverSplit: String
) -> [VerifierExample] {
    let base = baseRecords.compactMap { record -> VerifierExample? in
        guard record.split == baseSplit,
              let label = verifier.baseLabel(for: record) else {
            return nil
        }
        return VerifierExample(
            id: record.id,
            text: record.text,
            language: record.language,
            split: baseSplit,
            label: label,
            sourceDataset: nil
        )
    }
    let silver = silverRecords.compactMap { record -> VerifierExample? in
        guard record.split == silverSplit else { return nil }
        return VerifierExample(
            id: record.id,
            text: record.text,
            language: record.language,
            split: silverSplit,
            label: verifier.silverLabel(for: record),
            sourceDataset: record.sourceDataset
        )
    }
    return base + silver
}

private func balancedTexts(
    examples: [VerifierExample],
    verifier: VerifierID,
    split: String
) -> [String: [String]] {
    var grouped = Dictionary(grouping: examples, by: \.label)
    if verifier == .action {
        let taskExamples = grouped["taskOnly"] ?? []
        let complaintExamples = grouped["complaintOnly"] ?? []
        let targetCount = min(taskExamples.count, complaintExamples.count)
        var bothExamples = grouped["both"] ?? []
        if !taskExamples.isEmpty, !complaintExamples.isEmpty {
            for index in bothExamples.count..<targetCount {
                let task = taskExamples[index % taskExamples.count]
                let complaint = complaintExamples[
                    Int(
                        stableSeed("\(split)|both|\(index)")
                            % UInt64(complaintExamples.count)
                    )
                ]
                bothExamples.append(
                    VerifierExample(
                        id: "composed-both-\(split)-\(index)",
                        text: "\(complaint.text)\n\(task.text)",
                        language: task.language,
                        split: split,
                        label: "both",
                        sourceDataset: "generated-composition"
                    )
                )
            }
            grouped["both"] = bothExamples
        }
    }
    let minimumCount = verifier.labels.compactMap { grouped[$0]?.count }.min() ?? 0
    precondition(minimumCount > 0, "Missing \(verifier.rawValue) label in \(split)")
    return Dictionary(uniqueKeysWithValues: verifier.labels.enumerated().map { offset, label in
        var generator = SeededGenerator(
            seed: stableSeed("\(verifier.rawValue)|\(split)|\(label)|\(offset)")
        )
        let texts = (grouped[label] ?? []).map(\.text).shuffled(using: &generator)
        return (label, Array(texts.prefix(minimumCount)))
    })
}

private func observations(
    model: MLTextClassifier,
    examples: [VerifierExample]
) throws -> [Observation] {
    try examples.map { example in
        let hypotheses = try model.predictionWithConfidence(from: example.text)
            .sorted { $0.value > $1.value }
        let winner = hypotheses.first ?? (key: "neither", value: 0)
        let runnerUp = hypotheses.dropFirst().first?.value ?? 0
        return Observation(
            example: example,
            predictedLabel: winner.key,
            confidence: winner.value,
            margin: winner.value - runnerUp
        )
    }
}

private func routingMetrics(
    observations: [Observation],
    confidenceThreshold: Double,
    minimumMargin: Double
) -> RoutingMetrics {
    var routed = 0
    var correctRouted = 0
    var expectedSpecialized = 0
    var missedSpecialized = 0
    var routedByLabel: [String: Int] = [:]
    var correctByLabel: [String: Int] = [:]
    for observation in observations {
        let expectedIsSpecialized = observation.example.label != "neither"
        if expectedIsSpecialized {
            expectedSpecialized += 1
        }
        let shouldRoute = observation.predictedLabel != "neither"
            && observation.confidence >= confidenceThreshold
            && observation.margin >= minimumMargin
        if shouldRoute {
            routed += 1
            routedByLabel[observation.predictedLabel, default: 0] += 1
            if observation.predictedLabel == observation.example.label {
                correctRouted += 1
                correctByLabel[observation.predictedLabel, default: 0] += 1
            }
        } else if expectedIsSpecialized {
            missedSpecialized += 1
        }
    }
    let precision = routed > 0 ? Double(correctRouted) / Double(routed) : 0
    let recall = expectedSpecialized > 0
        ? Double(correctRouted) / Double(expectedSpecialized)
        : 0
    return RoutingMetrics(
        total: observations.count,
        expectedSpecialized: expectedSpecialized,
        routed: routed,
        correctRouted: correctRouted,
        falseRouted: routed - correctRouted,
        missedSpecialized: missedSpecialized,
        precision: rounded(precision),
        recall: rounded(recall),
        f1: rounded(
            precision + recall > 0
                ? 2 * precision * recall / (precision + recall)
                : 0
        ),
        routedByLabel: routedByLabel,
        correctByLabel: correctByLabel
    )
}

private func selectedThreshold(
    observations: [Observation]
) -> ThresholdSelection {
    var selections: [ThresholdSelection] = []
    for confidenceStep in 50...99 {
        for marginStep in 0...10 {
            let confidence = Double(confidenceStep) / 100
            let margin = Double(marginStep) / 20
            let metrics = routingMetrics(
                observations: observations,
                confidenceThreshold: confidence,
                minimumMargin: margin
            )
            if metrics.precision >= 0.95 {
                selections.append(
                    ThresholdSelection(
                        confidenceThreshold: confidence,
                        minimumMargin: margin,
                        metrics: metrics
                    )
                )
            }
        }
    }
    return selections.max {
        if $0.metrics.recall != $1.metrics.recall {
            return $0.metrics.recall < $1.metrics.recall
        }
        if $0.metrics.routed != $1.metrics.routed {
            return $0.metrics.routed < $1.metrics.routed
        }
        if $0.confidenceThreshold != $1.confidenceThreshold {
            return $0.confidenceThreshold > $1.confidenceThreshold
        }
        return $0.minimumMargin > $1.minimumMargin
    } ?? ThresholdSelection(
        confidenceThreshold: 1,
        minimumMargin: 1,
        metrics: routingMetrics(
            observations: observations,
            confidenceThreshold: 1,
            minimumMargin: 1
        )
    )
}

private func gateResult(
    verifier: VerifierID,
    observations: [Observation],
    thresholdsByLanguage: [String: ThresholdSelection],
    globalThreshold: ThresholdSelection
) -> GateResult {
    var support: [String: Int] = [:]
    var correct: [String: Int] = [:]
    var sourceSupport: [String: [String: Int]] = [:]
    for observation in observations {
        let selection = thresholdsByLanguage[observation.example.language]
            ?? globalThreshold
        let routed = observation.predictedLabel != "neither"
            && observation.confidence >= selection.confidenceThreshold
            && observation.margin >= selection.minimumMargin
        guard routed else { continue }
        let key = "\(observation.example.language)|\(observation.predictedLabel)"
        support[key, default: 0] += 1
        let source = observation.example.sourceDataset ?? "generated-base"
        sourceSupport[key, default: [:]][source, default: 0] += 1
        if observation.predictedLabel == observation.example.label {
            correct[key, default: 0] += 1
        }
    }
    let precision = Dictionary(uniqueKeysWithValues: support.map { key, count in
        (
            key,
            rounded(Double(correct[key] ?? 0) / Double(max(count, 1)))
        )
    })
    let maximumSourceShare = Dictionary(uniqueKeysWithValues: support.map { key, count in
        let maximum = sourceSupport[key]?.values.max() ?? 0
        return (key, rounded(Double(maximum) / Double(max(count, 1))))
    })
    let requiredKeys = ["en", "zh-Hans"].flatMap { language in
        verifier.labels
            .filter { $0 != "neither" }
            .map { "\(language)|\($0)" }
    }
    let accepted = requiredKeys.allSatisfy {
        support[$0, default: 0] >= 100
            && precision[$0, default: 0] >= 0.95
            && maximumSourceShare[$0, default: 1] <= 0.65
    }
    return GateResult(
        accepted: accepted,
        reason: accepted
            ? "Every routed label/language meets precision, support, and source-diversity gates."
            : "Shadow only: at least one label/language misses precision, support, or source-diversity gates.",
        minimumPredictedPositivesPerLabelAndLanguage: 100,
        supportByLabelAndLanguage: support,
        precisionByLabelAndLanguage: precision,
        maximumSourceShareByLabelAndLanguage: maximumSourceShare
    )
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
}

private func train(
    verifier: VerifierID,
    baseRecords: [BaseRecord],
    silverRecords: [SilverRecord]
) throws -> (VerifierReport, [String: Any]) {
    let training = examples(
        verifier: verifier,
        baseRecords: baseRecords,
        silverRecords: silverRecords,
        baseSplit: "train",
        silverSplit: "silverTrain"
    )
    let calibration = examples(
        verifier: verifier,
        baseRecords: baseRecords,
        silverRecords: silverRecords,
        baseSplit: "validation",
        silverSplit: "silverCalibration"
    )
    let acceptance = examples(
        verifier: verifier,
        baseRecords: baseRecords,
        silverRecords: silverRecords,
        baseSplit: "golden",
        silverSplit: "silverAcceptance"
    )
    let trainingTexts = balancedTexts(
        examples: training,
        verifier: verifier,
        split: "train"
    )
    let calibrationTexts = balancedTexts(
        examples: calibration,
        verifier: verifier,
        split: "calibration"
    )
    let parameters = MLTextClassifier.ModelParameters(
        validation: .dictionary(calibrationTexts),
        algorithm: .maxEnt(revision: 1)
    )
    let model = try MLTextClassifier(
        trainingData: trainingTexts,
        parameters: parameters
    )
    let modelURL = outputDirectoryURL.appendingPathComponent(verifier.modelFile)
    try model.write(to: modelURL)
    let calibrationObservations = try observations(model: model, examples: calibration)
    let acceptanceObservations = try observations(model: model, examples: acceptance)
    let externalCalibrationObservations = calibrationObservations.filter {
        $0.example.sourceDataset != nil
    }
    let thresholdObservations = externalCalibrationObservations.count >= 40
        ? externalCalibrationObservations
        : calibrationObservations
    let globalThreshold = selectedThreshold(observations: thresholdObservations)
    let languages = Set(calibration.map(\.language)).sorted()
    let thresholdsByLanguage = Dictionary(uniqueKeysWithValues: languages.map { language in
        let externalLanguageObservations = thresholdObservations.filter {
            $0.example.language == language
        }
        let languageObservations = externalLanguageObservations.count >= 15
            ? externalLanguageObservations
            : calibrationObservations.filter {
                $0.example.language == language
            }
        return (
            language,
            selectedThreshold(
                observations: languageObservations
            )
        )
    })
    let finalAcceptanceMetrics = routingMetrics(
        observations: acceptanceObservations,
        confidenceThreshold: globalThreshold.confidenceThreshold,
        minimumMargin: globalThreshold.minimumMargin
    )
    let acceptanceByLanguage: [String: RoutingMetrics] = Dictionary(
        uniqueKeysWithValues: languages.map { language in
            let threshold = thresholdsByLanguage[language] ?? globalThreshold
            return (
                language,
                routingMetrics(
                    observations: acceptanceObservations.filter {
                        $0.example.language == language
                    },
                    confidenceThreshold: threshold.confidenceThreshold,
                    minimumMargin: threshold.minimumMargin
                )
            )
        }
    )
    let gate = gateResult(
        verifier: verifier,
        observations: acceptanceObservations,
        thresholdsByLanguage: thresholdsByLanguage,
        globalThreshold: globalThreshold
    )
    let modelBytes = (
        try fileManager.attributesOfItem(atPath: modelURL.path)[.size] as? NSNumber
    )?.intValue ?? 0
    let report = VerifierReport(
        id: verifier.rawValue,
        labels: verifier.labels,
        modelFile: verifier.modelFile,
        modelBytes: modelBytes,
        trainingCount: trainingTexts.values.reduce(0) { $0 + $1.count },
        calibrationCount: calibration.count,
        thresholdCalibrationCount: thresholdObservations.count,
        acceptanceCount: acceptance.count,
        threshold: globalThreshold,
        thresholdsByLanguage: thresholdsByLanguage,
        calibrationMetrics: globalThreshold.metrics,
        acceptanceMetrics: finalAcceptanceMetrics,
        acceptanceByLanguage: acceptanceByLanguage,
        gate: gate
    )
    let configuration: [String: Any] = [
        "id": verifier.rawValue,
        "modelFile": verifier.modelFile,
        "labels": verifier.labels,
        "confidenceThreshold": globalThreshold.confidenceThreshold,
        "confidenceThresholdsByLanguage": thresholdsByLanguage.mapValues {
            $0.confidenceThreshold
        },
        "minimumMargin": globalThreshold.minimumMargin,
        "minimumMarginsByLanguage": thresholdsByLanguage.mapValues {
            $0.minimumMargin
        },
        "acceptedForAutomaticRouting": gate.accepted,
        "deploymentMode": gate.accepted ? "automatic" : "shadow"
    ]
    return (report, configuration)
}

private func main() throws {
    try fileManager.createDirectory(
        at: outputDirectoryURL,
        withIntermediateDirectories: true
    )
    let baseRecords = try readJSONLines(BaseRecord.self, from: baseCorpusURL)
    let silverURLs = [
        silverDirectoryURL.appendingPathComponent("silver-train.jsonl"),
        silverDirectoryURL.appendingPathComponent("silver-calibration.jsonl"),
        silverDirectoryURL.appendingPathComponent("silver-acceptance.jsonl")
    ]
    let silverRecords = try silverURLs.flatMap {
        try readJSONLines(SilverRecord.self, from: $0)
    }
    var reports: [VerifierReport] = []
    var configurations: [[String: Any]] = []
    for verifier in VerifierID.allCases {
        let (report, configuration) = try train(
            verifier: verifier,
            baseRecords: baseRecords,
            silverRecords: silverRecords
        )
        reports.append(report)
        configurations.append(configuration)
        print(
            "VERIFIER_SELECTED id=\(verifier.rawValue) "
                + "accepted=\(report.gate.accepted) "
                + "precision=\(report.acceptanceMetrics.precision)"
        )
    }

    let generatedAt = ISO8601DateFormatter().string(from: Date())
    let report = TrainingReport(
        generatedAt: generatedAt,
        baseCorpusPath: baseCorpusURL.path,
        silverDirectoryPath: silverDirectoryURL.path,
        selectionPolicy:
            "Thresholds and top-1/top-2 margins are calibrated without acceptance data. "
            + "Automatic routing requires >=95% exact-route precision and >=100 routed "
            + "positives for every specialized label in both English and Simplified Chinese. "
            + "Without human gold, passing values remain consensus-relative.",
        verifiers: reports
    )
    try writeJSON(report, to: reportURL)

    let manifestData = try Data(contentsOf: baseManifestURL)
    guard var manifest = try JSONSerialization.jsonObject(
        with: manifestData
    ) as? [String: Any] else {
        throw NSError(
            domain: "VerifierTraining",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid base manifest"]
        )
    }
    for classifier in manifest["classifiers"] as? [[String: Any]] ?? [] {
        guard let modelFile = classifier["modelFile"] as? String else { continue }
        let source = baseManifestURL.deletingLastPathComponent()
            .appendingPathComponent(modelFile)
        let destination = outputDirectoryURL.appendingPathComponent(modelFile)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
    manifest["schemaVersion"] = 3
    manifest["verifiers"] = configurations
    manifest["verifierGeneratedAt"] = generatedAt
    manifest["verifierLabelPolicy"] = "multi-model-consensus-without-human-gold"
    let outputManifestURL = outputDirectoryURL.appendingPathComponent(
        "clipboard-semantic-models.json"
    )
    let outputManifestData = try JSONSerialization.data(
        withJSONObject: manifest,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try outputManifestData.write(to: outputManifestURL, options: .atomic)
    print("VERIFIER_REPORT \(reportURL.path)")
}

do {
    try main()
} catch {
    fputs("Verifier training failed: \(error)\n", stderr)
    exit(1)
}

#!/usr/bin/env xcrun swift

import CreateML
import Foundation

private struct CorpusRecord: Codable {
    let id: String
    let text: String
    let language: String
    let split: String
    let family: String
    let task: Bool
    let question: Bool
    let invitation: Bool
    let complaint: Bool
    let sentiment: String
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
    let acceptedForAutomaticRouting: Bool
    let validationBinary: BinaryMetrics?
    let testBinary: BinaryMetrics?
    let goldenBinary: BinaryMetrics?
    let testFalsePositiveExamples: [String]?
    let testFalseNegativeExamples: [String]?
    let goldenFalsePositiveExamples: [String]?
    let goldenFalseNegativeExamples: [String]?
    let binaryByLanguage: [String: BinaryMetrics]?
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

private enum ClassifierID: String, CaseIterable {
    case task
    case question
    case invitation
    case complaint
    case sentiment

    var resourceName: String {
        switch self {
        case .task: "TaskIntentClassifier"
        case .question: "QuestionIntentClassifier"
        case .invitation: "InvitationIntentClassifier"
        case .complaint: "ComplaintIntentClassifier"
        case .sentiment: "SentimentClassifier"
        }
    }

    var labels: [String] {
        switch self {
        case .task: ["notTask", "task"]
        case .question: ["notQuestion", "question"]
        case .invitation: ["notInvitation", "invitation"]
        case .complaint: ["notComplaint", "complaint"]
        case .sentiment: ["negative", "neutral", "positive"]
        }
    }

    var positiveLabel: String? {
        switch self {
        case .task: "task"
        case .question: "question"
        case .invitation: "invitation"
        case .complaint: "complaint"
        case .sentiment: nil
        }
    }

    func label(for record: CorpusRecord) -> String {
        switch self {
        case .task: record.task ? "task" : "notTask"
        case .question: record.question ? "question" : "notQuestion"
        case .invitation: record.invitation ? "invitation" : "notInvitation"
        case .complaint: record.complaint ? "complaint" : "notComplaint"
        case .sentiment: record.sentiment
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
private let corpusURL = repositoryRoot
    .appendingPathComponent("ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl")
private let candidateDirectory = repositoryRoot
    .appendingPathComponent("ModelTraining/ClipboardSemantics/Candidates")
private let resourceDirectory = repositoryRoot
    .appendingPathComponent("OSGKeyboardShared/Resources/ClipboardSemantics")
private let reportURL = repositoryRoot
    .appendingPathComponent("ModelTraining/ClipboardSemantics/evaluation-report.json")

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
        let texts = (grouped[label] ?? [])
            .map(\.text)
            .shuffled(using: &generator)
        result[label] = Array(texts.prefix(minimumCount))
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
    scores: [Double],
    expectedPositive: Bool,
    predictedPositive: Bool,
    limit: Int = 12
) -> [String] {
    zip(records, scores).compactMap { record, score -> String? in
        let isExpectedPositive = classifier.label(for: record) == positiveLabel
        let isPredictedPositive = score >= threshold
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
    for integer in 60...99 {
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
    let trainingTexts = balancedTexts(
        records: trainingRecords,
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
        let testScores = try scores(
            classifier: classifier,
            records: testRecords,
            positiveLabel: positiveLabel
        )
        let testMetrics = binaryMetrics(
            records: testRecords,
            classifier: classifierID,
            positiveLabel: positiveLabel,
            threshold: calibration.threshold,
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
            threshold: calibration.threshold,
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
                threshold: calibration.threshold,
                scores: languageScores
            )
        }
        report = CandidateReport(
            algorithm: algorithm.rawValue,
            modelBytes: modelFileSize(at: modelURL),
            runtimeAssetIndependent: algorithm == .maxEnt,
            balancedTrainingCount: totalCount(trainingTexts),
            balancedValidationCount: totalCount(validationTexts),
            threshold: rounded(calibration.threshold),
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
                scores: testScores,
                expectedPositive: false,
                predictedPositive: true
            ),
            testFalseNegativeExamples: binaryErrorExamples(
                records: testRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                scores: testScores,
                expectedPositive: true,
                predictedPositive: false
            ),
            goldenFalsePositiveExamples: binaryErrorExamples(
                records: goldenRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                scores: goldenScores,
                expectedPositive: false,
                predictedPositive: true
            ),
            goldenFalseNegativeExamples: binaryErrorExamples(
                records: goldenRecords,
                classifier: classifierID,
                positiveLabel: positiveLabel,
                threshold: calibration.threshold,
                scores: goldenScores,
                expectedPositive: true,
                predictedPositive: false
            ),
            binaryByLanguage: byLanguage,
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
        return CandidateAlgorithm.allCases
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
    let records = try loadCorpus()
    let trainingRecords = records.filter { $0.split == "train" }
    let validationRecords = records.filter { $0.split == "validation" }
    let testRecords = records.filter { $0.split == "test" }
    let goldenRecords = records.filter { $0.split == "golden" }
    let algorithms = selectedAlgorithms()
    let classifiers = selectedClassifiers()
    precondition(!algorithms.isEmpty, "No supported algorithms requested")
    precondition(!classifiers.isEmpty, "No supported classifiers requested")

    try fileManager.createDirectory(
        at: resourceDirectory,
        withIntermediateDirectories: true
    )
    let generatedAt = ISO8601DateFormatter().string(from: Date())
    var classifierReports: [ClassifierReport] = []
    var manifestClassifiers: [ManifestClassifier] = []

    for classifierID in classifiers {
        var candidates: [TrainedCandidate] = []
        for algorithm in algorithms {
            do {
                candidates.append(
                    try train(
                        classifierID: classifierID,
                        algorithm: algorithm,
                        trainingRecords: trainingRecords,
                        validationRecords: validationRecords,
                        testRecords: testRecords,
                        goldenRecords: goldenRecords
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
        corpusPath: "ModelTraining/ClipboardSemantics/clipboard_semantic_corpus.jsonl",
        corpusCount: records.count,
        trainingCount: trainingRecords.count,
        validationCount: validationRecords.count,
        testCount: testRecords.count,
        goldenCount: goldenRecords.count,
        selectionPolicy:
            "Validation only: binary models require precision >= 0.97, then maximize recall; "
            + "sentiment prioritizes macro-F1. Automatic routing also requires a self-contained "
            + "maxEnt model because BERT embedding assets are not guaranteed in extensions. "
            + "Test and golden data gate deployment but never tune model weights.",
        classifiers: classifierReports
    )
    try writeJSON(report, to: reportURL)
    try writeJSON(
        ModelManifest(
            schemaVersion: 1,
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

#!/usr/bin/env xcrun swift

import CoreML
import Darwin
import Foundation
import NaturalLanguage

private enum BenchmarkError: LocalizedError {
    case invalidArguments(String)
    case invalidManifest(String)
    case invalidCorpus(String)
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message),
             .invalidManifest(let message),
             .invalidCorpus(let message),
             .missingFile(let message):
            return message
        }
    }
}

private struct Arguments {
    let modelDirectory: URL
    let corpus: URL
    let report: URL
    let maximumSamples: Int
    let warmRounds: Int

    static let usage = """
    Usage: benchmark_v6_models.swift \
      --model-directory <directory> \
      --corpus <corpus.jsonl> \
      --report <report.json> \
      [--max-samples <positive integer>] \
      [--warm-rounds <positive integer>]
    """

    static func parse(_ rawArguments: [String]) throws -> Arguments {
        var values: [String: String] = [:]
        var index = 0
        let supportedFlags = Set([
            "--model-directory",
            "--corpus",
            "--report",
            "--max-samples",
            "--warm-rounds"
        ])

        while index < rawArguments.count {
            let flag = rawArguments[index]
            guard supportedFlags.contains(flag) else {
                throw BenchmarkError.invalidArguments("Unknown argument: \(flag)\n\(usage)")
            }
            guard index + 1 < rawArguments.count,
                  !rawArguments[index + 1].hasPrefix("--") else {
                throw BenchmarkError.invalidArguments("Missing value for \(flag)\n\(usage)")
            }
            guard values[flag] == nil else {
                throw BenchmarkError.invalidArguments("Duplicate argument: \(flag)\n\(usage)")
            }
            values[flag] = rawArguments[index + 1]
            index += 2
        }

        let requiredFlags = ["--model-directory", "--corpus", "--report"]
        for flag in requiredFlags where values[flag] == nil {
            throw BenchmarkError.invalidArguments("Missing required argument: \(flag)\n\(usage)")
        }

        let maximumSamples = try positiveInteger(
            values["--max-samples"] ?? "120",
            flag: "--max-samples"
        )
        let warmRounds = try positiveInteger(
            values["--warm-rounds"] ?? "5",
            flag: "--warm-rounds"
        )
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )

        return Arguments(
            modelDirectory: resolvedURL(values["--model-directory"]!, relativeTo: currentDirectory),
            corpus: resolvedURL(values["--corpus"]!, relativeTo: currentDirectory),
            report: resolvedURL(values["--report"]!, relativeTo: currentDirectory),
            maximumSamples: maximumSamples,
            warmRounds: warmRounds
        )
    }

    private static func positiveInteger(_ value: String, flag: String) throws -> Int {
        guard let result = Int(value), result > 0 else {
            throw BenchmarkError.invalidArguments(
                "\(flag) must be a positive integer, received: \(value)"
            )
        }
        return result
    }

    private static func resolvedURL(_ path: String, relativeTo baseURL: URL) -> URL {
        URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }
}

private struct Manifest: Decodable {
    let schemaVersion: Int
    let classifiers: [ManifestClassifier]
}

private struct ManifestClassifier: Decodable {
    let id: String
    let modelFile: String
    let algorithm: String
    let labels: [String]
    let positiveLabel: String?
}

private struct CorpusRecord: Decodable {
    let text: String
    let split: String
}

private struct MemorySnapshot: Encodable {
    let currentRSSBytes: UInt64?
    let peakRSSBytes: UInt64?
}

private struct TimingDistribution: Encodable {
    let rounds: Int
    let samplesPerRound: Int
    let measurementCount: Int
    let averageMilliseconds: Double
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let minimumMilliseconds: Double
    let maximumMilliseconds: Double
}

private struct ModelBenchmark: Encodable {
    let id: String
    let modelFile: String
    let algorithm: String
    let labels: [String]
    let positiveLabel: String?
    let modelBytes: UInt64
    let compiledModelBytes: UInt64
    let compileMilliseconds: Double
    let coldLoadMilliseconds: Double
    let firstPredictionMilliseconds: Double
    let warmPrediction: TimingDistribution
    let predictedLabelCounts: [String: Int]
    let memoryAfterCompile: MemorySnapshot
    let memoryAfterLoad: MemorySnapshot
    let memoryAfterPredictions: MemorySnapshot
}

private struct CorpusSummary: Encodable {
    let path: String
    let eligibleSplits: [String]
    let maximumSamples: Int
    let selectedSamples: Int
    let selectedSamplesBySplit: [String: Int]
    let selectionPolicy: String
}

private struct BenchmarkReport: Encodable {
    let schemaVersion: Int
    let generatedAt: String
    let manifestSchemaVersion: Int
    let modelDirectory: String
    let corpus: CorpusSummary
    let warmRounds: Int
    let clock: String
    let percentileMethod: String
    let memoryAtStart: MemorySnapshot
    let memoryAtEnd: MemorySnapshot
    let models: [ModelBenchmark]
}

private let fileManager = FileManager.default
private let eligibleSplits = Set(["validation", "test", "golden"])

private func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}

private func rounded(_ value: Double, places: Int = 6) -> Double {
    guard value.isFinite else { return 0 }
    let scale = pow(10, Double(places))
    return (value * scale).rounded() / scale
}

private func currentRSSBytes() -> UInt64? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                rebound,
                &count
            )
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    return UInt64(info.resident_size)
}

private func peakRSSBytes() -> UInt64? {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0, usage.ru_maxrss >= 0 else {
        return nil
    }
    // Darwin reports ru_maxrss in bytes; Linux reports KiB.
    #if os(macOS)
    return UInt64(usage.ru_maxrss)
    #else
    return UInt64(usage.ru_maxrss) * 1_024
    #endif
}

private func memorySnapshot() -> MemorySnapshot {
    MemorySnapshot(
        currentRSSBytes: currentRSSBytes(),
        peakRSSBytes: peakRSSBytes()
    )
}

private func validateReadableFile(_ url: URL, description: String) throws {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue,
          fileManager.isReadableFile(atPath: url.path) else {
        throw BenchmarkError.missingFile("\(description) is not a readable file: \(url.path)")
    }
}

private func validateModelDirectory(_ url: URL) throws {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw BenchmarkError.missingFile("Model directory does not exist: \(url.path)")
    }
}

private func modelURL(for modelFile: String, in directory: URL) throws -> URL {
    guard !modelFile.isEmpty else {
        throw BenchmarkError.invalidManifest("Manifest contains an empty modelFile")
    }
    let baseURL = directory.resolvingSymlinksInPath().standardizedFileURL
    let candidateURL = directory
        .appendingPathComponent(modelFile)
        .resolvingSymlinksInPath()
        .standardizedFileURL
    let basePrefix = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
    guard candidateURL.path.hasPrefix(basePrefix) else {
        throw BenchmarkError.invalidManifest(
            "Model file resolves outside --model-directory: \(modelFile)"
        )
    }
    try validateReadableFile(candidateURL, description: "Model")
    return candidateURL
}

private func loadManifest(from modelDirectory: URL) throws -> Manifest {
    let manifestURL = modelDirectory.appendingPathComponent(
        "clipboard-semantic-models.json"
    )
    try validateReadableFile(manifestURL, description: "Manifest")
    let manifest = try JSONDecoder().decode(
        Manifest.self,
        from: Data(contentsOf: manifestURL)
    )
    guard (1...4).contains(manifest.schemaVersion) else {
        throw BenchmarkError.invalidManifest(
            "Unsupported manifest schema \(manifest.schemaVersion); expected 1...4"
        )
    }
    guard !manifest.classifiers.isEmpty else {
        throw BenchmarkError.invalidManifest("Manifest has no classifiers")
    }
    let classifierIDs = manifest.classifiers.map(\.id)
    guard Set(classifierIDs).count == classifierIDs.count else {
        throw BenchmarkError.invalidManifest("Manifest contains duplicate classifier IDs")
    }
    for classifier in manifest.classifiers {
        guard !classifier.id.isEmpty, !classifier.labels.isEmpty else {
            throw BenchmarkError.invalidManifest(
                "Manifest classifier IDs and labels must not be empty"
            )
        }
        if classifier.id == "domain", classifier.positiveLabel != nil {
            throw BenchmarkError.invalidManifest(
                "The multiclass domain classifier must not define positiveLabel"
            )
        }
    }
    return manifest
}

private func loadCorpus(from url: URL, maximumSamples: Int) throws -> [CorpusRecord] {
    try validateReadableFile(url, description: "Corpus")
    let content = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    var records: [CorpusRecord] = []

    for (offset, line) in content.split(separator: "\n").enumerated() {
        let record: CorpusRecord
        do {
            record = try decoder.decode(CorpusRecord.self, from: Data(line.utf8))
        } catch {
            throw BenchmarkError.invalidCorpus(
                "Invalid JSONL record at line \(offset + 1): \(error.localizedDescription)"
            )
        }
        guard eligibleSplits.contains(record.split) else { continue }
        records.append(record)
        if records.count == maximumSamples {
            break
        }
    }

    guard !records.isEmpty else {
        throw BenchmarkError.invalidCorpus(
            "Corpus has no records in validation, test, or golden splits"
        )
    }
    return records
}

private func recursiveSize(of url: URL) throws -> UInt64 {
    let resourceValues = try url.resourceValues(
        forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
    )
    if resourceValues.isRegularFile == true {
        return UInt64(resourceValues.fileSize ?? 0)
    }
    guard resourceValues.isDirectory == true else { return 0 }
    guard let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else {
        return 0
    }

    var total: UInt64 = 0
    for case let childURL as URL in enumerator {
        let childValues = try childURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        if childValues.isRegularFile == true {
            total += UInt64(childValues.fileSize ?? 0)
        }
    }
    return total
}

private func compileModel(sourceURL: URL, outputDirectory: URL) throws -> URL {
    let generatedURL = try MLModel.compileModel(at: sourceURL)
    let destinationURL = outputDirectory
        .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
        .appendingPathExtension("mlmodelc")
    if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.moveItem(at: generatedURL, to: destinationURL)
    return destinationURL
}

private func percentile(_ sortedValues: [Double], fraction: Double) -> Double {
    guard !sortedValues.isEmpty else { return 0 }
    let rank = max(1, Int(ceil(fraction * Double(sortedValues.count))))
    return sortedValues[min(rank - 1, sortedValues.count - 1)]
}

private func timingDistribution(
    values: [Double],
    rounds: Int,
    samplesPerRound: Int
) -> TimingDistribution {
    let sortedValues = values.sorted()
    let average = values.reduce(0, +) / Double(values.count)
    return TimingDistribution(
        rounds: rounds,
        samplesPerRound: samplesPerRound,
        measurementCount: values.count,
        averageMilliseconds: rounded(average),
        p50Milliseconds: rounded(percentile(sortedValues, fraction: 0.50)),
        p95Milliseconds: rounded(percentile(sortedValues, fraction: 0.95)),
        minimumMilliseconds: rounded(sortedValues.first ?? 0),
        maximumMilliseconds: rounded(sortedValues.last ?? 0)
    )
}

private func benchmark(
    classifier: ManifestClassifier,
    modelDirectory: URL,
    temporaryDirectory: URL,
    records: [CorpusRecord],
    warmRounds: Int
) throws -> ModelBenchmark {
    let sourceURL = try modelURL(for: classifier.modelFile, in: modelDirectory)
    let sourceBytes = try recursiveSize(of: sourceURL)

    let compileStartedAt = ContinuousClock.now
    let compiledURL = try compileModel(
        sourceURL: sourceURL,
        outputDirectory: temporaryDirectory
    )
    let compileMilliseconds = milliseconds(compileStartedAt.duration(to: .now))
    let memoryAfterCompile = memorySnapshot()
    let compiledBytes = try recursiveSize(of: compiledURL)

    let loadStartedAt = ContinuousClock.now
    let model = try NLModel(contentsOf: compiledURL)
    let loadMilliseconds = milliseconds(loadStartedAt.duration(to: .now))
    let memoryAfterLoad = memorySnapshot()

    let firstPredictionStartedAt = ContinuousClock.now
    _ = model.predictedLabel(for: records[0].text)
    let firstPredictionMilliseconds = milliseconds(
        firstPredictionStartedAt.duration(to: .now)
    )

    var warmMeasurements: [Double] = []
    warmMeasurements.reserveCapacity(records.count * warmRounds)
    var predictedLabelCounts: [String: Int] = [:]
    for _ in 0..<warmRounds {
        for record in records {
            let predictionStartedAt = ContinuousClock.now
            let predictedLabel = model.predictedLabel(for: record.text) ?? "__noPrediction__"
            warmMeasurements.append(
                milliseconds(predictionStartedAt.duration(to: .now))
            )
            predictedLabelCounts[predictedLabel, default: 0] += 1
        }
    }

    return ModelBenchmark(
        id: classifier.id,
        modelFile: classifier.modelFile,
        algorithm: classifier.algorithm,
        labels: classifier.labels,
        positiveLabel: classifier.positiveLabel,
        modelBytes: sourceBytes,
        compiledModelBytes: compiledBytes,
        compileMilliseconds: rounded(compileMilliseconds),
        coldLoadMilliseconds: rounded(loadMilliseconds),
        firstPredictionMilliseconds: rounded(firstPredictionMilliseconds),
        warmPrediction: timingDistribution(
            values: warmMeasurements,
            rounds: warmRounds,
            samplesPerRound: records.count
        ),
        predictedLabelCounts: predictedLabelCounts,
        memoryAfterCompile: memoryAfterCompile,
        memoryAfterLoad: memoryAfterLoad,
        memoryAfterPredictions: memorySnapshot()
    )
}

private func writeReport(_ report: BenchmarkReport, to url: URL) throws {
    try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(report).write(to: url, options: .atomic)
}

private func formattedMiB(_ bytes: UInt64?) -> String {
    guard let bytes else { return "unavailable" }
    return String(format: "%.1f MiB", Double(bytes) / 1_048_576)
}

private func run() throws {
    let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    try validateModelDirectory(arguments.modelDirectory)
    let manifest = try loadManifest(from: arguments.modelDirectory)
    let records = try loadCorpus(
        from: arguments.corpus,
        maximumSamples: arguments.maximumSamples
    )
    let splitCounts = Dictionary(grouping: records, by: \.split).mapValues(\.count)
    let memoryAtStart = memorySnapshot()

    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
        "osg-v6-model-benchmark-\(UUID().uuidString)",
        isDirectory: true
    )
    try fileManager.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer { try? fileManager.removeItem(at: temporaryDirectory) }

    var modelBenchmarks: [ModelBenchmark] = []
    modelBenchmarks.reserveCapacity(manifest.classifiers.count)
    for classifier in manifest.classifiers {
        modelBenchmarks.append(
            try benchmark(
                classifier: classifier,
                modelDirectory: arguments.modelDirectory,
                temporaryDirectory: temporaryDirectory,
                records: records,
                warmRounds: arguments.warmRounds
            )
        )
    }

    let report = BenchmarkReport(
        schemaVersion: 1,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        manifestSchemaVersion: manifest.schemaVersion,
        modelDirectory: arguments.modelDirectory.path,
        corpus: CorpusSummary(
            path: arguments.corpus.path,
            eligibleSplits: eligibleSplits.sorted(),
            maximumSamples: arguments.maximumSamples,
            selectedSamples: records.count,
            selectedSamplesBySplit: splitCounts,
            selectionPolicy: "first eligible records in corpus order"
        ),
        warmRounds: arguments.warmRounds,
        clock: "ContinuousClock",
        percentileMethod: "nearest-rank",
        memoryAtStart: memoryAtStart,
        memoryAtEnd: memorySnapshot(),
        models: modelBenchmarks
    )
    try writeReport(report, to: arguments.report)

    let totalCompile = modelBenchmarks.reduce(0) { $0 + $1.compileMilliseconds }
    let totalLoad = modelBenchmarks.reduce(0) { $0 + $1.coldLoadMilliseconds }
    let warmAverage = modelBenchmarks.reduce(0) {
        $0 + $1.warmPrediction.averageMilliseconds
    } / Double(modelBenchmarks.count)
    print(
        String(
            format: "V6 benchmark: %d models, %d samples × %d rounds; compile %.3f ms, cold load %.3f ms, warm avg %.3f ms, peak RSS %@; report %@",
            modelBenchmarks.count,
            records.count,
            arguments.warmRounds,
            totalCompile,
            totalLoad,
            warmAverage,
            formattedMiB(report.memoryAtEnd.peakRSSBytes),
            arguments.report.path
        )
    )
}

do {
    try run()
} catch {
    let message = "benchmark_v6_models: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}

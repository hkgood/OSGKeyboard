#!/usr/bin/env swift
//
// prepare_clm.swift
// OSGKeyboard · offline custom language model compiler (macOS 14+)
//
// Takes a SFCustomLanguageModelData .bin and runs:
//   SFSpeechLanguageModel.prepareCustomLanguageModel(...)
//
// Usage:
//   swift Scripts/lexicon/prepare_clm.swift
//   swift Scripts/lexicon/prepare_clm.swift --input path/to/OSGKeyboardCLM.bin
//

import Foundation
import Speech

// MARK: - CLI

struct PrepareOptions {
    var inputBin: URL
    var outputDir: URL
    var clientIdentifier: String
    var weight: Double?

    static func parse() -> PrepareOptions {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        var input = repoRoot.appendingPathComponent(
            "OSGKeyboard/Resources/CustomLanguageModel/v1/OSGKeyboardCLM.bin"
        )
        var output = repoRoot.appendingPathComponent(
            "OSGKeyboard/Resources/CustomLanguageModel/v1/compiled"
        )
        var clientID = "com.osgkeyboard.custom-lm.v1"
        var weight: Double?

        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--input":
                input = URL(fileURLWithPath: iterator.next() ?? "")
            case "--output-dir":
                output = URL(fileURLWithPath: iterator.next() ?? "")
            case "--client-identifier":
                clientID = iterator.next() ?? clientID
            case "--weight":
                weight = Double(iterator.next() ?? "")
            case "-h", "--help":
                printUsage()
                exit(0)
            default:
                fputs("Unknown flag: \(flag)\n", stderr)
                printUsage()
                exit(2)
            }
        }

        return PrepareOptions(
            inputBin: input,
            outputDir: output,
            clientIdentifier: clientID,
            weight: weight
        )
    }

    static func printUsage() {
        print("""
        prepare_clm.swift — compile SFCustomLanguageModelData .bin on macOS

        Options:
          --input <path>              Training .bin (default: OSGKeyboardCLM.bin)
          --output-dir <path>         Directory for compiled LM + Vocab
          --client-identifier <id>    Client identifier (default: com.osgkeyboard.custom-lm.v1)
          --weight <0.0-1.0>          Optional customization weight
          -h, --help                  Show help
        """)
    }
}

// MARK: - Runner

enum PrepareCLM {
    static func run() async throws {
        let options = PrepareOptions.parse()
        let fm = FileManager.default

        guard fm.fileExists(atPath: options.inputBin.path) else {
            throw PrepareError.missingInput(options.inputBin.path)
        }

        try fm.createDirectory(at: options.outputDir, withIntermediateDirectories: true)

        let languageModelURL = options.outputDir.appendingPathComponent("LM")
        let vocabularyURL = options.outputDir.appendingPathComponent("Vocab")

        // Remove stale outputs so prepare always starts clean.
        for url in [languageModelURL, vocabularyURL] {
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }

        let configuration: SFSpeechLanguageModel.Configuration
        if let weight = options.weight {
            configuration = SFSpeechLanguageModel.Configuration(
                languageModel: languageModelURL,
                vocabulary: vocabularyURL,
                weight: NSNumber(value: weight)
            )
        } else {
            configuration = SFSpeechLanguageModel.Configuration(
                languageModel: languageModelURL,
                vocabulary: vocabularyURL
            )
        }

        fputs("Input asset: \(options.inputBin.path)\n", stderr)
        fputs("Output dir:  \(options.outputDir.path)\n", stderr)
        fputs("Client ID:   \(options.clientIdentifier)\n", stderr)

        let inputBytes = (try? fm.attributesOfItem(atPath: options.inputBin.path)[.size] as? NSNumber)?.intValue ?? 0
        fputs("Preparing custom language model (\(inputBytes) byte asset)…\n", stderr)
        fputs("This may take several minutes for large lexicons.\n", stderr)

        let started = Date()
        try await SFSpeechLanguageModel.prepareCustomLanguageModel(
            for: options.inputBin,
            clientIdentifier: options.clientIdentifier,
            configuration: configuration
        )
        let elapsed = Date().timeIntervalSince(started)

        let lmBytes = fileSize(at: languageModelURL)
        let vocabBytes = fileSize(at: vocabularyURL)

        fputs(
            "Done in \(String(format: "%.1f", elapsed))s — LM=\(lmBytes) bytes, Vocab=\(vocabBytes) bytes\n",
            stderr
        )

        let manifestURL = options.outputDir.appendingPathComponent("prepared-manifest.json")
        let manifest: [String: Any] = [
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "client_identifier": options.clientIdentifier,
            "input_bin": options.inputBin.lastPathComponent,
            "input_bin_bytes": inputBytes,
            "language_model": languageModelURL.lastPathComponent,
            "language_model_bytes": lmBytes,
            "vocabulary": vocabularyURL.lastPathComponent,
            "vocabulary_bytes": vocabBytes,
            "prepare_seconds": elapsed,
            "configuration": [
                "language_model": languageModelURL.path,
                "vocabulary": vocabularyURL.path,
                "weight": options.weight as Any,
            ],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: manifestURL)
        fputs("Wrote \(manifestURL.path)\n", stderr)
    }

    private static func fileSize(at url: URL) -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        return (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }
}

enum PrepareError: LocalizedError {
    case missingInput(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let path):
            return "Missing input .bin: \(path)"
        }
    }
}

Task {
    do {
        try await PrepareCLM.run()
        exit(0)
    } catch {
        fputs("prepare_clm failed: \(error)\n", stderr)
        exit(1)
    }
}
dispatchMain()

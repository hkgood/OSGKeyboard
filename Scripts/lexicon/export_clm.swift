#!/usr/bin/env swift
//
// export_clm.swift
// OSGKeyboard · offline SFCustomLanguageModelData exporter (macOS 14+)
//
// Reads the project-curated AI/tech TSV and writes a .bin training asset via
// Speech framework. The normalized four-column TSV beside the binary also
// powers the Mac runtime bias index.
// Usage:
//   swift Scripts/lexicon/export_clm.swift
//   swift Scripts/lexicon/export_clm.swift --max-entries 30000
//

import Foundation
import Speech

// MARK: - CLI

struct CLIOptions {
    var aiTechTSV: URL
    var outputBin: URL
    var localeID: String
    var modelID: String
    var modelVersion: String
    var maxEntries: Int?

    static func parse() -> CLIOptions {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        var aiTech = repoRoot.appendingPathComponent(
            "OSGKeyboard/Resources/CustomLanguageModel/ai-tech-brands/v1/phrases.tsv"
        )
        var output = repoRoot.appendingPathComponent(
            "OSGKeyboard/Resources/CustomLanguageModel/v1/OSGKeyboardCLM.bin"
        )
        var localeID = "zh_CN"
        var modelID = "com.osgkeyboard.custom-lm.v1"
        var modelVersion = "1.0.1"
        var maxEntries: Int?

        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--ai-tech-tsv":
                aiTech = URL(fileURLWithPath: iterator.next() ?? "")
            case "--output":
                output = URL(fileURLWithPath: iterator.next() ?? "")
            case "--locale":
                localeID = iterator.next() ?? localeID
            case "--identifier":
                modelID = iterator.next() ?? modelID
            case "--version":
                modelVersion = iterator.next() ?? modelVersion
            case "--max-entries":
                maxEntries = Int(iterator.next() ?? "")
            case "-h", "--help":
                printUsage()
                exit(0)
            default:
                fputs("Unknown flag: \(flag)\n", stderr)
                printUsage()
                exit(2)
            }
        }

        return CLIOptions(
            aiTechTSV: aiTech,
            outputBin: output,
            localeID: localeID,
            modelID: modelID,
            modelVersion: modelVersion,
            maxEntries: maxEntries
        )
    }

    static func printUsage() {
        print("""
        export_clm.swift — build SFCustomLanguageModelData .bin on macOS

        Options:
          --ai-tech-tsv <path>   Project-curated AI/tech phrases TSV
          --output <path>        Output .bin path
          --locale <id>          Locale identifier (default: zh_CN)
          --identifier <id>      Custom LM identifier
          --version <ver>        Custom LM version string
          --max-entries <n>      Optional cap for smoke tests
          -h, --help             Show help
        """)
    }
}

// MARK: - TSV parsing

struct PhraseEntry: Hashable {
    let phrase: String
    let pinyin: String
    let weight: Int
    let source: String
}

enum TSVLoader {
    static func load(from url: URL, sourceLabel: String) throws -> [PhraseEntry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var entries: [PhraseEntry] = []

        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = String(rawLine)
            if index == 0, line.lowercased().hasPrefix("word\t") {
                continue
            }
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let word = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else {
                continue
            }

            // Formats:
            // normalized: word, pinyin, source, weight
            // ai-tech: word, pinyin, source, category, weight, canonical
            let weight: Int
            if parts.count >= 6, let parsed = Int(parts[4]) {
                weight = parsed
            } else if parts.count >= 4, let parsed = Int(parts[3]) {
                weight = parsed
            } else {
                weight = 1
            }

            let pinyin = parts.count >= 2 ? parts[1] : ""
            let source = parts.count >= 3 ? parts[2] : sourceLabel
            entries.append(
                PhraseEntry(
                    phrase: word,
                    pinyin: pinyin,
                    weight: max(1, weight),
                    source: source
                )
            )
        }

        return entries
    }

    static func merge(_ batches: [[PhraseEntry]]) -> [PhraseEntry] {
        var merged: [String: PhraseEntry] = [:]
        for batch in batches {
            for entry in batch {
                if let current = merged[entry.phrase] {
                    if entry.weight >= current.weight {
                        merged[entry.phrase] = entry
                    }
                } else {
                    merged[entry.phrase] = entry
                }
            }
        }
        return merged.values.sorted {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.phrase < $1.phrase
        }
    }
}

// MARK: - Export

enum ExportCLM {
    static func run() async throws {
        let options = CLIOptions.parse()
        let fm = FileManager.default

        guard fm.fileExists(atPath: options.aiTechTSV.path) else {
            throw ExportError.missingInput(options.aiTechTSV.path)
        }

        fputs("Loading phrases…\n", stderr)
        let aiTech = try TSVLoader.load(from: options.aiTechTSV, sourceLabel: "ai_tech_seed")
        var merged = TSVLoader.merge([aiTech])

        if let cap = options.maxEntries, merged.count > cap {
            merged = Array(merged.prefix(cap))
            fputs("Capped to \(cap) entries (--max-entries)\n", stderr)
        }

        fputs(
            "Loaded \(merged.count) unique project-curated AI/tech phrases\n",
            stderr
        )
        fputs("Locale=\(options.localeID) identifier=\(options.modelID) version=\(options.modelVersion)\n", stderr)

        let locale = Locale(identifier: options.localeID)
        let started = Date()

        fputs("Building SFCustomLanguageModelData…\n", stderr)
        let data = SFCustomLanguageModelData(
            locale: locale,
            identifier: options.modelID,
            version: options.modelVersion
        ) {
            for entry in merged {
                SFCustomLanguageModelData.PhraseCount(
                    phrase: entry.phrase,
                    count: entry.weight
                )
            }
        }

        let outputURL = options.outputBin
        let parent = outputURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let phrasesURL = parent.appendingPathComponent("phrases.tsv")
        let normalizedLines = merged.map { entry in
            "\(entry.phrase)\t\(entry.pinyin)\t\(entry.source)\t\(entry.weight)"
        }
        let normalizedTSV = (["word\tpinyin\tsource\tweight"] + normalizedLines)
            .joined(separator: "\n") + "\n"
        try normalizedTSV.write(to: phrasesURL, atomically: true, encoding: .utf8)
        fputs("Wrote \(phrasesURL.path)\n", stderr)

        fputs("Exporting to \(outputURL.path)…\n", stderr)
        try await data.export(to: outputURL)

        let elapsed = Date().timeIntervalSince(started)
        let bytes = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        fputs(
            "Done in \(String(format: "%.1f", elapsed))s — \(outputURL.lastPathComponent) (\(bytes) bytes)\n",
            stderr
        )

        let manifestURL = parent.appendingPathComponent("compiled-manifest.json")
        let manifest: [String: Any] = [
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "locale": options.localeID,
            "identifier": options.modelID,
            "version": options.modelVersion,
            "phrase_count": merged.count,
            "sources": [
                "ai_tech_seed": aiTech.count,
            ],
            "bin_file": outputURL.lastPathComponent,
            "bin_bytes": bytes,
            "export_seconds": elapsed,
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: manifestURL)
        fputs("Wrote \(manifestURL.path)\n", stderr)

        let sourceManifestURL = parent.appendingPathComponent("manifest.json")
        let sourceManifest: [String: Any] = [
            "version": "v1",
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "locale": "zh-Hans",
            "entry_count": merged.count,
            "sources": [[
                "key": "ai_tech_seed",
                "label": "OSGKeyboard curated AI/tech lexicon",
                "license": "MIT (curated seed; OSGKeyboard contributors)",
                "raw_count": aiTech.count,
            ]],
            "notes": [
                "Project-curated bilingual AI brands, technology terms, companies, and names.",
                "No third-party cell dictionaries or Sogou-derived data.",
                "PhraseCount weights map to SFCustomLanguageModelData relative frequencies.",
            ],
            "files": ["phrases": "phrases.tsv"],
        ]
        let sourceManifestData = try JSONSerialization.data(
            withJSONObject: sourceManifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try sourceManifestData.write(to: sourceManifestURL)
        fputs("Wrote \(sourceManifestURL.path)\n", stderr)
    }
}

enum ExportError: LocalizedError {
    case missingInput(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let path):
            return "Missing input file: \(path)"
        }
    }
}

Task {
    do {
        try await ExportCLM.run()
        exit(0)
    } catch {
        fputs("export_clm failed: \(error)\n", stderr)
        exit(1)
    }
}
dispatchMain()

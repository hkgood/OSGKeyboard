// PolishStyleCorpusExportStore.swift
// OSGKeyboard · Main App
//
// Exports the same paired dictation corpus used by personal style learning.

import Foundation
import OSGKeyboardShared

struct PolishStyleCorpusExport: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let effectiveCharacterCount: Int
    let requiredEffectiveCharacterCount: Int
    /// Maximum effective characters included in this export. Caps the
    /// training-corpus window even when the user has accumulated far
    /// more history than the production 2,500-character unlock gate.
    let trainingExtractionMaximumCharacterCount: Int
    let examples: [Example]

    struct Example: Codable, Equatable {
        let prePolishText: String
        let finalText: String
        let polishStyleID: String?
        let polishStylePrompt: String?
        let wasUserEdited: Bool
        let createdAt: Date
    }
}

@MainActor
final class PolishStyleCorpusExportStore {
    static let shared = PolishStyleCorpusExportStore()

    private let directoryURL: URL?
    private let fileManager: FileManager
    private let now: () -> Date
    private let appVersion: () -> String
    private let appBuild: () -> String

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() },
        appVersion: @escaping () -> String = { AppVersionDisplay.marketingVersion },
        appBuild: @escaping () -> String = { AppVersionDisplay.buildNumber }
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.now = now
        self.appVersion = appVersion
        self.appBuild = appBuild
    }

    func makeExport(from history: SyncedSpeechHistory) -> PolishStyleCorpusExport? {
        let eligibleCorpus = PolishStyleLearningCorpusBuilder.build(from: history)
        guard !eligibleCorpus.examples.isEmpty else { return nil }
        let corpus = PolishStyleLearningCorpusBuilder.trainingWindow(
            from: eligibleCorpus.examples,
            maximumCharacterCount:
                PolishStyleLearningCorpusBuilder
                    .trainingExtractionMaximumCharacterCount
        )

        let examples = corpus.examples
            .map {
                PolishStyleCorpusExport.Example(
                    prePolishText: $0.prePolishText,
                    finalText: $0.finalText,
                    polishStyleID: $0.polishStyleID,
                    polishStylePrompt: $0.polishStylePrompt,
                    wasUserEdited: $0.wasUserEdited,
                    createdAt: $0.createdAt
                )
            }
        return PolishStyleCorpusExport(
            schemaVersion: PolishStyleCorpusExport.currentSchemaVersion,
            generatedAt: now(),
            appVersion: appVersion(),
            appBuild: appBuild(),
            effectiveCharacterCount: corpus.effectiveCharacterCount,
            requiredEffectiveCharacterCount:
                PolishStyleLearningCorpusBuilder.requiredEffectiveCharacterCount,
            trainingExtractionMaximumCharacterCount:
                PolishStyleLearningCorpusBuilder
                    .trainingExtractionMaximumCharacterCount,
            examples: examples
        )
    }

    func makeExportURL(from history: SyncedSpeechHistory) -> URL? {
        guard let directoryURL = resolvedDirectoryURL() else {
            return nil
        }
        let exportURL = exportURL(in: directoryURL)
        guard let export = makeExport(from: history) else {
            try? fileManager.removeItem(at: exportURL)
            return nil
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let jsonData = try encoder.encode(export)
            let archiveData = try SingleFileZIPArchive.makeArchive(
                fileName: "osgkeyboard-personal-style-corpus-v1.json",
                contents: jsonData
            )
            try archiveData.write(to: exportURL, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: exportURL.path
            )
            return exportURL
        } catch {
            return nil
        }
    }

    private func resolvedDirectoryURL() -> URL? {
        if let directoryURL {
            return directoryURL
        }
        return fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("CorpusExports", isDirectory: true)
    }

    private func exportURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(
            "osgkeyboard-personal-style-corpus-v1.zip",
            isDirectory: false
        )
    }
}

private enum SingleFileZIPArchive {
    private enum ArchiveError: Error {
        case fileNameTooLong
        case contentsTooLarge
    }

    private static let localFileHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralDirectorySignature: UInt32 = 0x0201_4B50
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let minimumVersion: UInt16 = 20
    private static let utf8Flag: UInt16 = 0x0800
    private static let storedCompressionMethod: UInt16 = 0
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021

    static func makeArchive(fileName: String, contents: Data) throws -> Data {
        let fileNameData = Data(fileName.utf8)
        guard let fileNameLength = UInt16(exactly: fileNameData.count) else {
            throw ArchiveError.fileNameTooLong
        }
        guard let contentsSize = UInt32(exactly: contents.count) else {
            throw ArchiveError.contentsTooLarge
        }
        let checksum = crc32(contents)

        var archive = Data()
        archive.appendLittleEndian(localFileHeaderSignature)
        archive.appendLittleEndian(minimumVersion)
        archive.appendLittleEndian(utf8Flag)
        archive.appendLittleEndian(storedCompressionMethod)
        archive.appendLittleEndian(dosTime)
        archive.appendLittleEndian(dosDate)
        archive.appendLittleEndian(checksum)
        archive.appendLittleEndian(contentsSize)
        archive.appendLittleEndian(contentsSize)
        archive.appendLittleEndian(fileNameLength)
        archive.appendLittleEndian(UInt16(0))
        archive.append(fileNameData)
        archive.append(contents)

        guard let centralDirectoryOffset = UInt32(exactly: archive.count) else {
            throw ArchiveError.contentsTooLarge
        }
        archive.appendLittleEndian(centralDirectorySignature)
        archive.appendLittleEndian(minimumVersion)
        archive.appendLittleEndian(minimumVersion)
        archive.appendLittleEndian(utf8Flag)
        archive.appendLittleEndian(storedCompressionMethod)
        archive.appendLittleEndian(dosTime)
        archive.appendLittleEndian(dosDate)
        archive.appendLittleEndian(checksum)
        archive.appendLittleEndian(contentsSize)
        archive.appendLittleEndian(contentsSize)
        archive.appendLittleEndian(fileNameLength)
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt32(0))
        archive.appendLittleEndian(UInt32(0))
        archive.append(fileNameData)

        guard let centralDirectorySize = UInt32(
            exactly: archive.count - Int(centralDirectoryOffset)
        ) else {
            throw ArchiveError.contentsTooLarge
        }
        archive.appendLittleEndian(endOfCentralDirectorySignature)
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(1))
        archive.appendLittleEndian(UInt16(1))
        archive.appendLittleEndian(centralDirectorySize)
        archive.appendLittleEndian(centralDirectoryOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.reduce(UInt32.max) { checksum, byte in
            let tableIndex = Int((checksum ^ UInt32(byte)) & 0xFF)
            return crc32Table[tableIndex] ^ (checksum >> 8)
        } ^ UInt32.max
    }

    private static let crc32Table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in
            (value & 1) == 1
                ? 0xEDB8_8320 ^ (value >> 1)
                : value >> 1
        }
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }
}

// PolishStyleCorpusExportStoreTests.swift
// OSGKeyboardTests

import Foundation
@testable import OSGKeyboard
import OSGKeyboardShared
import XCTest

@MainActor
final class PolishStyleCorpusExportStoreTests: XCTestCase {
    func testExportKeepsEligiblePairsAndTrainingMetadata() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let prompt = "# Role\nBe concise\n# Style Boundaries\nKeep meaning\n# Examples\nA → B"
        let fingerprint = SyncedSpeechHistory.polishStylePromptFingerprint(for: prompt)
        let eligible = SpeechHistoryEntry(
            text: "你好，世界。",
            prePolishText: "你好 世界",
            polishStyleID: "user.concise",
            polishStylePromptFingerprint: fingerprint,
            createdAt: createdAt,
            modifiedAt: createdAt.addingTimeInterval(60),
            revision: 1
        )
        let translated = SpeechHistoryEntry(
            text: "Hello",
            prePolishText: "你好",
            wasTranslation: true
        )
        let history = SyncedSpeechHistory(
            entries: [translated, eligible],
            polishStylePromptSnapshots: [fingerprint: prompt]
        )
        let store = PolishStyleCorpusExportStore(
            directoryURL: temporaryDirectory(),
            now: { generatedAt },
            appVersion: { "2.0.3" },
            appBuild: { "94" }
        )

        let export = try XCTUnwrap(store.makeExport(from: history))

        XCTAssertEqual(export.schemaVersion, 1)
        XCTAssertEqual(export.generatedAt, generatedAt)
        XCTAssertEqual(export.appVersion, "2.0.3")
        XCTAssertEqual(export.appBuild, "94")
        XCTAssertEqual(export.effectiveCharacterCount, 4)
        XCTAssertEqual(export.requiredEffectiveCharacterCount, 2_500)
        XCTAssertEqual(export.examples.count, 1)
        XCTAssertEqual(export.examples[0].prePolishText, "你好 世界")
        XCTAssertEqual(export.examples[0].finalText, "你好，世界。")
        XCTAssertEqual(export.examples[0].polishStyleID, "user.concise")
        XCTAssertEqual(export.examples[0].polishStylePrompt, prompt)
        XCTAssertTrue(export.examples[0].wasUserEdited)
        XCTAssertEqual(export.examples[0].createdAt, createdAt)
    }

    func testJSONUsesISO8601AndOmitsSyncMetadata() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let deletedID = UUID()
        let history = SyncedSpeechHistory(
            entries: [
                SpeechHistoryEntry(
                    text: "Final text",
                    prePolishText: "Raw text",
                    createdAt: createdAt
                )
            ],
            deletedEntryIDs: [deletedID: createdAt],
            appliedMutationIDs: [UUID()],
            clearedAt: createdAt.addingTimeInterval(-60)
        )
        let store = PolishStyleCorpusExportStore(
            directoryURL: directory,
            now: { createdAt },
            appVersion: { "2.0.3" },
            appBuild: { "94" }
        )

        let exportURL = try XCTUnwrap(store.makeExportURL(from: history))
        let archived = try extractStoredFile(from: exportURL)
        let json = try XCTUnwrap(String(data: archived.contents, encoding: .utf8))

        XCTAssertEqual(exportURL.pathExtension, "zip")
        XCTAssertEqual(
            archived.fileName,
            "osgkeyboard-personal-style-corpus-v1.json"
        )
        XCTAssertTrue(json.contains(#""schemaVersion" : 1"#))
        XCTAssertTrue(json.contains("2023-11-14T22:13:20Z"))
        XCTAssertFalse(json.contains("deletedEntryIDs"))
        XCTAssertFalse(json.contains("appliedMutationIDs"))
        XCTAssertFalse(json.contains("clearedAt"))
        XCTAssertFalse(json.contains(deletedID.uuidString))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            PolishStyleCorpusExport.self,
            from: archived.contents
        )
        XCTAssertEqual(decoded.examples.count, 1)
    }

    func testExportUsesNewestCompleteExamplesThroughThreshold() throws {
        let history = SyncedSpeechHistory(
            entries: [
                SpeechHistoryEntry(
                    text: "oldest",
                    prePolishText: String(repeating: "旧", count: 1_000),
                    createdAt: Date(timeIntervalSince1970: 1)
                ),
                SpeechHistoryEntry(
                    text: "middle-complete",
                    prePolishText: String(repeating: "中", count: 1_600),
                    createdAt: Date(timeIntervalSince1970: 2)
                ),
                SpeechHistoryEntry(
                    text: "newest-complete",
                    prePolishText: String(repeating: "新", count: 1_000),
                    createdAt: Date(timeIntervalSince1970: 3)
                )
            ]
        )

        let export = try XCTUnwrap(
            PolishStyleCorpusExportStore(
                directoryURL: temporaryDirectory()
            ).makeExport(from: history)
        )

        XCTAssertEqual(export.effectiveCharacterCount, 2_600)
        XCTAssertEqual(
            export.examples.map(\.finalText),
            ["middle-complete", "newest-complete"]
        )
        XCTAssertEqual(export.examples[0].prePolishText.count, 1_600)
        XCTAssertEqual(export.examples[1].prePolishText.count, 1_000)
    }

    func testEmptyCorpusRemovesPreviousExport() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PolishStyleCorpusExportStore(directoryURL: directory)
        let populated = SyncedSpeechHistory(
            entries: [
                SpeechHistoryEntry(text: "Final", prePolishText: "Raw")
            ]
        )
        let exportURL = try XCTUnwrap(store.makeExportURL(from: populated))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

        XCTAssertNil(store.makeExportURL(from: .empty))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "PolishStyleCorpusExportStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func extractStoredFile(
        from archiveURL: URL
    ) throws -> (fileName: String, contents: Data) {
        let archive = try Data(contentsOf: archiveURL)
        XCTAssertEqual(littleEndianUInt32(in: archive, at: 0), 0x0403_4B50)
        XCTAssertEqual(littleEndianUInt16(in: archive, at: 8), 0)
        XCTAssertNotNil(archive.range(of: Data([0x50, 0x4B, 0x01, 0x02])))
        XCTAssertNotNil(archive.range(of: Data([0x50, 0x4B, 0x05, 0x06])))

        let expectedChecksum = littleEndianUInt32(in: archive, at: 14)
        let contentsSize = Int(littleEndianUInt32(in: archive, at: 18))
        let fileNameLength = Int(littleEndianUInt16(in: archive, at: 26))
        let extraLength = Int(littleEndianUInt16(in: archive, at: 28))
        let fileNameStart = 30
        let fileNameEnd = fileNameStart + fileNameLength
        let contentsStart = fileNameEnd + extraLength
        let contentsEnd = contentsStart + contentsSize

        let fileName = try XCTUnwrap(
            String(
                data: archive.subdata(in: fileNameStart..<fileNameEnd),
                encoding: .utf8
            )
        )
        let contents = archive.subdata(in: contentsStart..<contentsEnd)
        XCTAssertEqual(crc32(contents), expectedChecksum)
        return (
            fileName,
            contents
        )
    }

    private func littleEndianUInt16(in data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }

    private func littleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func crc32(_ data: Data) -> UInt32 {
        data.reduce(UInt32.max) { checksum, byte in
            var value = checksum ^ UInt32(byte)
            for _ in 0..<8 {
                value = (value & 1) == 1
                    ? 0xEDB8_8320 ^ (value >> 1)
                    : value >> 1
            }
            return value
        } ^ UInt32.max
    }
}

final class AppDistributionChannelTests: XCTestCase {
    func testDebugBuildAllowsInternalToolsWithoutReceipt() {
        XCTAssertTrue(
            AppDistributionChannel.allowsInternalTools(
                isDebugBuild: true,
                receiptURL: nil
            )
        )
    }

    func testTestFlightReceiptAllowsInternalToolsInReleaseBuild() {
        XCTAssertTrue(
            AppDistributionChannel.allowsInternalTools(
                isDebugBuild: false,
                receiptURL: URL(fileURLWithPath: "/StoreKit/sandboxReceipt")
            )
        )
    }

    func testProductionOrMissingReceiptHidesInternalToolsInReleaseBuild() {
        XCTAssertFalse(
            AppDistributionChannel.allowsInternalTools(
                isDebugBuild: false,
                receiptURL: URL(fileURLWithPath: "/StoreKit/receipt")
            )
        )
        XCTAssertFalse(
            AppDistributionChannel.allowsInternalTools(
                isDebugBuild: false,
                receiptURL: nil
            )
        )
    }
}

// FlowFailureLogStoreTests.swift
// OSGKeyboardTests

import Foundation
@testable import OSGKeyboard
import XCTest

final class FlowFailureLogStoreTests: XCTestCase {
    func testFailureReportKeepsOnlyTenSecondsAndRedactsSensitiveMetadata() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableFailureLogClock(
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = FlowFailureLogStore(
            directoryURL: directory,
            now: { clock.current }
        )

        store.record("event=tooOld")
        clock.advance(by: 11)
        store.record(
            "event=current sessionId=550e8400-e29b-41d4-a716-446655440000 "
                + "access_token=secret container=/private/var/mobile/Containers/example"
        )

        let url = try XCTUnwrap(
            store.persistStartupFailure(
                reason: "timedOut",
                context: ["authorization": "bearer=secret"]
            )
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(
            FlowStartupFailureReport.self,
            from: Data(contentsOf: url)
        )

        XCTAssertEqual(report.reason, "timedOut")
        XCTAssertEqual(report.events.count, 1)
        XCTAssertFalse(report.events[0].message.contains("tooOld"))
        XCTAssertFalse(report.events[0].message.contains("550e8400"))
        XCTAssertFalse(report.events[0].message.contains("secret"))
        XCTAssertFalse(report.events[0].message.contains("/private/var/mobile"))
        XCTAssertEqual(report.events[0].message.components(separatedBy: "<uuid>").count, 2)
    }

    func testReportRetentionKeepsNewestFilesWithinCountLimit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableFailureLogClock(
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = FlowFailureLogStore(
            directoryURL: directory,
            maxReportCount: 2,
            now: { clock.current }
        )

        for index in 0..<3 {
            store.record("event=failure\(index)")
            XCTAssertNotNil(
                store.persistStartupFailure(
                    reason: "timedOut",
                    context: ["index": "\(index)"]
                )
            )
            clock.advance(by: 1)
        }

        XCTAssertEqual(store.reportURLs().count, 2)
    }

    func testExportCombinesReportsAndClearRemovesAllFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FlowFailureLogStore(directoryURL: directory)
        store.record("event=failure")
        XCTAssertNotNil(
            store.persistStartupFailure(
                reason: "notPossible",
                context: [:]
            )
        )

        let exportURL = try XCTUnwrap(store.makeExportURL())
        let exportText = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exportText.contains("\"reports\""))
        XCTAssertTrue(exportText.contains("\"notPossible\""))

        store.deleteAllReports()
        XCTAssertTrue(store.reportURLs().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "FlowFailureLogStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private final class MutableFailureLogClock: @unchecked Sendable {
    private let lock: NSLock
    private var value: Date

    init(_ date: Date) {
        value = date
        lock = NSLock()
    }

    var current: Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

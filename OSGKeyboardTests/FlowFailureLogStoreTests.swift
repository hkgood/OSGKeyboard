// FlowFailureLogStoreTests.swift
// OSGKeyboardTests

import Foundation
import OSGKeyboardShared
@testable import OSGKeyboard
import XCTest

final class FlowFailureLogStoreTests: XCTestCase {
    func testFailureReportKeepsRetentionWindowAndRedactsSensitiveMetadata() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableFailureLogClock(
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = makeStore(directory: directory, clock: clock)

        store.record("event=tooOld")
        clock.advance(by: FlowFailureLogStore.retentionWindow + 1)
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
        let report = try decodeReport(at: url)

        XCTAssertEqual(report.reason, "timedOut")
        XCTAssertEqual(report.events.count, 1)
        XCTAssertFalse(report.events[0].message.contains("tooOld"))
        XCTAssertFalse(report.events[0].message.contains("550e8400"))
        XCTAssertFalse(report.events[0].message.contains("secret"))
        XCTAssertFalse(report.events[0].message.contains("/private/var/mobile"))
        XCTAssertEqual(report.events[0].message.components(separatedBy: "<uuid>").count, 2)
    }

    /// A cold-start handoff spans app launch, URL routing, permission checks,
    /// the host's 5 s PiP budget and the keyboard's 8 s start budget. The old
    /// 10 s window pruned away exactly the events that explain the failure.
    func testRetentionWindowCoversAFullColdStartHandoff() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableFailureLogClock(
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = makeStore(directory: directory, clock: clock)

        store.record("event=startSession.request")
        clock.advance(by: 14)
        store.record("event=startWatchdog.timeout")

        let url = try XCTUnwrap(
            store.persistStartupFailure(reason: "startTimeout", context: [:])
        )
        let report = try decodeReport(at: url)

        XCTAssertEqual(report.events.count, 2)
        XCTAssertTrue(report.events[0].message.contains("startSession.request"))
    }

    func testEventWindowIsCappedByCount() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = makeStore(directory: directory)
        for index in 0..<(FlowFailureLogStore.maxEventCount + 50) {
            store.record("event=noise\(index)")
        }

        let url = try XCTUnwrap(
            store.persistStartupFailure(reason: "timedOut", context: [:])
        )
        let report = try decodeReport(at: url)

        XCTAssertEqual(report.events.count, FlowFailureLogStore.maxEventCount)
        // Oldest events are dropped first; the failure itself is the newest.
        XCTAssertTrue(report.events.last?.message.contains("noise449") == true)
    }

    /// The keyboard extension is the only process still alive when the host was
    /// never launched, so its reports must be tagged and must survive alongside
    /// the host's in one directory.
    func testHostAndKeyboardReportsShareOneDirectoryAndStayTagged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let hostStore = makeStore(directory: directory, process: .host)
        let keyboardStore = makeStore(directory: directory, process: .keyboard)

        hostStore.record("event=pipRecovery.deferred")
        XCTAssertNotNil(
            hostStore.persistStartupFailure(reason: "notPossible", context: [:])
        )
        keyboardStore.record("event=startWatchdog.timeout")
        XCTAssertNotNil(
            keyboardStore.persistStartupFailure(reason: "startTimeout", context: [:])
        )

        let reports = keyboardStore.reports()
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(Set(reports.map(\.process)), [.host, .keyboard])
        let keyboardReport = try XCTUnwrap(reports.first { $0.process == .keyboard })
        XCTAssertEqual(keyboardReport.reason, "startTimeout")
        XCTAssertTrue(
            keyboardReport.events.contains { $0.message.contains("startWatchdog.timeout") }
        )
    }

    /// Reports written while the App Group container was unavailable land in the
    /// process-local directory; listing and export must still find them.
    func testReportsInFallbackDirectoryAreListedAndExported() throws {
        let primary = temporaryDirectory()
        let fallback = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: primary)
            try? FileManager.default.removeItem(at: fallback)
        }

        let degradedStore = FlowFailureLogStore(
            directoryURL: fallback,
            additionalReadDirectoryURLs: [],
            process: .host
        )
        degradedStore.record("event=appGroupUnavailable")
        XCTAssertNotNil(
            degradedStore.persistStartupFailure(
                reason: "appGroupUnavailable",
                context: [:]
            )
        )

        let recoveredStore = FlowFailureLogStore(
            directoryURL: primary,
            additionalReadDirectoryURLs: [fallback],
            process: .host
        )
        XCTAssertEqual(recoveredStore.reportURLs().count, 1)

        let exportURL = try XCTUnwrap(recoveredStore.makeExportURL())
        let exportText = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exportText.contains("\"appGroupUnavailable\""))
    }

    /// Schema v1 reports predate `process`; they must stay exportable.
    func testLegacySchemaV1ReportDecodesAsHostReport() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let legacy = """
        {
          "appVersion": "1.0",
          "buildNumber": "1",
          "capturedAt": "2024-01-01T00:00:00Z",
          "context": {},
          "events": [],
          "operatingSystem": "iOS 18.0",
          "reason": "timedOut",
          "reportID": "550E8400-E29B-41D4-A716-446655440000",
          "schemaVersion": 1,
          "windowStartedAt": "2024-01-01T00:00:00Z"
        }
        """
        try Data(legacy.utf8).write(
            to: directory.appendingPathComponent(
                "flow-start-failure-2024-01-01T00-00-00Z-legacy.json"
            )
        )

        let store = makeStore(directory: directory)
        let report = try XCTUnwrap(store.reports().first)
        XCTAssertEqual(report.process, .host)
        XCTAssertEqual(report.reason, "timedOut")
    }

    func testReportRetentionKeepsNewestFilesWithinCountLimit() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = MutableFailureLogClock(
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = FlowFailureLogStore(
            directoryURL: directory,
            additionalReadDirectoryURLs: [],
            process: .host,
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

        let store = makeStore(directory: directory)
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

    // MARK: - Helpers

    private func makeStore(
        directory: URL,
        process: FlowDiagnosticsProcess = .host,
        clock: MutableFailureLogClock? = nil
    ) -> FlowFailureLogStore {
        FlowFailureLogStore(
            directoryURL: directory,
            // Never fall back to the real Application Support directory in tests.
            additionalReadDirectoryURLs: [],
            process: process,
            now: clock.map { clock in { clock.current } } ?? Date.init
        )
    }

    private func decodeReport(at url: URL) throws -> FlowStartupFailureReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            FlowStartupFailureReport.self,
            from: Data(contentsOf: url)
        )
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

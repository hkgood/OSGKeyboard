// FlowFailureLogStore.swift
// OSGKeyboard · Shared
//
// Keeps a rolling in-memory Flow breadcrumb window and writes it whenever a
// session start reaches a terminal failure. Lives in the shared framework so
// BOTH processes record: the host app owns the PiP/audio start path, but the
// keyboard extension is the process that actually observes "the session never
// came up" (start watchdog timeout, host-open rejected, host disconnected) —
// and it is the only one still alive when the host was never launched at all.
//
// Reports are written into the App Group container so a single export in
// Settings shows both sides of the handoff on one timeline. Reports contain
// operational state, never audio, transcripts, clipboard contents, prompts,
// or credentials.

import Foundation

/// Which process produced a breadcrumb window.
public enum FlowDiagnosticsProcess: String, Codable, Sendable {
    case host
    case keyboard

    /// Keyboard extensions carry an `NSExtension` Info.plist entry; the
    /// containing app does not.
    public static var current: FlowDiagnosticsProcess {
        Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil ? .keyboard : .host
    }
}

public struct FlowFailureLogEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let message: String

    public init(timestamp: Date, message: String) {
        self.timestamp = timestamp
        self.message = message
    }
}

public struct FlowStartupFailureReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportID: UUID
    public let process: FlowDiagnosticsProcess
    public let capturedAt: Date
    public let windowStartedAt: Date
    public let reason: String
    public let context: [String: String]
    public let appVersion: String
    public let buildNumber: String
    public let operatingSystem: String
    public let events: [FlowFailureLogEvent]
}

extension FlowStartupFailureReport {
    /// Schema v1 reports predate `process` and were always written by the host.
    /// Decoding them leniently keeps older on-device reports exportable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        reportID = try container.decode(UUID.self, forKey: .reportID)
        process = try container.decodeIfPresent(
            FlowDiagnosticsProcess.self,
            forKey: .process
        ) ?? .host
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        windowStartedAt = try container.decode(Date.self, forKey: .windowStartedAt)
        reason = try container.decode(String.self, forKey: .reason)
        context = try container.decode([String: String].self, forKey: .context)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(String.self, forKey: .buildNumber)
        operatingSystem = try container.decode(String.self, forKey: .operatingSystem)
        events = try container.decode([FlowFailureLogEvent].self, forKey: .events)
    }
}

private struct FlowStartupFailureExport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let reports: [FlowStartupFailureReport]
}

public final class FlowFailureLogStore: @unchecked Sendable {
    public static let shared = FlowFailureLogStore()

    public static let schemaVersion = 2

    /// Breadcrumb window. A cold-start handoff spans app launch → URL routing →
    /// permission checks → PiP recovery (5 s budget) → the keyboard's 8 s start
    /// budget, so the previous 10 s window routinely pruned away the very
    /// events that explain the failure.
    public static let retentionWindow: TimeInterval = 60

    /// Hard cap so a chatty session cannot grow the window without bound.
    public static let maxEventCount = 400

    private let directoryURL: URL
    private let additionalReadDirectoryURLs: [URL]
    private let process: FlowDiagnosticsProcess
    private let maxReportCount: Int
    private let maxReportAge: TimeInterval
    private let maxTotalBytes: Int
    private let now: () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()
    private var events: [FlowFailureLogEvent] = []
    private var lastPersistedAt: Date?

    public init(
        directoryURL: URL = FlowFailureLogStore.defaultDirectoryURL(),
        additionalReadDirectoryURLs: [URL] = FlowFailureLogStore.fallbackDirectoryURLs(),
        process: FlowDiagnosticsProcess = .current,
        maxReportCount: Int = 40,
        maxReportAge: TimeInterval = 14 * 24 * 60 * 60,
        maxTotalBytes: Int = 4 * 1_024 * 1_024,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.additionalReadDirectoryURLs = additionalReadDirectoryURLs
            .filter { $0.standardizedFileURL != directoryURL.standardizedFileURL }
        self.process = process
        self.maxReportCount = maxReportCount
        self.maxReportAge = maxReportAge
        self.maxTotalBytes = maxTotalBytes
        self.now = now
        self.fileManager = fileManager
    }

    public func record(_ message: String) {
        let timestamp = now()
        let event = FlowFailureLogEvent(
            timestamp: timestamp,
            message: Self.redact(message)
        )
        lock.withLock {
            events.append(event)
            pruneEvents(referenceDate: timestamp)
        }
    }

    /// When this process last wrote a report. Lets a catch-all capture path
    /// tell "nobody recorded this incident" from "a better-labelled report for
    /// the same incident just landed".
    public func lastReportPersistedAt() -> Date? {
        lock.withLock { lastPersistedAt }
    }

    /// Breadcrumbs currently inside the retention window. Exposed for tests and
    /// for callers that want to attach the window to another transport.
    public func breadcrumbs() -> [FlowFailureLogEvent] {
        lock.withLock {
            pruneEvents(referenceDate: now())
            return events
        }
    }

    @discardableResult
    public func persistStartupFailure(
        reason: String,
        context: [String: String]
    ) -> URL? {
        let capturedAt = now()
        let capturedEvents = lock.withLock { () -> [FlowFailureLogEvent] in
            pruneEvents(referenceDate: capturedAt)
            return events
        }
        let report = FlowStartupFailureReport(
            schemaVersion: Self.schemaVersion,
            reportID: UUID(),
            process: process,
            capturedAt: capturedAt,
            windowStartedAt: capturedEvents.first?.timestamp ?? capturedAt,
            reason: Self.redact(reason),
            context: context.mapValues(Self.redact),
            appVersion: Self.bundleValue("CFBundleShortVersionString"),
            buildNumber: Self.bundleValue("CFBundleVersion"),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            events: capturedEvents
        )

        do {
            try prepareDirectory(directoryURL)
            let fileURL = directoryURL.appendingPathComponent(
                Self.reportFilename(date: capturedAt, process: process, id: report.reportID),
                isDirectory: false
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(report).write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [
                    // The keyboard extension can hit a terminal start failure on
                    // a locked screen; `completeUntilFirstUserAuthentication`
                    // keeps that write from failing.
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                    .modificationDate: capturedAt
                ],
                ofItemAtPath: fileURL.path
            )
            pruneReports(referenceDate: capturedAt)
            lock.withLock { lastPersistedAt = capturedAt }
            return fileURL
        } catch {
            return nil
        }
    }

    public func reportURLs() -> [URL] {
        reportFileURLs().sorted { lhs, rhs in
            modificationDate(for: lhs) > modificationDate(for: rhs)
        }
    }

    public func reports() -> [FlowStartupFailureReport] {
        reportsWithURLs().map(\.report)
    }

    /// Reports paired with the file each was decoded from, newest first.
    ///
    /// Anything that acts on individual reports — the diagnostics uploader
    /// marking one as sent, for example — needs this pairing: `reports()` drops
    /// files it cannot decode, so zipping its result with `reportURLs()` would
    /// silently attribute a report to the wrong file after one corrupt write.
    public func reportsWithURLs() -> [(url: URL, report: FlowStartupFailureReport)] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return reportURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let report = try? decoder.decode(FlowStartupFailureReport.self, from: data)
            else {
                return nil
            }
            return (url, report)
        }
    }

    public func makeExportURL() -> URL? {
        // Host and keyboard reports interleave on one timeline: sort oldest
        // first so a handoff failure reads top-to-bottom across processes.
        let reports = reports().sorted { $0.capturedAt < $1.capturedAt }
        guard !reports.isEmpty else { return nil }

        let export = FlowStartupFailureExport(
            schemaVersion: Self.schemaVersion,
            generatedAt: now(),
            reports: reports
        )
        do {
            try prepareDirectory(directoryURL)
            let exportURL = directoryURL.appendingPathComponent(
                "flow-startup-diagnostics-export.json",
                isDirectory: false
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(export).write(to: exportURL, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: exportURL.path
            )
            return exportURL
        } catch {
            return nil
        }
    }

    public func deleteAllReports() {
        for url in reportFileURLs() {
            try? fileManager.removeItem(at: url)
        }
        for directory in [directoryURL] + additionalReadDirectoryURLs {
            try? fileManager.removeItem(
                at: directory.appendingPathComponent(
                    "flow-startup-diagnostics-export.json",
                    isDirectory: false
                )
            )
        }
    }

    private func pruneEvents(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-Self.retentionWindow)
        events.removeAll { $0.timestamp < cutoff }
        if events.count > Self.maxEventCount {
            events.removeFirst(events.count - Self.maxEventCount)
        }
    }

    private func prepareDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func pruneReports(referenceDate: Date) {
        let sorted = reportURLs()
        var retainedBytes = 0

        for (index, url) in sorted.enumerated() {
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            let fileSize = values?.fileSize ?? 0
            let isExpired = referenceDate.timeIntervalSince(modifiedAt) > maxReportAge
            let exceedsCount = index >= maxReportCount
            let exceedsSize = retainedBytes + fileSize > maxTotalBytes

            if isExpired || exceedsCount || exceedsSize {
                try? fileManager.removeItem(at: url)
            } else {
                retainedBytes += fileSize
            }
        }
    }

    private func reportFileURLs() -> [URL] {
        ([directoryURL] + additionalReadDirectoryURLs).flatMap { directory -> [URL] in
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return urls.filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent.hasPrefix("flow-start-failure-")
            }
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate) ?? .distantPast
    }

    /// App Group container when available, so the host app and the keyboard
    /// extension append to the same directory. Falls back to the process's own
    /// Application Support directory — the `appGroupUnavailable` failure is
    /// precisely the case where the shared container cannot be opened, and that
    /// report must still land somewhere.
    public static func defaultDirectoryURL() -> URL {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) {
            return container.appendingPathComponent("FlowDiagnostics", isDirectory: true)
        }
        return localDirectoryURL()
    }

    /// Extra directories consulted when listing/exporting. Keeps reports written
    /// during an App Group outage visible once the container comes back.
    public static func fallbackDirectoryURLs() -> [URL] {
        [localDirectoryURL()]
    }

    private static func localDirectoryURL() -> URL {
        let baseURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("FlowDiagnostics", isDirectory: true)
    }

    private static func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    private static func reportFilename(
        date: Date,
        process: FlowDiagnosticsProcess,
        id: UUID
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "flow-start-failure-\(process.rawValue)-\(timestamp)-\(id.uuidString.lowercased()).json"
    }

    private static func redact(_ value: String) -> String {
        var redacted = value.replacingOccurrences(
            of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}"#,
            with: "<uuid>",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"/private/var/mobile/Containers/\S+"#,
            with: "<container-path>",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)(api[_-]?key|authorization|bearer|access[_-]?token|refresh[_-]?token)=\S+"#,
            with: "$1=<redacted>",
            options: .regularExpression
        )
        return redacted
    }
}

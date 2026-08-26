// FlowFailureLogStore.swift
// OSGKeyboard · Main App
//
// Keeps a short in-memory Flow breadcrumb window and writes it only when a
// session start reaches a terminal failure. Reports contain operational state,
// never audio, transcripts, clipboard contents, prompts, or credentials.

import Foundation

struct FlowFailureLogEvent: Codable, Equatable, Sendable {
    let timestamp: Date
    let message: String
}

struct FlowStartupFailureReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let reportID: UUID
    let capturedAt: Date
    let windowStartedAt: Date
    let reason: String
    let context: [String: String]
    let appVersion: String
    let buildNumber: String
    let operatingSystem: String
    let events: [FlowFailureLogEvent]
}

private struct FlowStartupFailureExport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let reports: [FlowStartupFailureReport]
}

final class FlowFailureLogStore: @unchecked Sendable {
    static let shared = FlowFailureLogStore()

    static let retentionWindow: TimeInterval = 10

    private let directoryURL: URL
    private let maxReportCount: Int
    private let maxReportAge: TimeInterval
    private let maxTotalBytes: Int
    private let now: () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()
    private var events: [FlowFailureLogEvent] = []

    init(
        directoryURL: URL = FlowFailureLogStore.defaultDirectoryURL(),
        maxReportCount: Int = 20,
        maxReportAge: TimeInterval = 14 * 24 * 60 * 60,
        maxTotalBytes: Int = 2 * 1_024 * 1_024,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.maxReportCount = maxReportCount
        self.maxReportAge = maxReportAge
        self.maxTotalBytes = maxTotalBytes
        self.now = now
        self.fileManager = fileManager
    }

    func record(_ message: String) {
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

    @discardableResult
    func persistStartupFailure(
        reason: String,
        context: [String: String]
    ) -> URL? {
        let capturedAt = now()
        let capturedEvents = lock.withLock {
            pruneEvents(referenceDate: capturedAt)
            return events
        }
        let report = FlowStartupFailureReport(
            schemaVersion: 1,
            reportID: UUID(),
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
            try prepareDirectory()
            let fileURL = directoryURL.appendingPathComponent(
                Self.reportFilename(date: capturedAt, id: report.reportID),
                isDirectory: false
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(report).write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                    .modificationDate: capturedAt
                ],
                ofItemAtPath: fileURL.path
            )
            pruneReports(referenceDate: capturedAt)
            return fileURL
        } catch {
            return nil
        }
    }

    func reportURLs() -> [URL] {
        reportFileURLs().sorted { lhs, rhs in
            modificationDate(for: lhs) > modificationDate(for: rhs)
        }
    }

    func makeExportURL() -> URL? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reports = reportURLs().compactMap { url -> FlowStartupFailureReport? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(FlowStartupFailureReport.self, from: data)
        }
        guard !reports.isEmpty else { return nil }

        let export = FlowStartupFailureExport(
            schemaVersion: 1,
            generatedAt: now(),
            reports: reports
        )
        do {
            try prepareDirectory()
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

    func deleteAllReports() {
        for url in reportFileURLs() {
            try? fileManager.removeItem(at: url)
        }
        try? fileManager.removeItem(
            at: directoryURL.appendingPathComponent(
                "flow-startup-diagnostics-export.json",
                isDirectory: false
            )
        )
    }

    private func pruneEvents(referenceDate: Date) {
        let cutoff = referenceDate.addingTimeInterval(-Self.retentionWindow)
        events.removeAll { $0.timestamp < cutoff }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directoryURL.path
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
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter {
            $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("flow-start-failure-")
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate) ?? .distantPast
    }

    private static func defaultDirectoryURL() -> URL {
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

    private static func reportFilename(date: Date, id: UUID) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "flow-start-failure-\(timestamp)-\(id.uuidString.lowercased()).json"
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

// FlowFailureDiagnostics.swift
// OSGKeyboard · Shared
//
// Process-agnostic entry point for Flow start diagnostics.
//
// The host app owns the start path, but the keyboard extension is the process
// that actually witnesses a failed handoff — and the only one still running
// when the host was never launched. Both sides funnel breadcrumbs and terminal
// failures through here so a single export in Settings carries both timelines.

import Foundation

/// Keyboard→host request for a companion breadcrumb dump.
public struct FlowDiagnosticsDumpRequest: Codable, Equatable, Sendable {
    public let requestedAt: Date
    public let reason: String

    public init(requestedAt: Date, reason: String) {
        self.requestedAt = requestedAt
        self.reason = reason
    }
}

public enum FlowFailureDiagnostics {
    /// Dump requests older than this are stale — the host was not running when
    /// the keyboard asked, and this is a later, unrelated launch.
    public static let dumpRequestMaxAge: TimeInterval = 30

    // MARK: - Breadcrumbs

    public static func record(_ message: String) {
        FlowFailureLogStore.shared.record(message)
    }

    /// When this process last wrote a report.
    public static func lastReportPersistedAt() -> Date? {
        FlowFailureLogStore.shared.lastReportPersistedAt()
    }

    // MARK: - Terminal failures

    /// Writes a report for a start attempt that reached a user-visible dead end.
    /// Always merges the cross-process App Group snapshot into `context`, so a
    /// report is diagnostic even when the other process left no breadcrumbs.
    @discardableResult
    public static func persistStartupFailure(
        reason: String,
        context: [String: String]
    ) -> URL? {
        let merged = bridgeContext().merging(context) { _, explicit in explicit }
        let url = FlowFailureLogStore.shared.persistStartupFailure(
            reason: reason,
            context: merged
        )
        if let url {
            OSGDiag.log(
                "Flow startup failure report saved file=\(url.lastPathComponent)",
                category: "flow"
            )
        } else {
            OSGDiag.log("Flow startup failure report could not be saved", category: "flow")
        }
        return url
    }

    /// Keyboard side: persist locally, then ask the host for its own window.
    @discardableResult
    public static func persistKeyboardStartupFailure(
        reason: String,
        context: [String: String]
    ) -> URL? {
        let url = persistStartupFailure(reason: reason, context: context)
        requestHostSnapshot(reason: reason)
        return url
    }

    // MARK: - Cross-process companion dump

    public static func requestHostSnapshot(
        reason: String,
        now: Date = Date(),
        defaults: UserDefaults? = nil
    ) {
        guard let defaults = defaults ?? AppGroup.defaultsIfAvailable else { return }
        let request = FlowDiagnosticsDumpRequest(requestedAt: now, reason: reason)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(request) else { return }
        defaults.set(data, forKey: FlowSessionKeys.flowDiagnosticsDumpRequest)
        FlowSessionDarwin.postDiagnosticsDumpRequested()
    }

    /// Consumes a pending dump request. Returns `nil` when there is none or the
    /// request is older than `dumpRequestMaxAge` (a request left behind while
    /// the host was dead must not make a later launch write a bogus report).
    public static func consumeHostSnapshotRequest(
        now: Date = Date(),
        maxAge: TimeInterval = dumpRequestMaxAge,
        defaults: UserDefaults? = nil
    ) -> FlowDiagnosticsDumpRequest? {
        guard let defaults = defaults ?? AppGroup.defaultsIfAvailable else { return nil }
        guard let data = defaults.data(forKey: FlowSessionKeys.flowDiagnosticsDumpRequest) else {
            return nil
        }
        defaults.removeObject(forKey: FlowSessionKeys.flowDiagnosticsDumpRequest)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let request = try? decoder.decode(FlowDiagnosticsDumpRequest.self, from: data) else {
            return nil
        }
        guard now.timeIntervalSince(request.requestedAt) <= maxAge else { return nil }
        return request
    }

    // MARK: - Shared context

    /// Everything about the handoff that is observable from either process.
    public static func bridgeContext() -> [String: String] {
        let memory = OSGDiag.memorySnapshot()
        var context: [String: String] = [
            "process": FlowDiagnosticsProcess.current.rawValue,
            "appGroupAvailable": AppGroup.isAvailable ? "true" : "false",
            "rssMB": String(format: "%.1f", memory.rssMB),
            "physicalFootprintMB": String(format: "%.1f", memory.physFootprintMB)
        ]
        guard AppGroup.isAvailable else { return context }

        context["hostReady"] = FlowSessionBridge.isHostReady() ? "true" : "false"
        context["hostReachable"] = FlowSessionBridge.isHostReachable() ? "true" : "false"
        context["hostStale"] = FlowSessionBridge.isHostStale() ? "true" : "false"
        context["hostHeavy"] = FlowSessionBridge.isHostHeavy() ? "true" : "false"
        context["bridgeSessionActive"] = FlowSessionBridge.isSessionActive() ? "true" : "false"
        context["keyboardRecordingState"] = FlowSessionBridge.recordingState().rawValue
        context["pipArmInCooldown"] = FlowSessionBridge.isPiPArmInCooldown() ? "true" : "false"
        context["heartbeatStalenessSeconds"] = FlowSessionBridge.heartbeatStaleness()
            .map { String(format: "%.3f", $0) } ?? "nil"
        if let snapshot = FlowSessionBridge.readySnapshot() {
            context["readyReason"] = snapshot.reason.rawValue
            context["readyEngineMode"] = snapshot.engineMode
            context["readySnapshotReady"] = snapshot.ready ? "true" : "false"
        } else {
            context["readyReason"] = "nil"
        }
        return context
    }
}

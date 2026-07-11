// FlowDebugPanel.swift
// OSGKeyboard · Shared
//
// TEMPORARY debug overlay for cross-process Flow state. Remove after the
// orange-mic investigation. Shows the same App Group contract fields on both
// the host app and the keyboard extension so we can see where they diverge.

import SwiftUI

/// One labeled row in the temporary Flow debug panel.
public struct FlowDebugRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// Builds the App Group half of the debug snapshot (readable from both processes).
public enum FlowDebugAppGroupSnapshot {
    public static func rows(defaults: UserDefaults? = nil) -> [FlowDebugRow] {
        FlowSessionBridge.reloadFromDisk(defaults: defaults)
        let snapshot = FlowSessionBridge.readySnapshot(defaults: defaults)
        let staleness = FlowSessionBridge.heartbeatStaleness(defaults: defaults)
        let generation = FlowSessionBridge.currentHostGeneration(defaults: defaults)
        let shortGen: String = {
            guard let generation, generation.count >= 8 else { return generation ?? "nil" }
            return String(generation.prefix(8))
        }()
        let snapGen: String = {
            guard let g = snapshot?.hostGeneration, g.count >= 8 else {
                return snapshot?.hostGeneration ?? "nil"
            }
            return String(g.prefix(8))
        }()
        let expires: String = {
            guard let ts = FlowSessionBridge.sessionExpiresAt(defaults: defaults) else { return "nil" }
            let remaining = ts - Date().timeIntervalSince1970
            return String(format: "%.0fs", remaining)
        }()

        return [
            FlowDebugRow("sessionActive", FlowSessionBridge.isSessionActive(defaults: defaults) ? "1" : "0"),
            FlowDebugRow("expiresIn", expires),
            FlowDebugRow("hostReachable", FlowSessionBridge.isHostReachable(defaults: defaults) ? "1" : "0"),
            FlowDebugRow("hostReady", FlowSessionBridge.isHostReady(defaults: defaults) ? "1" : "0"),
            FlowDebugRow("hostStale", FlowSessionBridge.isHostStale(defaults: defaults) ? "1" : "0"),
            FlowDebugRow("hbStale", staleness.map { String(format: "%.1fs", $0) } ?? "nil"),
            FlowDebugRow("snap.ready", snapshot.map { $0.ready ? "1" : "0" } ?? "nil"),
            FlowDebugRow("snap.reason", snapshot?.reason.rawValue ?? "nil"),
            FlowDebugRow("snap.session", shortUUID(snapshot?.sessionId)),
            FlowDebugRow("gen.now", shortGen),
            FlowDebugRow("gen.snap", snapGen),
            FlowDebugRow("gen.match", {
                guard let a = snapshot?.hostGeneration,
                      let b = generation else { return "n/a" }
                return a == b ? "1" : "0"
            }()),
            FlowDebugRow("pendingHost", FlowSessionBridge.pendingHostBundleId(defaults: defaults) ?? "nil"),
            FlowDebugRow("recState", FlowSessionBridge.recordingState(defaults: defaults).rawValue),
            FlowDebugRow("appGroup", AppGroup.isAvailable ? "1" : "0")
        ]
    }

    private static func shortUUID(_ id: UUID?) -> String {
        guard let id else { return "nil" }
        return String(id.uuidString.prefix(8))
    }
}

/// Collapsible monospaced status panel. Temporary — for investigation only.
public struct FlowDebugPanel: View {
    public let title: String
    public let rows: [FlowDebugRow]
    @Binding public var isExpanded: Bool
    public var maxContentHeight: CGFloat

    public init(
        title: String,
        rows: [FlowDebugRow],
        isExpanded: Binding<Bool>,
        maxContentHeight: CGFloat = 180
    ) {
        self.title = title
        self.rows = rows
        self._isExpanded = isExpanded
        self.maxContentHeight = maxContentHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "▼" : "▶")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Spacer(minLength: 0)
                    Text(summaryChip)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(summaryColor)
                }
                .foregroundStyle(Color.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 6) {
                                Text(row.label)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 92, alignment: .leading)
                                Text(row.value)
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(maxHeight: maxContentHeight)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.7), lineWidth: 1)
        )
    }

    private var summaryChip: String {
        let hostReady = rows.first(where: { $0.label == "hostReady" })?.value
            ?? rows.first(where: { $0.label == "bridgeReady" })?.value
            ?? "?"
        let mic = rows.first(where: { $0.label == "mic" })?.value
        if let mic {
            return "mic=\(shortMic(mic)) hr=\(hostReady)"
        }
        let active = rows.first(where: { $0.label == "isActive" })?.value ?? "?"
        return "active=\(active) hr=\(hostReady)"
    }

    private var summaryColor: Color {
        let hostReady = rows.first(where: { $0.label == "hostReady" })?.value
            ?? rows.first(where: { $0.label == "bridgeReady" })?.value
        if hostReady == "1" { return .green }
        return .orange
    }

    private func shortMic(_ value: String) -> String {
        if value.hasPrefix("ready") { return "ready" }
        if value.contains("preparing") { return "prep" }
        if value.contains("hostNotReady") { return "notReady" }
        if value.contains("recording") { return "rec" }
        if value.contains("processing") { return "proc" }
        if value.contains("noFullAccess") { return "noFA" }
        if value.contains("appGroup") { return "noAG" }
        if value.contains("missingAPIKey") { return "noKey" }
        return String(value.prefix(12))
    }
}

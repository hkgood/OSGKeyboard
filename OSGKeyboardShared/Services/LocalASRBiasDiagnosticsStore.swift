// LocalASRBiasDiagnosticsStore.swift
// OSGKeyboard · Shared
//
// Persists the most recent local ASR bias diagnostics for settings / debug UI.

import Foundation

public struct LocalASRBiasDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public var capturedAt: Date
    public var modelId: String?
    public var backendLabel: String?
    public var diagnostics: LocalASRBiasDiagnostics
    public var hotwordCount: Int
    public var promptBiasLength: Int

    public init(
        capturedAt: Date = Date(),
        modelId: String? = nil,
        backendLabel: String? = nil,
        diagnostics: LocalASRBiasDiagnostics,
        hotwordCount: Int = 0,
        promptBiasLength: Int = 0
    ) {
        self.capturedAt = capturedAt
        self.modelId = modelId
        self.backendLabel = backendLabel
        self.diagnostics = diagnostics
        self.hotwordCount = hotwordCount
        self.promptBiasLength = promptBiasLength
    }
}

public enum LocalASRBiasDiagnosticsStore {
    private static let defaultsKey = "mac.localASR.lastBiasDiagnostics"

    public static func save(payload: LocalASRBiasPayload, modelId: String?, backendLabel: String?) {
        let snapshot = LocalASRBiasDiagnosticsSnapshot(
            modelId: modelId,
            backendLabel: backendLabel,
            diagnostics: payload.diagnostics,
            hotwordCount: payload.hardHotwords.count,
            promptBiasLength: payload.promptBias?.count ?? 0
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    public static func load() -> LocalASRBiasDiagnosticsSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LocalASRBiasDiagnosticsSnapshot.self, from: data)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

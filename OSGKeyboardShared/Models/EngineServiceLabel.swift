// EngineServiceLabel.swift
// OSGKeyboard · Shared
//
// Human-readable summary of the active engine / AI provider for UI hints.

import Foundation

public enum EngineServiceLabel {
    public static func summary(
        engineMode: String,
        providerId: String,
        model: String
    ) -> String {
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        let prefix = isChinese ? "当前：" : "Active: "
        if engineMode == "local" {
            return isChinese
                ? "\(prefix)本地引擎 · Apple SpeechAnalyzer"
                : "\(prefix)On-device · Apple SpeechAnalyzer"
        }
        let providerName = ProviderDisplayName.name(for: providerId)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty { return "\(prefix)\(providerName)" }
        return "\(prefix)\(providerName) · \(trimmedModel)"
    }
}

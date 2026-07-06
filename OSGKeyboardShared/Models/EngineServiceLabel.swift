// EngineServiceLabel.swift
// OSGKeyboard · Shared
//
// Human-readable summary of the active engine / AI provider for UI hints.

import Foundation

public enum EngineServiceLabel {
    public static func summary(
        engineMode: String,
        providerId: String,
        model: String,
        language: AppUILanguage? = nil
    ) -> String {
        let lang = language ?? AppGroupStore().uiLanguage
        if engineMode == "local" {
            let asrName = SharedL10n.string("engine.asr.appleSpeech", language: lang)
            return SharedL10n.format("engine.summary.local", language: lang, asrName)
        }
        let providerName = ProviderDisplayName.name(for: providerId, language: lang)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty {
            return SharedL10n.format("engine.summary.cloud", language: lang, providerName)
        }
        return SharedL10n.format(
            "engine.summary.cloudWithModel",
            language: lang,
            providerName,
            trimmedModel
        )
    }
}

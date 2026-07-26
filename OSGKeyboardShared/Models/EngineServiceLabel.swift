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
        asrProviderId: String? = nil,
        asrModel: String? = nil,
        language: AppUILanguage? = nil
    ) -> String {
        let lang = language ?? AppGroupStore().uiLanguage
        if engineMode == "local" {
            let asrName = SharedL10n.string("engine.asr.appleSpeech", language: lang)
            return SharedL10n.format("engine.summary.local", language: lang, asrName)
        }
        // Cloud status line should name the speech engine, not the polish LLM.
        let resolvedASRProvider: String = {
            if let asrProviderId, !asrProviderId.isEmpty { return asrProviderId }
            return providerId
        }()
        let resolvedASRModel: String = {
            if let asrModel, !asrModel.isEmpty { return asrModel }
            return model
        }()
        let providerName = ProviderDisplayName.name(for: resolvedASRProvider, language: lang)
        let trimmedModel = resolvedASRModel.trimmingCharacters(in: .whitespacesAndNewlines)
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

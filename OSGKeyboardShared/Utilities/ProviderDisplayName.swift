// ProviderDisplayName.swift
// OSGKeyboard · Shared
//
// Locale-aware provider labels for settings and status hints.

import Foundation

public enum ProviderDisplayName {
    public static func name(
        for providerId: String,
        language: AppUILanguage? = nil
    ) -> String {
        let key = "provider.\(providerId)"
        let localized = SharedL10n.string(key, language: language)
        if localized != key { return localized }
        return LLMProvider.provider(id: providerId).name
    }
}

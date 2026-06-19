// ProviderDisplayName.swift
// OSGKeyboard · Shared
//
// Locale-aware provider labels for settings and status hints.

import Foundation

public enum ProviderDisplayName {
    public static func name(for providerId: String) -> String {
        let key = "provider.\(providerId)"
        let localized = NSLocalizedString(key, comment: "")
        if localized != key { return localized }
        return LLMProvider.provider(id: providerId).name
    }
}

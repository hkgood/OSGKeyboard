// SpeechLocaleResolver.swift
// OSGKeyboard · Shared
//
// Maps persisted `localeId` settings to a `Locale` suitable for
// `DictationTranscriber.supportedLocale(equivalentTo:)`.

import Foundation

public enum SpeechLocaleResolver {
    /// Resolve a stored locale id (`auto`, `zh-Hans`, …) for on-device ASR.
    public static func resolve(_ localeId: String) -> Locale {
        let raw: String
        if localeId == "auto" {
            raw = Locale.preferredLanguages.first ?? "en-US"
        } else {
            raw = localeId
        }
        let normalized = raw.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh") { return Locale(identifier: "zh-Hans") }
        if normalized.hasPrefix("ja") { return Locale(identifier: "ja-JP") }
        if normalized.hasPrefix("ko") { return Locale(identifier: "ko-KR") }
        if normalized.hasPrefix("en") { return Locale(identifier: "en-US") }
        return Locale(identifier: raw.replacingOccurrences(of: "_", with: "-"))
    }
}

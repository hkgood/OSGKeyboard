// ASRLocaleLabels.swift
// OSGKeyboard · Main App
//
// Human-readable labels for ASR locale picker rows. Honors the in-app
// UI language override instead of caching strings at load time.

import Foundation
import OSGKeyboardShared

enum ASRLocaleLabels {
    private static let bundledKeys: [String: String] = [
        "auto": "locale.auto",
        "zh-Hans": "locale.zh-Hans",
        "zh-Hant": "locale.zh-Hant",
        "en-US": "locale.en-US",
        "ja-JP": "locale.ja-JP",
        "ko-KR": "locale.ko-KR",
    ]

    static func displayName(for localeId: String, language: AppUILanguage) -> String {
        if let key = bundledKeys[localeId] {
            return AppUILanguage.localizedString(
                key,
                tableName: nil,
                bundle: .main,
                language: language
            )
        }
        let uiLocale = Locale(identifier: language.resolvedLanguageCode())
        return uiLocale.localizedString(forIdentifier: localeId) ?? localeId
    }
}

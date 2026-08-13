// TypingInputConfiguration.swift
// OSGKeyboard · Shared
//
// App Group-backed Chinese input settings shared by the host app and
// keyboard extension. Fuzzy pairs are opt-in to avoid noisy candidates.

import Foundation
import Combine

public enum TypingInputSchema: String, CaseIterable, Identifiable, Codable, Sendable {
    case fullPinyin = "osg_pinyin"
    case microsoftDoublePinyin = "osg_double_pinyin_mspy"
    case sogouDoublePinyin = "osg_double_pinyin_sogou"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .fullPinyin: return "全"
        case .microsoftDoublePinyin: return "微"
        case .sogouDoublePinyin: return "搜"
        }
    }

    /// Stable Rime schema `name:` (not UI copy). Keep Chinese so redeploy fingerprints stay stable.
    public var displayName: String {
        switch self {
        case .fullPinyin: return "全拼"
        case .microsoftDoublePinyin: return "微软双拼"
        case .sogouDoublePinyin: return "搜狗双拼"
        }
    }

    /// Localizable UI label key (`AppL10n` / `SharedL10n`).
    public var labelKey: String {
        switch self {
        case .fullPinyin: return "typing.schema.fullPinyin"
        case .microsoftDoublePinyin: return "typing.schema.microsoftDoublePinyin"
        case .sogouDoublePinyin: return "typing.schema.sogouDoublePinyin"
        }
    }
}

/// Default keyboard open mode when "remember last" is off.
public enum DefaultInputMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case voice
    case pinyin
    case english

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .voice: return "settings.typingInput.default.mode.voice"
        case .pinyin: return "settings.typingInput.default.mode.pinyin"
        case .english: return "settings.typingInput.default.mode.english"
        }
    }

    public var surface: KeyboardState.Surface {
        switch self {
        case .voice: return .voice
        case .pinyin, .english: return .typing
        }
    }

    public var typingLanguage: TypingInputLanguage? {
        switch self {
        case .voice: return nil
        case .pinyin: return .chinese
        case .english: return .english
        }
    }
}

public enum PinyinFuzzyPair: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhZ
    case chC
    case shS
    case nL
    case fH
    case anAng
    case enEng
    case inIng

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zhZ: return "zh ↔ z"
        case .chC: return "ch ↔ c"
        case .shS: return "sh ↔ s"
        case .nL: return "n ↔ l"
        case .fH: return "f ↔ h"
        case .anAng: return "an ↔ ang"
        case .enEng: return "en ↔ eng"
        case .inIng: return "in ↔ ing"
        }
    }
}

public struct TypingInputConfigurationSnapshot: Equatable, Sendable {
    public let schema: TypingInputSchema
    public let fuzzyPairs: Set<PinyinFuzzyPair>

    public init(schema: TypingInputSchema, fuzzyPairs: Set<PinyinFuzzyPair>) {
        self.schema = schema
        self.fuzzyPairs = fuzzyPairs
    }
}

@MainActor
public final class TypingInputConfiguration: ObservableObject {
    public static let shared = TypingInputConfiguration()

    private enum Key {
        static let schema = "typing.input.schema"
        static let fuzzyPairs = "typing.input.fuzzyPairs"
        /// Legacy bool; migrated into `defaultInputMode` (true → pinyin).
        static let defaultToTyping = "typing.input.defaultToTyping"
        static let defaultInputMode = "typing.input.defaultInputMode"
        static let rememberLastSurface = "typing.input.rememberLastSurface"
        static let lastSurface = "typing.input.lastSurface"
        static let lastTypingLanguage = "typing.input.lastTypingLanguage"
        static let resourceVersion = "typing.rime.resourceVersion"
        static let personalDictionaryFingerprint = "typing.rime.personalDictionaryFingerprint"
    }

    private let defaults: UserDefaults
    private var isHydrating = true

    @Published public var schema: TypingInputSchema {
        didSet { persistIfReady() }
    }

    @Published public var fuzzyPairs: Set<PinyinFuzzyPair> {
        didSet { persistIfReady() }
    }

    /// Static open preference when `rememberLastSurface` is off.
    /// Ignored when remembering and a prior surface was saved.
    @Published public var defaultInputMode: DefaultInputMode {
        didSet { persistIfReady() }
    }

    /// When on, reopen on the voice/typing/AI surface (and typing language) left last time.
    @Published public var rememberLastSurface: Bool {
        didSet { persistIfReady() }
    }

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroup.defaults
        let schemaId = self.defaults.string(forKey: Key.schema) ?? ""
        schema = TypingInputSchema(rawValue: schemaId) ?? .fullPinyin
        let fuzzyIds = self.defaults.stringArray(forKey: Key.fuzzyPairs) ?? []
        fuzzyPairs = Set(fuzzyIds.compactMap(PinyinFuzzyPair.init(rawValue:)))
        defaultInputMode = Self.resolveDefaultInputMode(from: self.defaults)
        rememberLastSurface = self.defaults.bool(forKey: Key.rememberLastSurface)
        isHydrating = false
    }

    public var snapshot: TypingInputConfigurationSnapshot {
        TypingInputConfigurationSnapshot(schema: schema, fuzzyPairs: fuzzyPairs)
    }

    public func setFuzzyPair(_ pair: PinyinFuzzyPair, enabled: Bool) {
        if enabled {
            fuzzyPairs.insert(pair)
        } else {
            fuzzyPairs.remove(pair)
        }
    }

    public func reload() {
        isHydrating = true
        schema = TypingInputSchema(rawValue: defaults.string(forKey: Key.schema) ?? "")
            ?? .fullPinyin
        let fuzzyIds = defaults.stringArray(forKey: Key.fuzzyPairs) ?? []
        fuzzyPairs = Set(fuzzyIds.compactMap(PinyinFuzzyPair.init(rawValue:)))
        defaultInputMode = Self.resolveDefaultInputMode(from: defaults)
        rememberLastSurface = defaults.bool(forKey: Key.rememberLastSurface)
        isHydrating = false
    }

    /// Legacy helper: true when the static default opens on the typing surface.
    nonisolated public static func prefersTypingOnOpen(
        defaults: UserDefaults? = nil
    ) -> Bool {
        resolveDefaultInputMode(from: defaults ?? AppGroup.defaultsIfAvailable).surface == .typing
    }

    nonisolated public static func remembersLastSurface(
        defaults: UserDefaults? = nil
    ) -> Bool {
        (defaults ?? AppGroup.defaultsIfAvailable)?.bool(forKey: Key.rememberLastSurface) ?? false
    }

    /// Surface to show on the first frame of a keyboard presentation.
    /// Prefer last-left surface when remembering; otherwise default input mode.
    nonisolated public static func preferredSurfaceOnOpen(
        defaults: UserDefaults? = nil
    ) -> KeyboardState.Surface {
        preferredOpenPreference(defaults: defaults).surface
    }

    /// Typing language to apply when opening onto the typing surface.
    nonisolated public static func preferredTypingLanguageOnOpen(
        defaults: UserDefaults? = nil
    ) -> TypingInputLanguage? {
        preferredOpenPreference(defaults: defaults).typingLanguage
    }

    nonisolated public static func preferredOpenPreference(
        defaults: UserDefaults? = nil
    ) -> (surface: KeyboardState.Surface, typingLanguage: TypingInputLanguage?) {
        let store = defaults ?? AppGroup.defaultsIfAvailable
        guard let store else { return (.voice, nil) }

        // AI is an explicit product surface. Restore it as an empty temporary
        // conversation even when the general "remember surface" toggle is off.
        if store.string(forKey: Key.lastSurface) == KeyboardState.Surface.ai.rawValue {
            return (.ai, nil)
        }

        if store.bool(forKey: Key.rememberLastSurface),
           let raw = store.string(forKey: Key.lastSurface),
           let surface = KeyboardState.Surface(rawValue: raw) {
            let language: TypingInputLanguage? = surface == .typing
                ? persistedTypingLanguage(defaults: store) ?? .chinese
                : nil
            return (surface, language)
        }

        let mode = resolveDefaultInputMode(from: store)
        return (mode.surface, mode.typingLanguage)
    }

    /// Persist the surface present when the keyboard leaves the screen.
    nonisolated public static func persistLastSurface(
        _ surface: KeyboardState.Surface,
        defaults: UserDefaults? = nil
    ) {
        (defaults ?? AppGroup.defaultsIfAvailable)?.set(surface.rawValue, forKey: Key.lastSurface)
    }

    /// Persist the typing language left on the typing surface.
    nonisolated public static func persistLastTypingLanguage(
        _ language: TypingInputLanguage,
        defaults: UserDefaults? = nil
    ) {
        (defaults ?? AppGroup.defaultsIfAvailable)?
            .set(language.rawValue, forKey: Key.lastTypingLanguage)
    }

    nonisolated public static func installedResourceVersion(
        defaults: UserDefaults? = nil
    ) -> String? {
        (defaults ?? AppGroup.defaultsIfAvailable)?.string(forKey: Key.resourceVersion)
    }

    nonisolated public static func setInstalledResourceVersion(
        _ value: String,
        defaults: UserDefaults? = nil
    ) {
        (defaults ?? AppGroup.defaultsIfAvailable)?.set(value, forKey: Key.resourceVersion)
    }

    nonisolated public static func installedPersonalDictionaryFingerprint(
        defaults: UserDefaults? = nil
    ) -> String? {
        (defaults ?? AppGroup.defaultsIfAvailable)?
            .string(forKey: Key.personalDictionaryFingerprint)
    }

    nonisolated public static func setInstalledPersonalDictionaryFingerprint(
        _ value: String,
        defaults: UserDefaults? = nil
    ) {
        (defaults ?? AppGroup.defaultsIfAvailable)?
            .set(value, forKey: Key.personalDictionaryFingerprint)
    }

    nonisolated private static func resolveDefaultInputMode(
        from defaults: UserDefaults?
    ) -> DefaultInputMode {
        guard let defaults else { return .voice }
        if let raw = defaults.string(forKey: Key.defaultInputMode),
           let mode = DefaultInputMode(rawValue: raw) {
            return mode
        }
        // Migrate legacy toggle: on → pinyin, off → voice.
        return defaults.bool(forKey: Key.defaultToTyping) ? .pinyin : .voice
    }

    nonisolated private static func persistedTypingLanguage(
        defaults: UserDefaults
    ) -> TypingInputLanguage? {
        guard let raw = defaults.string(forKey: Key.lastTypingLanguage) else { return nil }
        return TypingInputLanguage(rawValue: raw)
    }

    private func persistIfReady() {
        guard !isHydrating else { return }
        defaults.set(schema.rawValue, forKey: Key.schema)
        defaults.set(fuzzyPairs.map(\.rawValue).sorted(), forKey: Key.fuzzyPairs)
        defaults.set(defaultInputMode.rawValue, forKey: Key.defaultInputMode)
        // Keep legacy bool in sync for any older readers still checking it.
        defaults.set(defaultInputMode.surface == .typing, forKey: Key.defaultToTyping)
        defaults.set(rememberLastSurface, forKey: Key.rememberLastSurface)
        AppGroupConfigDarwin.postConfigChanged()
    }
}

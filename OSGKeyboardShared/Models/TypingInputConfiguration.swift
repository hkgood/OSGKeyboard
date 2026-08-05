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

    public var displayName: String {
        switch self {
        case .fullPinyin: return "全拼"
        case .microsoftDoublePinyin: return "微软双拼"
        case .sogouDoublePinyin: return "搜狗双拼"
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
        static let defaultToTyping = "typing.input.defaultToTyping"
        static let rememberLastSurface = "typing.input.rememberLastSurface"
        static let lastSurface = "typing.input.lastSurface"
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

    /// Selects the text keyboard whenever the extension becomes visible.
    /// Ignored when `rememberLastSurface` is on and a prior surface was saved.
    @Published public var defaultToTyping: Bool {
        didSet { persistIfReady() }
    }

    /// When on, reopen on the voice/typing surface left at the last dismiss.
    @Published public var rememberLastSurface: Bool {
        didSet { persistIfReady() }
    }

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroup.defaults
        let schemaId = self.defaults.string(forKey: Key.schema) ?? ""
        schema = TypingInputSchema(rawValue: schemaId) ?? .fullPinyin
        let fuzzyIds = self.defaults.stringArray(forKey: Key.fuzzyPairs) ?? []
        fuzzyPairs = Set(fuzzyIds.compactMap(PinyinFuzzyPair.init(rawValue:)))
        defaultToTyping = self.defaults.bool(forKey: Key.defaultToTyping)
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
        defaultToTyping = defaults.bool(forKey: Key.defaultToTyping)
        rememberLastSurface = defaults.bool(forKey: Key.rememberLastSurface)
        isHydrating = false
    }

    /// Legacy helper for the default-to-typing toggle only (not full open policy).
    nonisolated public static func prefersTypingOnOpen(
        defaults: UserDefaults? = nil
    ) -> Bool {
        (defaults ?? AppGroup.defaultsIfAvailable)?.bool(forKey: Key.defaultToTyping) ?? false
    }

    nonisolated public static func remembersLastSurface(
        defaults: UserDefaults? = nil
    ) -> Bool {
        (defaults ?? AppGroup.defaultsIfAvailable)?.bool(forKey: Key.rememberLastSurface) ?? false
    }

    /// Surface to show on the first frame of a keyboard presentation.
    /// Prefer last-left surface when remembering; otherwise default-to-typing.
    nonisolated public static func preferredSurfaceOnOpen(
        defaults: UserDefaults? = nil
    ) -> KeyboardState.Surface {
        let store = defaults ?? AppGroup.defaultsIfAvailable
        guard let store else { return .voice }

        if store.bool(forKey: Key.rememberLastSurface),
           let raw = store.string(forKey: Key.lastSurface),
           let surface = KeyboardState.Surface(rawValue: raw) {
            return surface
        }

        return store.bool(forKey: Key.defaultToTyping) ? .typing : .voice
    }

    /// Persist the surface present when the keyboard leaves the screen.
    nonisolated public static func persistLastSurface(
        _ surface: KeyboardState.Surface,
        defaults: UserDefaults? = nil
    ) {
        (defaults ?? AppGroup.defaultsIfAvailable)?.set(surface.rawValue, forKey: Key.lastSurface)
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

    private func persistIfReady() {
        guard !isHydrating else { return }
        defaults.set(schema.rawValue, forKey: Key.schema)
        defaults.set(fuzzyPairs.map(\.rawValue).sorted(), forKey: Key.fuzzyPairs)
        defaults.set(defaultToTyping, forKey: Key.defaultToTyping)
        defaults.set(rememberLastSurface, forKey: Key.rememberLastSurface)
        AppGroupConfigDarwin.postConfigChanged()
    }
}
